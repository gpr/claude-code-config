---
name: opsx-team-apply
description: |
  Drive an in-flight OpenSpec change from /opsx:apply through review,
  fix, verify, sync, and archive using a coordinated team: a lead (the
  main session), an implementer, a tester, a reviewer, and a verifier.
  The lead never edits production code; teammates commit their own
  work. Use whenever the user says "apply <change> with a team",
  "team-apply <change>", "team-implement <change>", "implement this
  opsx change with reviewers", "ship <change> via team review",
  "team-finalize <change>", "verify-sync-archive with a team",
  "/opsx-team-apply <name>", or asks for a multi-agent / team-based
  opsx workflow on a specific in-flight change. Do not use for the
  proposal phase (see opsx-team-propose).
argument-hint: "<change-name, or empty to auto-detect>"
model: claude-opus-4-7
thinking:
  effort: medium
author: gregory.rome@teads.com
version: 1.3.0
date: 2026-05-21
---

## Purpose

Drive a full review-driven implementation cycle for an OpenSpec change
through a small team of agents. The shape mirrors how a careful pair-or-
trio of engineers ships a change: someone writes it, someone else reads
it, the author defends or accepts the feedback, and a third party
verifies the result against the spec before it's archived.

You — the main session — are the **lead**. You spawn four teammates:

- **implementer** — runs `/opsx:apply`, edits code, commits.
- **reviewer** — reviews the implementer's diff against the change spec.
- **tester** — writes all missing tests for the change.
- **verifier** — runs `/opsx:verify` and reports gaps.

Each teammate commits its own work. The lead and the reviewer never edit production code
directly; the lead only runs `/opsx:sync`, `/opsx:archive`, and the final
archive commit.

## The single rule that prevents the worst failure mode

**Before any SendMessage claiming a teammate's code is broken, reproduce the failure yourself against `HEAD`.** System-injected diagnostics (`<new-diagnostics>` reminders, cached pyright/test output) can lag the working tree by minutes. If you paste a stale diagnostic into a fix demand, you will pressure a teammate to commit fictional changes. Cost of the check: ~5 seconds. Cost of skipping it: an eroded teammate, a polluted commit history, and a user escalation that didn't need to happen. This rule is enforced in Step 1c below.

## Arguments

`$ARGUMENTS` is the change name — a directory under `openspec/changes/`
(not `archive/`).

If `$ARGUMENTS` is empty:

1. List in-flight changes: !`openspec list || echo "openspec is missing, stopping here"`.
2. If exactly one exists, use it.
3. Otherwise use `AskUserQuestion` to ask the user which one.

If the named directory does not exist, stop and use `AskUserQuestion` to ask the user — do not
spawn a team for a phantom change.

## Context

Current git status: !`git status --short`
Current branch: !`git branch --show-current`

## Preflight

Before creating the team:

- Confirm the working tree is clean enough to start (no uncommitted
  changes that aren't part of the change). If dirty, ask the user.
- Re-read the change's `proposal.md`, `design.md`, and `tasks.md` so you
  can brief each teammate accurately. Teammates start with no context
  from this session — every message you send must be self-contained.
- Make sure you are not in plan mode. ExitPlanMode if needed.
- Record the baseline SHA: `git rev-parse HEAD`. You will diff against
  this when deciding whether a teammate is "stuck" vs. "working" (see
  Step 1c and the "Wait for reply" rules).

## Team setup

Create the team and spawn teammates in a single coordinated setup pass:

1. `TeamCreate` with:
   - `team_name: opsx-apply-<change>`
   - `description: "Implement OpenSpec change <change> via lead/implementer/reviewer/verifier"`
2. Spawn four teammates via the `Agent` tool, each with `team_name` set
   to the team above and `name` set as below. Pass `model: claude-opus-4-7`
   to all teammates; the `thinking.effort` levels below are tuned per
   role. Every initial briefing MUST end with the **Communication rules
   block** in the next subsection.
   - `implementer` — `subagent_type: general-purpose`, `thinking.effort: medium`. Brief with: the change name, where its artifacts live, and the communication rules block.
   - `tester` — `subagent_type: general-purpose`, `thinking.effort: medium`. Brief with: the change name, where its artifacts live, and the communication rules block.
   - `reviewer` — `subagent_type: pr-review-toolkit:code-reviewer`, `thinking.effort: high`. Brief with: the change name, a pointer to its artifacts, instruction to wait for the lead's review request with the commit SHA, and the communication rules block.
   - `verifier` — `subagent_type: general-purpose`, `thinking.effort: medium`. Brief with: the change name, a pointer to its artifacts, instruction to wait for the lead's verification request, and the communication rules block.

Spawn the four teammates in parallel (single message, multiple Agent
tool calls). Each will immediately go idle after acknowledging — that
is normal, not an error.

### Communication rules block (append verbatim to every initial briefing)

```
Communication rules:
- All replies to the lead MUST go through the SendMessage tool. Plain-text output is invisible to the lead and will be lost.
- After each turn you will automatically go idle. That is normal and does not indicate completion or failure.
- You may receive nag-style follow-ups if your reply crosses with a lead message. Reply once with the latest authoritative state; do not re-do work that already landed.
- If a lead message claims your code is broken: before "fixing" anything, paste raw evidence (git rev-parse HEAD, the exact tool output, the relevant file lines) and ask the lead to verify against the same SHA. Refusing to commit fictional changes is correct behavior — you will not be penalized for it.
- All commits MUST follow the project's conventional-commit rules. Use the project's commit skill if one exists.
```

## Workflow

Execute the steps in order. Use `SendMessage` to dispatch work and read
teammate replies as they arrive.

### Task tracking — per deliverable, not per step

Use `TaskCreate`/`TaskUpdate` to track each **concrete deliverable**, not each workflow step. Workflow steps include loops; tasks don't loop cleanly. Create tasks like:

- `implementer Commit A (opsx:apply)`
- `tester Commit B (initial tests)`
- `implementer Commit C (test-run fixes, if any)`
- `reviewer report`
- `implementer triage`
- `implementer Commit D (synthesis fixes)`, `tester Commit E (synthesis tests)`
- `verifier pass 1 report`

Loop iterations get fresh task IDs (`verifier pass 2 report`, `implementer Commit F`, ...). Update task status the moment each deliverable lands, not at end-of-step.

### Wait-for-reply protocol

For every step that says "Wait for ... reply":

- **Idle is not silence.** Before any nag-message, run:
  ```bash
  git log --oneline <baseline>..HEAD
  git status
  ```
  If commits landed since the dispatch, or files are dirty in the teammate's lane, they are working — wait, do not nag. Replies routinely cross with `idle_notification` events.
- Only after **both** come back empty AND **>5 minutes** have elapsed, retry once with a shorter request listing required outputs.
- If still no response after 2 additional minutes, call `AskUserQuestion` with: teammate name, requested task, disk state from `git log`/`git status`, retries attempted, and two concrete options.
- If a response is incomplete, send one correction message with a checklist of missing items.
- If still incomplete after that correction, call `AskUserQuestion` with the same status details.

### Step 1a — Implement and test (parallel)

Dispatch `implementer` and `tester` in parallel (single message, two `SendMessage` calls).

Message `implementer`:

> Run `/opsx:apply <change>` to implement the change.
> When the implementation is complete, create one conventional commit. Commit only files under your production lane (typically `src/` or the equivalent); test files are owned by the tester running in parallel. Use a scope that reflects the area of the codebase you touched.
> Report back the list of files changed and a brief summary of what you did.

Message `tester`:

> Implement all new tests for the change and adapt existing tests as needed. You are running **in parallel with the implementer**, who is editing the same modules you are testing.
>
> Parallel-dispatch rules:
> 1. Write tests against the **documented signatures** in `proposal.md` / `design.md` / `specs/`, not against what currently exists in the source file (which is in flight).
> 2. If a test would require a not-yet-existing symbol, skip/defer it and note it in your report.
> 3. Run the project's type-checker (e.g. `pyright`) before each commit. Test fixtures often fight `**dict` narrowing — build a typed factory helper rather than disabling rules.
> 4. Do not touch production code; the implementer owns `src/` (or the equivalent production lane).
>
> When tests are written, create one conventional commit scoped to the area you touched. Report the commit SHA, file list, and a one-line summary.

Wait for the implementer and tester replies. Capture the commit SHAs and file list.

### Step 1b — Run tests and fix failures

Once both have replied, message `implementer`:

> Execute all tests.
> If any fail, fix them and commit the fixes (use `refactor` for unreleased code).
> Report back the new commit SHA and a one-line summary of the fixes.

### Step 1c — Verify-before-demand protocol

Before sending any SendMessage that asserts a teammate's code is broken or tests are failing, the lead MUST reproduce the failure locally against the current `HEAD`:

```bash
git rev-parse HEAD                  # record SHA you actually observed
uv run pyright <file>               # or the project's type-checker
uv run pytest <relevant tests> -q   # or the project's test runner
```

Decision rules:

- If the tool comes back **clean**, the diagnostic was stale. Say nothing — do not message the teammate.
- If the tool **reproduces** the error, include the exact command, observed HEAD SHA, and raw tool output in your SendMessage. Phrase the ask as "can you confirm or refute against `<SHA>`?" — not "fix this".
- **Never paste a `<new-diagnostics>` system-reminder verbatim into a teammate message.** Those snapshots lag the working tree by minutes.
- **Never threaten reassignment in the same message as a technical claim.** If you are wrong about the claim, the threat is catastrophic; if you are right, the evidence already carries the weight.

When a teammate pushes back with raw evidence (HEAD SHA, command output), stop and re-verify. Refusing to commit fictional changes is correct teammate behavior.

### Step 2 — Review

Message `reviewer`:

> Review the diff with the main branch for OpenSpec change `<change>`. Compare the diff
> against `openspec/changes/<change>/proposal.md`,
> `openspec/changes/<change>/design.md`, and the deltas under
> `openspec/changes/<change>/specs/`. Produce a structured review:
> numbered list of issues (severity: blocker / nit / question), each
> with a file/line reference and a concrete suggestion. If the
> implementation is clean, say so explicitly with an empty issue list.
> Include security, style, correctness, spec divergence, missing tests, and any other feedback that would be relevant to a human reviewer. Be specific and actionable — avoid vague feedback like "this part is confusing" without explaining why or how to fix it.

Wait for the reviewer's reply. Keep the full review verbatim.

### Step 3 — Implementer triages the review

Forward the full review to `implementer`:

> The reviewer produced the following critique of your commit. For each
> numbered item, respond with one of: ACCEPT (you will apply it),
> REJECT (with a rationale — code already does this, suggestion is
> wrong, out of scope), or DEFER (with a reason — separate change).
> Do not make any edits yet — just produce your triage.

Wait for the implementer's triage.

### Step 4 — Lead synthesis

Read the review + the implementer's triage side by side. Produce a final action list:

- ACCEPT items → add to the action list.
- REJECT items where the implementer's rationale is sound → drop.
- **REJECT/DEFER items where the rationale quotes the spec → MUST re-open the cited spec file and read the surrounding paragraph and any nested scenarios before accepting.** A single quoted sentence does not establish the full contract. Common failure: the implementer quotes "no caller will set this" to justify deferring per-chapter wiring, but the spec also mandates function-level scenarios (clamping, telemetry, signature shape) that are independent of any caller. Reading 30 extra lines of the spec costs 30 seconds and saves a verifier loop iteration.
- REJECT items where the rationale is weak, or DEFER items that look in-scope after the spec re-read → use `AskUserQuestion` to surface the disagreement and let the user decide. Do not silently override either side.

If the action list is empty (no edits needed), skip Step 5 and proceed
directly to Step 6 — there is nothing to verify-after-fix, but the
verifier still runs against the original commit.

### Step 5 — Apply modifications

Message `implementer` with the final action list:

> Apply the following changes from the review (synthesized by the lead).
> When done, create a second commit. Use `refactor` for bug-style fixes
> in unreleased code, or `fix` only if the original code shipped. Match
> the scope to what you actually changed. Report the new commit SHA and
> a one-line summary per item.

Wait for confirmation.

### Step 5b — Slow-gate self-check (precondition for Step 6)

Before dispatching the verifier, the lead MUST execute every `@pytest.mark.slow` (or equivalently gated) test added by the change and confirm `PASSED` (not `SKIPPED`):

```bash
uv run pytest -m slow <new-test-files> -v
```

If any gate **skips**, treat as Step 5 incomplete: the fixture is likely too small or empty. Message the tester to fix the fixture or remove the silent-skip path, then re-check. Do not advance to Step 6 with silent skips — the verifier will flag the same risk on its next pass anyway.

Also confirm `git status` is clean (all teammate work committed) and the project's type-checker + linter are clean on touched files.

### Step 6 — Verify

Message `verifier`:

> Run `/opsx:verify <change>`. Report every discrepancy: missing tasks,
> spec/impl divergence, undocumented behavior, broken validation, or
> tasks marked done that aren't really done. If verification is clean,
> say so explicitly.

Wait for the verifier's report.

### Step 7 — Decide and fix verifier issues

For each issue from Step 6, classify:

- **Must-fix** — blocks archival. Code or artifacts must be updated.
- **Defer with user approval** — genuinely out of scope; call
  `AskUserQuestion` before dropping.

For must-fix items, message `implementer` with the consolidated fix
list. The implementer applies fixes and commits (`refactor` or
`chore(openspec)` as appropriate). Re-run Step 6 (create a fresh task,
e.g. `verifier pass 2 report`).

Loop Steps 6–7 up to **three** total passes. If verification still
fails after the third pass, stop and ask the user — repeated failure
usually means the change's scope is wrong, not that one more tweak
will fix it.

### Step 8 — Sync, archive, and final commit

The lead performs these steps directly (do not delegate):

1. Run `/opsx:sync <change>`.
2. Run `/opsx:archive <change>`.
3. Stage everything that changed in steps 1 and 2 of this section.
4. Commit using the project's commit conventions.

## Teardown

Send `shutdown_request` to each teammate (`implementer`, `tester`,
`reviewer`, `verifier`) via `SendMessage`. The team file under
`~/.claude/teams/opsx-apply-<change>/` and its task list will remain
on disk for traceability.

## Guardrails

- **Never** `git push`. It belongs to the user.
- **Never** paste a `<new-diagnostics>` system-reminder verbatim into a teammate message. Reproduce against `HEAD` first (see Step 1c).
- **Never** threaten reassignment in the same message as a technical claim.
- When a teammate pushes back with raw evidence, stop and re-verify before insisting. Reward that behavior — do not steamroll it.
- If the implementer reports merge conflicts, destructive operations, or anything requiring `--force`, stop and ask the user — do not authorize teammates to bypass safety checks.
- Every agent commits its own work. Do not collapse to a single end-of-run commit — the per-step commit history is the audit trail the user explicitly asked for.
- Refer to teammates by name in `SendMessage` (`implementer`, not the agent UUID). Idle notifications between turns are normal — do not treat them as failures (see the Wait-for-reply protocol).
- Convert any relative dates you encounter ("Thursday", "next week") to absolute ISO dates before writing them into artifacts.
- If `openspec` CLI is missing at any point, stop and tell the user to install it according to project instructions.
- When committing, use project instructions and the appropriate commit skill if available.
