---
name: rtk-task-review
description: |
  Review whether RTK (the PreToolUse:Bash hook that compresses command output,
  e.g. grep/ls/cat) causes the agent to repeat near-duplicate Bash calls to
  compensate for lost detail, over a configurable lookback window. Links each
  Bash tool call in ~/.claude/projects transcripts to its RTK hook attachment,
  detects same-family/overlapping-target follow-up calls (a "repeat"), compares
  repeat rate on RTK-rewritten calls vs. an untreated same-session control
  group, checks dose-response against output truncation, and writes a
  self-contained HTML report + chart. Use when: user says "/rtk-task-review",
  "review RTK usage", "does RTK cause repeated tool calls", "does RTK make me
  re-run grep/ls more", "rerun the RTK analysis".
argument-hint: "[days back, default 30]"
author: Claude Code
version: 2.0.0
date: 2026-08-14
---

## Arguments

`$ARGUMENTS` is the number of days back to review. If empty or not a positive
integer, default to 30.

## Steps

1. Run the bundled script (it needs matplotlib — use `uv run --with matplotlib`,
   no venv setup required):

   ```
   uv run --with matplotlib python3 ~/.claude/skills/rtk-task-review/scripts/rtk_task_review.py --days <N> --out <output-dir>
   ```

   Pick `<output-dir>` under the scratchpad/session temp dir unless the user
   names a permanent path. The script is read-only against
   `~/.claude/projects` and `~/Library/Application Support/rtk/history.db`
   (it copies the DB before querying) — it never mutates either.

2. The script prints treated/untreated repeat rates, the bootstrap CI on the
   gap between them, and the paths to four artifacts: `rtk_review_report.html`,
   `rtk_chart.png`, `rtk_analysis.json`, `retry_pairs_sample.csv`.

3. Report to the user in the ADHD-style format: lead with the treated vs.
   untreated repeat-rate gap and its 95% CI, then the report path. State it as
   an association, not causation — the untreated control group is thin and
   non-randomly selected (RTK skips a call mostly when it can't parse the
   arguments, which itself correlates with complexity) — the script's own HTML
   already says this, don't contradict it.

4. Point out that `retry_pairs_sample.csv` needs manual labeling
   (`compression_retry` / `wrong_query` / `deliberate_breadth` / `other`) before
   the repeat-rate numbers can be trusted — re-run with `--labels <path>` after
   labeling to get a flag-precision number. If the user hasn't labeled it yet,
   say the numbers are unvalidated rather than presenting them as settled.

5. If sample size is small (`n_treated` or `n_untreated` in the script's stdout
   is under ~20, or the CI is `n/a`), say so plainly — the comparison isn't
   reliable at that size.

## Notes

- Task unit is one Bash tool call, linked to its RTK hook attachment via the
  exact `toolUseID` <-> `tool_use.id` match (not just hook name — three
  different hooks share the `PreToolUse:Bash` name in `settings.json`; the
  actual RTK-treatment signal is `"RTK auto-rewrite" in attachment.stdout`).
- A "repeat" = same command family, overlapping target tokens (Jaccard ≥ 0.5),
  within 3 calls / 5 min, no intervening user message, the first call's result
  non-empty (rules out "the query was just wrong"), and not an exact re-run
  (that's a flake, not lost detail).
- This is correlational, not causal — RTK is on for the whole window, so there
  is no true before/after baseline in the data. `history.db` join coverage is
  partial (~13% historically) and corroborating only, never primary.
- Never write into `~/.claude/projects` or the live `history.db` — the script
  already guarantees this; don't add code paths that would.
