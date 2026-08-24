---
name: git-commit
description: |
  Commit specified changes using conventional commit format.
  Use when: user says "commit", "commit this", "commit changes",
  "/commit", or asks to create a git commit. Handles scope selection,
  conventional commit type classification, and breaking change notation.
argument-hint: "[files, dirs, or context...]"
author: Claude Code
version: 2.1.0
date: 2026-08-17
---

## Arguments

If $ARGUMENTS names specific files or directories, stage them with `git add` before proceeding.
If $ARGUMENTS is descriptive context (not a path), use it to decide which staged or unstaged changes to commit.
If $ARGUMENTS is empty, work with whatever is already staged.

##  Context

Current git status: !`git status`
Current git diff (staged and unstaged changes): !`git diff HEAD`
Current branch: !`git branch --show-current`
Recent commits: !`git log --oneline -10`
Remote URLs: !`git remote -v 2>/dev/null | awk '{print $2}' | sort -u`
If the diff is empty, tell the user there's nothing to commit and stop.

## Rules

- Use `refactor` instead of `fix` for unreleased bugs
- Reserve `feat`, `perf`, `fix`, `style` for released source code only (not docs, tests, or config)
- Infer scope from the primary directory or module affected
- Use `!` for breaking changes, and include a description of the breaking change in the commit message body
- Subject: imperative mood, ≤72 chars, no trailing period
- Body: add when the "why" isn't obvious from the diff. Separate from subject with a blank line.
- Always append: `Co-Authored-By: Claude <model> <noreply@anthropic.com>` (replace `<model>` with the current model name)

## Session token trailers

Eligibility gate — check against `Remote URLs` from Context above: eligible if that list is
empty, or every entry matches `github.com[:/]gpr/`. Any other remote (including all Teads
remotes and forks) → skip this entire section silently. No trailers, no mention to the user.

If eligible, read session token usage before composing the commit message:

```bash
sid=<session id, from the scratchpad path in this agent's own context>
main=$(ls ~/.claude/projects/*/"$sid".jsonl 2>/dev/null)
subs=$(ls ~/.claude/projects/*/"$sid"/subagents/*.jsonl 2>/dev/null)

cat $main $subs 2>/dev/null | jq -s '
  [.[] | select(.type=="assistant" and .message.usage)]
  | group_by(.message.id) | map(.[0].message.usage)
  | {inp:   ((map(.input_tokens)|add) + (map(.cache_creation_input_tokens)|add)),
     cread: (map(.cache_read_input_tokens)|add),
     out:   (map(.output_tokens)|add)}'
```

`group_by(.message.id)` is required — a transcript has multiple raw entries per logical
message; summing without dedup roughly doubles every figure. Include subagent transcripts
(`<sid>/subagents/agent-*.jsonl`) — they can carry a large share of a session's tokens.

Empty/null output (statusline-independent — this can happen if the transcript is unreadable)
→ skip trailers for this commit, but still continue to the persistence step below with
whatever was computed (skip persistence too if nothing was computed).

Definitions:
- `in` = uncached `input_tokens` + `cache_creation_input_tokens` — new input the model had to ingest.
- `cached` = `cache_read_input_tokens` — kept separate because it dwarfs the rest and reflects context size, not work done.
- `out` = `output_tokens`.

Format each figure with a `k`/`M` suffix at one decimal above 1,000; plain integer below.

Compute the delta: read `$CLAUDE_TMPDIR/<project-slug>/<sid>/scratchpad/last-commit-tokens`
(three space-separated integers: `<in> <cached> <out>`). `Commit-Tokens` = session figures minus
stored figures, each floored at 0. If the file is absent, `Commit-Tokens` equals `Session-Tokens`.

If eligible and figures were computed, append below the `Co-Authored-By` line:

```
Session-Tokens: 79.1k in / 1.4M cached / 12.8k out
Commit-Tokens: 21.4k in / 386.2k cached / 3.2k out
```

After a successful `git commit` (exit 0) — regardless of eligibility, as long as figures were
computed — overwrite `last-commit-tokens` with the current session's raw `<in> <cached> <out>`.
This must happen even when the repo is ineligible and no trailer was printed: otherwise a
Teads-repo commit leaves the delta unrecorded, and the next eligible commit in the same session
would misreport ineligible-repo usage as its own. Do not write on a failed or aborted commit.

These figures are best-effort and read directly from the session transcript — no cost/dollar
figure is available natively, so none is included. A missing trailer is not a bug.

This mechanism assumes inline execution: the session id is read from this agent's own
scratchpad path. If this skill is ever run via `context: fork`, re-check whether the fork's
scratchpad carries the parent session id before trusting this section.

After committing, run `git log -<number-of-commit> --format="%h %s"` to confirm success and show the result to the user.
