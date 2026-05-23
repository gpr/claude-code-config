---
name: opsx-finalize
description: |
  Finalize an OpenSpec change end-to-end: verify the implementation, fix
  any issues found, sync delta specs to main specs, archive the change,
  and commit everything. Use when: user says "finalize this change",
  "wrap up this opsx change", "verify-sync-archive", "/opsx-finalize",
  or asks to complete the closing OpenSpec workflow on a change. Always
  use this skill whenever the user wants to take an in-progress OpenSpec
  change all the way through to an archived + committed state in one
  shot, even if they only mention one of the steps.
argument-hint: "[change name, or empty to auto-detect]"
model: claude-opus-4-7
thinking:
  effort: high
author: gregory.rome
version: 1.0.0
date: 2026-05-12
---

## Purpose

Run the closing sequence of an OpenSpec change as a single guided workflow:

1. `/opsx:verify` — confirm implementation matches the change artifacts
2. Fix any issues surfaced by verification
3. `/opsx:sync` — promote delta specs into main specs
4. `/opsx:archive` — move the change into `openspec/changes/archive/`
5. Commit everything with a conventional commit

This runs on Opus with high thinking effort because the verification step
needs careful reasoning across spec, design, tasks, and implementation —
silent drift here defeats the point of spec-driven development.

## Arguments

`$ARGUMENTS` should be the change name (matching a directory under
`openspec/changes/`). If empty, list `openspec/changes/` (excluding
`archive/`); if exactly one in-flight change exists, use it; otherwise
ask the user which one.

## Context

Current git status: !`git status`
In-flight changes: !`ls openspec/changes/ 2>/dev/null | grep -v '^archive$' || echo "(none)"`
Current branch: !`git branch --show-current`

## Workflow

Execute the steps in order. Do not skip ahead — each step's output
informs the next.

### Step 1 — Verify

Invoke the `opsx:verify` skill with the change name. Capture every
discrepancy it reports: missing tasks, spec/impl divergence, undocumented
behavior, broken validation, etc.

If verification passes cleanly with zero issues, skip to Step 3.

### Step 2 — Fix issues

For each issue from Step 1:

- If the fix is in implementation code, edit the code.
- If the fix is in the change artifacts (`proposal.md`, `design.md`,
  `specs/`, `tasks.md`), edit those.
- If a task in `tasks.md` is done but unchecked, check it.
- If something is genuinely out of scope for this change, surface it to
  the user and ask before deferring — do not silently drop it.

After fixing, re-run `opsx:verify`. Loop until verification is clean.
If you loop more than 3 times without convergence, stop and ask the
user — repeated failure usually means the change's scope is wrong, not
that one more tweak will fix it.

### Step 3 — Sync

Invoke the `opsx:sync` skill to promote delta specs from
`openspec/changes/<name>/specs/` into `openspec/specs/`. Confirm the
main specs reflect the new behavior before continuing.

### Step 4 — Archive

Invoke the `opsx:archive` skill to move the change directory into
`openspec/changes/archive/YYYY-MM-DD-<name>/`.

### Step 5 — Commit

Stage everything that changed across Steps 2–4 and create a single
conventional commit. Per the project's `CLAUDE.md`:

- Use `chore(openspec): archive <change-name>` as the default subject if
  the change was archive-only (no impl edits in Step 2).
- If Step 2 modified production source under `src/`, prefer the type
  that matches the underlying work (`feat` / `fix` / `refactor` /
  `perf`) with an appropriate scope, and mention the archived change in
  the body.
- Use `refactor` (not `fix`) for bugs in unreleased code.
- Subject ≤72 chars, imperative mood, no trailing period.
- Append `Co-Authored-By: Claude <claude-opus-4-7> <noreply@anthropic.com>`.

After committing, run `git log -1 --stat` and show the result.

## Notes

- Do **not** run `cog bump` — versioning is a separate decision.
- Do **not** push — leave that to the user.
- If `openspec` CLI is missing, stop and tell the user to run
  `mise install`.
