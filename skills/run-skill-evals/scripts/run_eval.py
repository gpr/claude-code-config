#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Run the eval loop described by agentskills.io's evaluating-skills.md.

For each test case in <skill>/evals/evals.json, this spawns two fresh,
non-interactive `claude -p` runs (one with the skill loaded as an appended
system prompt, one without) against the same prompt, grades the output
against the case's assertions with a third `claude -p` judge call, and
writes with_skill/without_skill outputs + timing.json + grading.json under
a workspace/iteration-N/ directory. It finishes by writing benchmark.json.

This calls out to the user's already-authenticated `claude` CLI — no API
key handling here. Every run uses --permission-mode bypassPermissions
because there is no human present to approve tool calls; only run this
against skills/prompts you trust.
"""

import argparse
import json
import statistics
import subprocess
import sys
from pathlib import Path


def run_claude(prompt, *, cwd, model=None, system_prompt=None, json_schema=None, timeout=600):
    cmd = ["claude", "-p", "--output-format", "json",
           "--permission-mode", "bypassPermissions",
           "--no-session-persistence"]
    if model:
        cmd += ["--model", model]
    if system_prompt:
        cmd += ["--append-system-prompt", system_prompt]
    if json_schema:
        cmd += ["--json-schema", json.dumps(json_schema)]
    cmd += [prompt]

    proc = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True, timeout=timeout)
    if proc.returncode != 0:
        raise RuntimeError(f"claude exited {proc.returncode}: {proc.stderr.strip()[:2000]}")

    line = next((l for l in reversed(proc.stdout.splitlines()) if l.strip().startswith("{")), None)
    if line is None:
        raise RuntimeError(f"no JSON object in claude output: {proc.stdout[:2000]}")
    return json.loads(line)


def total_tokens(usage):
    if not usage:
        return 0
    return sum(usage.get(k, 0) for k in (
        "input_tokens", "output_tokens",
        "cache_creation_input_tokens", "cache_read_input_tokens",
    ))


def do_run(prompt, *, cwd, model, system_prompt, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    result = run_claude(prompt, cwd=cwd, model=model, system_prompt=system_prompt)
    (out_dir / "outputs").mkdir(exist_ok=True)
    (out_dir / "outputs" / "response.txt").write_text(result.get("result", ""))
    timing = {
        "total_tokens": total_tokens(result.get("usage")),
        "duration_ms": result.get("duration_ms"),
    }
    (out_dir / "timing.json").write_text(json.dumps(timing, indent=2))
    return result.get("result", ""), timing


GRADING_SCHEMA = {
    "type": "object",
    "properties": {
        "assertion_results": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "text": {"type": "string"},
                    "passed": {"type": "boolean"},
                    "evidence": {"type": "string"},
                },
                "required": ["text", "passed", "evidence"],
            },
        },
    },
    "required": ["assertion_results"],
}


def grade(prompt, expected_output, assertions, output_text, *, cwd, model, out_dir):
    if not assertions:
        return None
    judge_prompt = (
        "You are grading an AI assistant's response against assertions. "
        "For each assertion, decide PASS or FAIL and quote concrete evidence "
        "from the response text. Do not give the benefit of the doubt.\n\n"
        f"Original user prompt:\n{prompt}\n\n"
        f"Expected output (human description of success):\n{expected_output}\n\n"
        f"Actual response to grade:\n{output_text}\n\n"
        f"Assertions to check:\n" + "\n".join(f"- {a}" for a in assertions)
    )
    result = run_claude(judge_prompt, cwd=cwd, model=model, json_schema=GRADING_SCHEMA)
    graded = json.loads(result["result"])
    passed = sum(1 for r in graded["assertion_results"] if r["passed"])
    total = len(graded["assertion_results"])
    graded["summary"] = {
        "passed": passed, "failed": total - passed, "total": total,
        "pass_rate": (passed / total) if total else 0.0,
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "grading.json").write_text(json.dumps(graded, indent=2))
    return graded


def next_iteration_dir(workspace):
    existing = [int(p.name.split("-")[1]) for p in workspace.glob("iteration-*") if p.name.split("-")[1].isdigit()]
    return workspace / f"iteration-{(max(existing) + 1) if existing else 1}"


def mean_stddev(values):
    values = [v for v in values if v is not None]
    if not values:
        return {"mean": None, "stddev": None}
    return {"mean": statistics.mean(values), "stddev": statistics.stdev(values) if len(values) > 1 else 0.0}


def aggregate(rows, iteration_dir):
    summary = {}
    for label in ("with_skill", "baseline"):
        pass_rates = [r["grading"][label]["summary"]["pass_rate"] for r in rows if r.get("grading", {}).get(label)]
        tokens = [r["timing"][label]["total_tokens"] for r in rows if r.get("timing", {}).get(label)]
        seconds = [r["timing"][label]["duration_ms"] / 1000 for r in rows if r.get("timing", {}).get(label) and r["timing"][label]["duration_ms"] is not None]
        summary[label] = {
            "pass_rate": mean_stddev(pass_rates),
            "time_seconds": mean_stddev(seconds),
            "tokens": mean_stddev(tokens),
        }
    delta = {}
    for key in ("pass_rate", "time_seconds", "tokens"):
        a, b = summary["with_skill"][key]["mean"], summary["baseline"][key]["mean"]
        delta[key] = (a - b) if (a is not None and b is not None) else None
    summary["delta"] = delta
    (iteration_dir / "benchmark.json").write_text(json.dumps({"run_summary": summary}, indent=2))
    return summary


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--skill", required=True, help="Path to the skill directory (contains SKILL.md and evals/evals.json)")
    ap.add_argument("--workspace", help="Workspace dir for run outputs (default: <skill>-workspace next to the skill)")
    ap.add_argument("--baseline-skill", help="Path to a previous version of the skill dir to use as baseline instead of no-skill")
    ap.add_argument("--model", help="Model override passed to every claude invocation")
    ap.add_argument("--ids", help="Comma-separated eval ids to run (default: all)")
    args = ap.parse_args()

    skill_dir = Path(args.skill).expanduser().resolve()
    skill_md = (skill_dir / "SKILL.md").read_text()
    evals_path = skill_dir / "evals" / "evals.json"
    evals_data = json.loads(evals_path.read_text())

    workspace = Path(args.workspace).expanduser().resolve() if args.workspace else skill_dir.parent / f"{skill_dir.name}-workspace"
    iteration_dir = next_iteration_dir(workspace)

    baseline_system_prompt = None
    baseline_label = "without_skill"
    if args.baseline_skill:
        baseline_system_prompt = (Path(args.baseline_skill).expanduser() / "SKILL.md").read_text()
        baseline_label = "old_skill"

    ids = {s.strip() for s in args.ids.split(",")} if args.ids else None
    rows = []

    for case in evals_data["evals"]:
        if ids is not None and str(case["id"]) not in ids:
            continue
        eval_dir = iteration_dir / f"eval-{case['id']}"
        print(f"[eval {case['id']}] with_skill run...", file=sys.stderr)
        with_text, with_timing = do_run(case["prompt"], cwd=skill_dir, model=args.model,
                                         system_prompt=skill_md, out_dir=eval_dir / "with_skill")
        print(f"[eval {case['id']}] {baseline_label} run...", file=sys.stderr)
        base_text, base_timing = do_run(case["prompt"], cwd=skill_dir, model=args.model,
                                         system_prompt=baseline_system_prompt, out_dir=eval_dir / baseline_label)

        assertions = case.get("assertions", [])
        print(f"[eval {case['id']}] grading with_skill...", file=sys.stderr)
        with_grading = grade(case["prompt"], case.get("expected_output", ""), assertions, with_text,
                              cwd=skill_dir, model=args.model, out_dir=eval_dir / "with_skill")
        print(f"[eval {case['id']}] grading {baseline_label}...", file=sys.stderr)
        base_grading = grade(case["prompt"], case.get("expected_output", ""), assertions, base_text,
                              cwd=skill_dir, model=args.model, out_dir=eval_dir / baseline_label)

        rows.append({
            "id": case["id"],
            "timing": {"with_skill": with_timing, "baseline": base_timing},
            "grading": {"with_skill": with_grading, "baseline": base_grading},
        })

    summary = aggregate(rows, iteration_dir)
    print(json.dumps({"iteration_dir": str(iteration_dir), "run_summary": summary}, indent=2))


if __name__ == "__main__":
    main()
