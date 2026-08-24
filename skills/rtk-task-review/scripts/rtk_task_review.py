#!/usr/bin/env python3
"""RTK compression-retry review.

Tests the hypothesis: does RTK's output compression on Bash calls (ls, grep, cat,
git, ...) cause the agent to re-run near-duplicate Bash commands to compensate for
lost detail? This replaces an earlier version of this script that only correlated
raw RTK usage against raw Bash-call *volume* per session/day — that test cannot
distinguish "RTK enabled more real work" from "RTK caused wasteful retries" (both
increment the same counter identically). See the methodology notes in SKILL.md.

Unit of analysis here is one Bash tool call, linked to its RTK hook attachment via
the exact `toolUseID` <-> `tool_use.id` match. For each call we ask: was it
RTK-rewritten ("treated"), and was it followed (within a short lookahead window, no
intervening user message, same command family, overlapping targets, non-empty first
result, not an exact re-run) by a near-duplicate call ("is_repeat")? We then compare
the repeat rate on treated vs. untreated calls (a same-session control group) and,
among treated calls only, whether repeat rate rises with how much the output was
truncated (dose-response).

Read-only against ~/.claude/projects and a *copy* of RTK's history.db — never
mutates either. history.db only corroborates (~13% coverage of RTK-rewritten calls
observed in transcripts) — it is not the primary dose signal.

Usage:
    uv run --with matplotlib python3 rtk_task_review.py --days 30 --out <dir>
"""
import argparse
import base64
import json
import random
import re
import shlex
import shutil
import sqlite3
import statistics
import tempfile
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

PROJECTS_DIR = Path.home() / ".claude" / "projects"
LIVE_HISTORY_DB = Path.home() / "Library" / "Application Support" / "rtk" / "history.db"

NONSIGNAL_FAMILIES = {"cd", "echo", "export", "set", "unset", "true", "false", "printf", "sleep"}
TRUNC_PATTERNS = [
    re.compile(r"\.\.\."),
    re.compile(r"\d+\s+more lines?", re.I),
    re.compile(r"truncat", re.I),
    re.compile(r"\[\d+\s+lines?\s+(hidden|omitted|truncated)", re.I),
]
LOOKAHEAD_CALLS = 3
LOOKAHEAD_SECONDS = 300  # 5 min
JACCARD_THRESHOLD = 0.5
HISTORY_DB_JOIN_TOLERANCE_S = 10
BOOTSTRAP_ITERS = 2000


def parse_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def split_segments(command):
    """Split a compound shell command on unquoted &&, ||, ;, | into segments."""
    segments = []
    buf = []
    quote = None
    i = 0
    n = len(command)
    while i < n:
        ch = command[i]
        if quote:
            buf.append(ch)
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            buf.append(ch)
            i += 1
            continue
        if command[i:i+2] in ("&&", "||"):
            segments.append("".join(buf))
            buf = []
            i += 2
            continue
        if ch in (";", "|"):
            segments.append("".join(buf))
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    if buf:
        segments.append("".join(buf))
    return [s.strip() for s in segments if s.strip()]


def family_and_targets(segment):
    """Return (family, target_token_set) for a shell segment, or (None, None) if not signal."""
    try:
        tokens = shlex.split(segment, posix=True)
    except ValueError:
        tokens = segment.split()
    # skip leading env-var assignments (FOO=bar cmd ...)
    idx = 0
    while idx < len(tokens) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[idx]):
        idx += 1
    tokens = tokens[idx:]
    if not tokens:
        return None, None
    family = tokens[0].lower()
    if family in NONSIGNAL_FAMILIES:
        return None, None
    targets = frozenset(t.lower() for t in tokens[1:] if not t.startswith("-"))
    return family, targets


def jaccard(a, b):
    if not a or not b:
        # No target tokens on one/both sides (e.g. bare `head -50` with no path/pattern) means
        # there's nothing informative to compare — two unrelated pipelines that both happen to
        # end in a flagless `head`/`tail`/`sort` must NOT be treated as a match.
        return 0.0
    inter = len(a & b)
    union = len(a | b)
    return inter / union if union else 0.0


def has_truncation_marker(text):
    if not text:
        return False
    return any(p.search(text) for p in TRUNC_PATTERNS)


def is_genuine_user_prompt(rec):
    if rec.get("type") != "user":
        return False
    if rec.get("isMeta"):
        return False
    content = (rec.get("message") or {}).get("content")
    if not isinstance(content, str):
        return False
    if content.strip().startswith("<local-command-"):
        return False
    return True


def extract_calls(path, cutoff, now):
    """Parse one session .jsonl, return list of call dicts within [cutoff, now]."""
    records = []
    try:
        with open(path, "r", errors="ignore") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except Exception:
                    records.append(None)
    except Exception as e:
        return None, f"read-error: {e}"

    # Pass 1: index tool_use blocks, hook_success attachments, tool_results, user-prompt markers.
    bash_tool_uses = {}  # id -> {command, timestamp, idx, cwd}
    hook_by_id = {}      # id -> {treated: bool}
    result_by_id = {}    # id -> {stdout, is_error}
    user_prompt_idx = set()

    for idx, rec in enumerate(records):
        if rec is None:
            continue
        rtype = rec.get("type")
        if rtype == "assistant":
            content = (rec.get("message") or {}).get("content")
            if isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("name") == "Bash":
                        tid = block.get("id")
                        ts = parse_ts(rec.get("timestamp") or "")
                        if tid and ts:
                            bash_tool_uses[tid] = {
                                "command": (block.get("input") or {}).get("command", ""),
                                "timestamp": ts,
                                "idx": idx,
                                "cwd": rec.get("cwd"),
                            }
        elif rtype == "attachment":
            att = rec.get("attachment") or {}
            if att.get("type") == "hook_success" and att.get("hookName") == "PreToolUse:Bash":
                tid = att.get("toolUseID")
                if tid:
                    stdout = att.get("stdout") or ""
                    treated = "RTK auto-rewrite" in stdout
                    # dedupe: keep the first hook_success seen per toolUseID
                    if tid not in hook_by_id:
                        hook_by_id[tid] = {"treated": treated}
        elif rtype == "user":
            if is_genuine_user_prompt(rec):
                user_prompt_idx.add(idx)
            content = (rec.get("message") or {}).get("content")
            tur = rec.get("toolUseResult")
            if isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_result":
                        tid = block.get("tool_use_id")
                        if tid:
                            stdout = ""
                            if isinstance(tur, dict):
                                stdout = tur.get("stdout") or ""
                            elif isinstance(block.get("content"), str):
                                stdout = block.get("content")
                            result_by_id[tid] = {
                                "stdout": stdout,
                                "is_error": bool(block.get("is_error")) or (isinstance(tur, dict) and tur.get("interrupted")),
                            }

    # Pass 2: build ordered call list, in window.
    calls = []
    for tid, tu in sorted(bash_tool_uses.items(), key=lambda kv: kv[1]["idx"]):
        ts = tu["timestamp"]
        if not (cutoff <= ts <= now):
            continue
        hook = hook_by_id.get(tid)
        result = result_by_id.get(tid, {})
        segments = []
        for seg in split_segments(tu["command"]):
            fam, targets = family_and_targets(seg)
            if fam:
                segments.append((fam, targets))
        calls.append({
            "session": str(path),
            "tool_use_id": tid,
            "command": tu["command"],
            "timestamp": ts,
            "idx": tu["idx"],
            "cwd": tu["cwd"],
            "treated": bool(hook and hook["treated"]),
            "hook_seen": hook is not None,
            "result_stdout": result.get("stdout", ""),
            "is_error": bool(result.get("is_error")),
            "segments": segments,
        })
    return calls, user_prompt_idx


def has_intervening_user_prompt(calls, i, j, user_prompt_positions):
    lo, hi = calls[i]["idx"], calls[j]["idx"]
    return any(lo < p < hi for p in user_prompt_positions)


def detect_repeats(calls, user_prompt_positions):
    """Mutate calls in place: set is_repeat, repeat_with for each call."""
    for i, c in enumerate(calls):
        c["is_repeat"] = False
        c["repeat_with"] = None
        if c["is_error"] or not c["result_stdout"].strip() or not c["segments"]:
            continue
        for j in range(i + 1, min(i + 1 + LOOKAHEAD_CALLS, len(calls))):
            other = calls[j]
            if (other["timestamp"] - c["timestamp"]).total_seconds() > LOOKAHEAD_SECONDS:
                break
            if other["is_error"]:
                continue
            if has_intervening_user_prompt(calls, i, j, user_prompt_positions):
                break  # a new human instruction landed between them: new intent, stop looking
            matched = False
            for fam_a, tgt_a in c["segments"]:
                for fam_b, tgt_b in other["segments"]:
                    if fam_a != fam_b:
                        continue
                    if jaccard(tgt_a, tgt_b) < JACCARD_THRESHOLD:
                        continue
                    if c["command"].strip() == other["command"].strip():
                        continue  # exact re-run: flake/env, not info loss
                    matched = True
                    break
                if matched:
                    break
            if matched:
                c["is_repeat"] = True
                c["repeat_with"] = other["tool_use_id"]
                break


def build_history_index(history_db_path):
    """Return list of (project_path, timestamp, saved_tokens, savings_pct) sorted by ts, per project."""
    by_project = defaultdict(list)
    if not history_db_path or not Path(history_db_path).exists():
        return by_project
    conn = sqlite3.connect(history_db_path)
    try:
        rows = conn.execute(
            "select project_path, timestamp, saved_tokens, savings_pct from commands"
        ).fetchall()
    finally:
        conn.close()
    for project_path, ts, saved, pct in rows:
        tsp = parse_ts(ts)
        if tsp:
            by_project[project_path].append((tsp, saved or 0, pct or 0.0))
    for k in by_project:
        by_project[k].sort(key=lambda r: r[0])
    return by_project


def nearest_history_match(by_project, cwd, ts):
    rows = by_project.get(cwd)
    if not rows:
        return None
    best, best_gap = None, None
    for row_ts, saved, pct in rows:
        gap = abs((row_ts - ts).total_seconds())
        if gap <= HISTORY_DB_JOIN_TOLERANCE_S and (best_gap is None or gap < best_gap):
            best, best_gap = (saved, pct), gap
    return best


def pearson(xs, ys):
    if len(xs) < 3 or statistics.pstdev(xs) == 0 or statistics.pstdev(ys) == 0:
        return None
    n = len(xs)
    mx, my = statistics.mean(xs), statistics.mean(ys)
    cov = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / n
    return cov / (statistics.pstdev(xs) * statistics.pstdev(ys))


def bootstrap_ci(session_groups, iters=BOOTSTRAP_ITERS, seed=1234):
    """Session-clustered bootstrap CI for treated_rate - untreated_rate, resampling sessions."""
    rng = random.Random(seed)
    sessions = list(session_groups.values())
    if len(sessions) < 3:
        return None
    diffs = []
    for _ in range(iters):
        sample = [sessions[rng.randrange(len(sessions))] for _ in sessions]
        a_hits = sum(s["treated_repeats"] for s in sample)
        a_n = sum(s["treated_n"] for s in sample)
        b_hits = sum(s["untreated_repeats"] for s in sample)
        b_n = sum(s["untreated_n"] for s in sample)
        if a_n == 0 or b_n == 0:
            continue
        diffs.append(a_hits / a_n - b_hits / b_n)
    if not diffs:
        return None
    diffs.sort()
    lo = diffs[int(0.025 * len(diffs))]
    hi = diffs[int(0.975 * len(diffs)) - 1]
    return lo, hi


def analyze(days, history_db_copy):
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(days=days)

    jsonl_files = list(PROJECTS_DIR.glob("*/*.jsonl"))
    # mtime is a *necessary* condition for "has any event after cutoff" (mtime = last
    # write time), so this prefilter has no false negatives; per-event filtering below
    # then keeps only in-window calls even from long-running/resumed sessions.
    candidates = [p for p in jsonl_files if datetime.fromtimestamp(p.stat().st_mtime, tz=timezone.utc) >= cutoff]

    all_calls = []
    read_errors = 0
    for p in candidates:
        calls, user_prompt_positions = extract_calls(p, cutoff, now)
        if calls is None:
            read_errors += 1
            continue
        if not calls:
            continue
        detect_repeats(calls, user_prompt_positions)
        all_calls.extend(calls)

    by_project = build_history_index(history_db_copy)
    for c in all_calls:
        if c["treated"] and c["cwd"]:
            match = nearest_history_match(by_project, c["cwd"], c["timestamp"])
            if match:
                c["saved_tokens"], c["savings_pct"] = match
            else:
                c["saved_tokens"], c["savings_pct"] = None, None
        else:
            c["saved_tokens"], c["savings_pct"] = None, None
        c["truncated"] = has_truncation_marker(c["result_stdout"])

    treated_calls = [c for c in all_calls if c["hook_seen"] is not None and not c["is_error"] and c["result_stdout"].strip() and c["segments"]]
    treated = [c for c in treated_calls if c["treated"]]
    untreated = [c for c in treated_calls if not c["treated"]]

    def rate(calls):
        return (sum(1 for c in calls if c["is_repeat"]) / len(calls)) if calls else None

    overall_treated_rate = rate(treated)
    overall_untreated_rate = rate(untreated)

    # per-family breakdown
    fam_stats = defaultdict(lambda: {"treated_n": 0, "treated_repeats": 0, "untreated_n": 0, "untreated_repeats": 0})
    for c in treated_calls:
        fams = {seg[0] for seg in c["segments"]}
        for fam in fams:
            key = fam_stats[fam]
            if c["treated"]:
                key["treated_n"] += 1
                key["treated_repeats"] += int(c["is_repeat"])
            else:
                key["untreated_n"] += 1
                key["untreated_repeats"] += int(c["is_repeat"])
    family_table = []
    for fam, s in sorted(fam_stats.items(), key=lambda kv: -(kv[1]["treated_n"] + kv[1]["untreated_n"])):
        family_table.append({
            "family": fam,
            "treated_n": s["treated_n"],
            "treated_rate": (s["treated_repeats"] / s["treated_n"]) if s["treated_n"] else None,
            "untreated_n": s["untreated_n"],
            "untreated_rate": (s["untreated_repeats"] / s["untreated_n"]) if s["untreated_n"] else None,
        })

    # session-clustered bootstrap CI on the treated-vs-untreated repeat-rate gap
    session_groups = defaultdict(lambda: {"treated_n": 0, "treated_repeats": 0, "untreated_n": 0, "untreated_repeats": 0})
    for c in treated_calls:
        g = session_groups[c["session"]]
        if c["treated"]:
            g["treated_n"] += 1
            g["treated_repeats"] += int(c["is_repeat"])
        else:
            g["untreated_n"] += 1
            g["untreated_repeats"] += int(c["is_repeat"])
    ci = bootstrap_ci(session_groups)

    # dose-response: among treated calls, repeat rate for truncated vs non-truncated output
    treated_truncated = [c for c in treated if c["truncated"]]
    treated_not_truncated = [c for c in treated if not c["truncated"]]
    dose_response = {
        "truncated_n": len(treated_truncated),
        "truncated_repeat_rate": rate(treated_truncated),
        "not_truncated_n": len(treated_not_truncated),
        "not_truncated_repeat_rate": rate(treated_not_truncated),
    }

    # history.db coverage among treated calls
    history_covered = sum(1 for c in treated if c.get("saved_tokens") is not None)

    return {
        "window_days": days,
        "window_start": cutoff.date().isoformat(),
        "window_end": now.date().isoformat(),
        "n_sessions": len({c["session"] for c in all_calls}),
        "n_files_read_error": read_errors,
        "n_calls_total": len(all_calls),
        "n_calls_analyzable": len(treated_calls),
        "n_treated": len(treated),
        "n_untreated": len(untreated),
        "overall_treated_repeat_rate": overall_treated_rate,
        "overall_untreated_repeat_rate": overall_untreated_rate,
        "repeat_rate_gap_ci95": ci,
        "family_table": family_table,
        "dose_response": dose_response,
        "history_db_coverage": {
            "treated_n": len(treated),
            "matched_n": history_covered,
            "coverage_pct": (history_covered / len(treated) * 100) if treated else None,
        },
        "all_calls": all_calls,
    }


def sample_for_validation(data, n=40, seed=7):
    """Pick a random sample of flagged is_repeat pairs for manual labeling."""
    flagged = [c for c in data["all_calls"] if c["is_repeat"]]
    rng = random.Random(seed)
    rng.shuffle(flagged)
    sample = flagged[:n]
    rows = []
    for c in sample:
        # find the matching "repeat_with" call in the same session for context
        peer_cmd = None
        for other in data["all_calls"]:
            if other["session"] == c["session"] and other["tool_use_id"] == c["repeat_with"]:
                peer_cmd = other["command"]
                break
        rows.append({
            "session": c["session"],
            "treated": c["treated"],
            "command": c["command"],
            "followed_by": peer_cmd,
            "label": "",  # fill in manually: compression_retry / wrong_query / deliberate_breadth / other
        })
    return rows


def write_labels_csv(rows, out_path):
    import csv
    with open(out_path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["session", "treated", "command", "followed_by", "label"])
        w.writeheader()
        for r in rows:
            w.writerow(r)


def read_labels_csv(path):
    import csv
    if not path or not Path(path).exists():
        return None
    with open(path, newline="") as fh:
        rows = list(csv.DictReader(fh))
    labeled = [r for r in rows if r.get("label", "").strip()]
    if not labeled:
        return None
    hits = sum(1 for r in labeled if r["label"].strip().lower() == "compression_retry")
    return {"n_labeled": len(labeled), "precision": hits / len(labeled)}


def fmt_pct(v):
    return "n/a" if v is None else f"{v * 100:.1f}%"


def fmt_r(v):
    return "n/a" if v is None else f"{v:+.2f}"


def render_chart(data, out_png):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    SURFACE = "#fcfcfb"
    TEXT_PRIMARY = "#0b0b0b"
    TEXT_SECONDARY = "#52514e"
    TREATED_COLOR = "#2a78d6"
    UNTREATED_COLOR = "#c3c2b7"
    GRID = "#e3e2dc"

    families = [f for f in data["family_table"] if (f["treated_n"] + f["untreated_n"]) >= 5][:8]

    fig, axes = plt.subplots(1, 2, figsize=(12, 5.4), facecolor=SURFACE)

    ax = axes[0]
    ax.set_facecolor(SURFACE)
    labels = [f["family"] for f in families]
    x = range(len(labels))
    treated_rates = [(-1 if f["treated_rate"] is None else f["treated_rate"]) for f in families]
    untreated_rates = [(-1 if f["untreated_rate"] is None else f["untreated_rate"]) for f in families]
    width = 0.35
    ax.bar([i - width / 2 for i in x], [max(0, v) for v in treated_rates], width, color=TREATED_COLOR, label="RTK-rewritten (treated)")
    ax.bar([i + width / 2 for i in x], [max(0, v) for v in untreated_rates], width, color=UNTREATED_COLOR, label="not rewritten (control)")
    ax.set_xticks(list(x))
    ax.set_xticklabels(labels, color=TEXT_SECONDARY, fontsize=9, rotation=20, ha="right")
    ax.set_title("Repeat rate by command family: treated vs control", color=TEXT_PRIMARY, fontsize=12, loc="left", pad=10)
    ax.set_ylabel("Repeat rate", color=TEXT_SECONDARY, fontsize=10)
    ax.tick_params(colors=TEXT_SECONDARY, labelsize=9)
    for spine in ["top", "right"]:
        ax.spines[spine].set_visible(False)
    for spine in ["left", "bottom"]:
        ax.spines[spine].set_color(GRID)
    ax.grid(True, axis="y", color=GRID, linewidth=0.8, alpha=0.7)
    ax.set_axisbelow(True)
    ax.legend(frameon=False, fontsize=8.5, labelcolor=TEXT_SECONDARY)
    ax.text(0.0, -0.34, "Families with <5 combined calls omitted (too thin to read).",
            transform=ax.transAxes, color=TEXT_SECONDARY, fontsize=8.5, style="italic")

    ax = axes[1]
    ax.set_facecolor(SURFACE)
    dr = data["dose_response"]
    cats = ["output truncated", "output not truncated"]
    vals = [dr["truncated_repeat_rate"] or 0, dr["not_truncated_repeat_rate"] or 0]
    ns = [dr["truncated_n"], dr["not_truncated_n"]]
    ax.bar(cats, vals, color=TREATED_COLOR, width=0.5)
    for i, (v, n) in enumerate(zip(vals, ns)):
        ax.text(i, v + 0.01, f"n={n}", ha="center", color=TEXT_SECONDARY, fontsize=9)
    ax.set_title("Dose-response: repeat rate vs output truncation\n(RTK-treated calls only)", color=TEXT_PRIMARY, fontsize=12, loc="left", pad=10)
    ax.set_ylabel("Repeat rate", color=TEXT_SECONDARY, fontsize=10)
    ax.tick_params(colors=TEXT_SECONDARY, labelsize=9)
    for spine in ["top", "right"]:
        ax.spines[spine].set_visible(False)
    for spine in ["left", "bottom"]:
        ax.spines[spine].set_color(GRID)
    ax.grid(True, axis="y", color=GRID, linewidth=0.8, alpha=0.7)
    ax.set_axisbelow(True)

    fig.tight_layout(rect=[0, 0.06, 1, 1])
    fig.savefig(out_png, dpi=180, facecolor=SURFACE, bbox_inches="tight")
    plt.close(fig)


def render_html(data, chart_png, labels_result, out_html):
    b64 = base64.b64encode(Path(chart_png).read_bytes()).decode("ascii")
    gap = None
    if data["overall_treated_repeat_rate"] is not None and data["overall_untreated_repeat_rate"] is not None:
        gap = data["overall_treated_repeat_rate"] - data["overall_untreated_repeat_rate"]
    ci = data["repeat_rate_gap_ci95"]
    ci_text = f"[{ci[0]*100:+.1f}pp, {ci[1]*100:+.1f}pp]" if ci else "n/a (too few sessions to bootstrap)"

    if labels_result:
        precision_text = f"{labels_result['precision']*100:.0f}% ({labels_result['n_labeled']} pairs labeled)"
        precision_note = ("Below this, treat the aggregate repeat-rate numbers above as unreliable — "
                           "re-check the flagging thresholds before trusting them.") if labels_result["precision"] < 0.6 else \
                          "High enough to treat the aggregate numbers as meaningful, not noise."
    else:
        precision_text = "not yet done"
        precision_note = ("A random sample of flagged pairs was written to " +
                           "<code>retry_pairs_sample.csv</code> next to this report — label each row "
                           "(compression_retry / wrong_query / deliberate_breadth / other) and re-run with "
                           "<code>--labels retry_pairs_sample.csv</code> to get a precision number. "
                           "Until then, the rates below are unvalidated.")

    family_rows = "".join(
        f"<tr><td>{f['family']}</td>"
        f"<td class='num'>{f['treated_n']}</td><td class='num'>{fmt_pct(f['treated_rate'])}</td>"
        f"<td class='num'>{f['untreated_n']}</td><td class='num'>{fmt_pct(f['untreated_rate'])}</td></tr>"
        for f in data["family_table"] if (f["treated_n"] + f["untreated_n"]) > 0
    )

    hdb = data["history_db_coverage"]

    html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>RTK compression-retry review — last {data['window_days']} days</title>
<style>
  :root {{
    --surface-1: #fcfcfb; --surface-2: #f3f2ee; --text-primary: #0b0b0b;
    --text-secondary: #52514e; --grid: #e3e2dc;
  }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; background: var(--surface-2); color: var(--text-primary);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; line-height: 1.5; }}
  main {{ max-width: 920px; margin: 0 auto; padding: 40px 24px 64px; }}
  h1 {{ font-size: 1.6rem; margin: 0 0 4px; }}
  .subtitle {{ color: var(--text-secondary); font-size: 0.95rem; margin: 0 0 28px; }}
  .card {{ background: var(--surface-1); border: 1px solid var(--grid); border-radius: 10px; padding: 24px 28px; margin-bottom: 24px; }}
  h2 {{ font-size: 1.05rem; margin: 0 0 12px; }}
  .verdict {{ display: flex; align-items: baseline; gap: 10px; margin-bottom: 8px; }}
  .verdict .badge {{ background: #eda100; color: white; font-size: 0.78rem; font-weight: 600;
    letter-spacing: 0.02em; padding: 3px 10px; border-radius: 999px; text-transform: uppercase; }}
  table {{ width: 100%; border-collapse: collapse; font-size: 0.9rem; margin: 12px 0 4px; }}
  th, td {{ text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--grid); }}
  th {{ color: var(--text-secondary); font-weight: 600; font-size: 0.82rem; }}
  td.num, th.num {{ text-align: right; font-variant-numeric: tabular-nums; }}
  img.chart {{ width: 100%; display: block; border-radius: 6px; margin: 8px 0 4px; }}
  .caption {{ color: var(--text-secondary); font-size: 0.85rem; }}
  ul {{ padding-left: 22px; margin: 8px 0; }}
  li {{ margin-bottom: 4px; }}
  code {{ background: var(--surface-2); border-radius: 4px; padding: 1px 5px; font-size: 0.85em; }}
  footer {{ color: var(--text-secondary); font-size: 0.8rem; margin-top: 32px; }}
</style>
</head>
<body>
<main>
  <h1>RTK compression-retry review — last {data['window_days']} days</h1>
  <p class="subtitle">Window: {data['window_start']} &rarr; {data['window_end']} &middot; Unit: one Bash tool call, linked
  to its RTK hook attachment by <code>toolUseID</code>.</p>

  <div class="card">
    <div class="verdict">
      <span class="badge">Association, not causation</span>
      <strong>Treated-call repeat rate: {fmt_pct(data['overall_treated_repeat_rate'])} &middot;
      untreated (control) repeat rate: {fmt_pct(data['overall_untreated_repeat_rate'])} &middot;
      gap: {('n/a' if gap is None else f'{gap*100:+.1f}pp')} (95% CI {ci_text})</strong>
    </div>
    <p class="caption">
      RTK is on for the entire window and dominates the exploration families (ls/rg/cat), so the
      "untreated" control group is thin and non-randomly selected (a call escapes rewriting mostly
      because RTK couldn't parse its arguments &mdash; itself correlated with complexity). Read the
      gap as an association among comparable calls, not a controlled experiment.
    </p>
  </div>

  <div class="card">
    <h2>Sample</h2>
    <ul>
      <li>{data['n_sessions']} sessions with Bash activity in the last {data['window_days']} days ({data['n_files_read_error']} files skipped on read error).</li>
      <li>{data['n_calls_total']} Bash calls total; {data['n_calls_analyzable']} analyzable (non-error, non-empty result, &ge;1 recognized command segment).</li>
      <li>{data['n_treated']} RTK-treated calls, {data['n_untreated']} untreated (control).</li>
      <li>history.db corroboration: matched {hdb['matched_n']}/{hdb['treated_n']} treated calls ({fmt_pct((hdb['coverage_pct'] or 0)/100) if hdb['coverage_pct'] is not None else 'n/a'} coverage) &mdash; corroborating only, not the primary dose signal.</li>
    </ul>
  </div>

  <div class="card">
    <h2>Repeat rate by command family</h2>
    <table>
      <thead><tr><th>Family</th><th class="num">Treated n</th><th class="num">Treated repeat rate</th><th class="num">Untreated n</th><th class="num">Untreated repeat rate</th></tr></thead>
      <tbody>{family_rows}</tbody>
    </table>
    <p class="caption">Families with a small untreated n have little control-group signal &mdash; read those rows as descriptive, not comparative.</p>
  </div>

  <div class="card">
    <h2>Chart</h2>
    <img class="chart" src="data:image/png;base64,{b64}" alt="Bar chart of repeat rate by family (treated vs control) and dose-response to output truncation">
  </div>

  <div class="card">
    <h2>Manual validation</h2>
    <p><strong>Flag precision: {precision_text}.</strong> {precision_note}</p>
  </div>

  <div class="card">
    <h2>Caveats</h2>
    <ul>
      <li>Correlational only &mdash; RTK is on for the whole window, no unrewritten baseline for the families it dominates.</li>
      <li>"Repeat" = same command family, target-token Jaccard &ge; {JACCARD_THRESHOLD}, within {LOOKAHEAD_CALLS} calls / {LOOKAHEAD_SECONDS//60} min, no intervening user message, first call's result non-empty, not an exact re-run. This heuristic can still misclassify deliberate breadth (grepping many dirs) as a retry &mdash; that's what manual validation above is for.</li>
      <li>history.db coverage is partial (~13% historically) and used only to corroborate, never as the primary signal.</li>
    </ul>
  </div>

  <footer>
    Generated from <code>~/.claude/projects/*/*.jsonl</code> and a copy of
    <code>~/Library/Application Support/rtk/history.db</code>.
  </footer>
</main>
</body>
</html>
"""
    Path(out_html).write_text(html)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--days", type=int, default=30, help="how many days back to review (default 30)")
    ap.add_argument("--out", type=str, default=None, help="output directory (default: a temp dir under $TMPDIR)")
    ap.add_argument("--labels", type=str, default=None, help="path to a previously hand-labeled retry_pairs_sample.csv, to compute flag precision")
    args = ap.parse_args()

    out_dir = Path(args.out) if args.out else Path(tempfile.mkdtemp(prefix="rtk-task-review-"))
    out_dir.mkdir(parents=True, exist_ok=True)

    history_db_copy = None
    if LIVE_HISTORY_DB.exists():
        tmp_dir = tempfile.mkdtemp(prefix="rtk-history-")
        history_db_copy = Path(tmp_dir) / "history.db"
        shutil.copy2(LIVE_HISTORY_DB, history_db_copy)

    data = analyze(args.days, history_db_copy)

    sample_rows = sample_for_validation(data)
    sample_csv = out_dir / "retry_pairs_sample.csv"
    write_labels_csv(sample_rows, sample_csv)
    labels_result = read_labels_csv(args.labels)

    # trim the heavy per-call list before dumping JSON (keep summary + a bounded sample)
    data_for_json = {k: v for k, v in data.items() if k != "all_calls"}
    data_for_json["n_calls_dumped"] = 0
    json_path = out_dir / "rtk_analysis.json"
    json_path.write_text(json.dumps(data_for_json, indent=2, default=str))

    png_path = out_dir / "rtk_chart.png"
    render_chart(data, png_path)

    html_path = out_dir / "rtk_review_report.html"
    render_html(data, png_path, labels_result, html_path)

    print(f"sessions={data['n_sessions']} calls={data['n_calls_total']} treated={data['n_treated']} untreated={data['n_untreated']} read_errors={data['n_files_read_error']}")
    print(f"treated_repeat_rate={fmt_pct(data['overall_treated_repeat_rate'])} untreated_repeat_rate={fmt_pct(data['overall_untreated_repeat_rate'])}")
    if data["repeat_rate_gap_ci95"]:
        lo, hi = data["repeat_rate_gap_ci95"]
        print(f"gap 95% CI: [{lo*100:+.1f}pp, {hi*100:+.1f}pp]")
    print(f"\nReport: {html_path}")
    print(f"Chart:  {png_path}")
    print(f"Data:   {json_path}")
    print(f"Validation sample ({len(sample_rows)} pairs) to label: {sample_csv}")


if __name__ == "__main__":
    main()
