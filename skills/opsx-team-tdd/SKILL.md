---
name: opsx-team-tdd
description: |
  Drive an in-flight OpenSpec change through a strict test-first cycle
  with a coordinated team: a tdd-implementer and tdd-reviewer lock
  hardened tests against the spec *before any implementation exists*,
  then an implementer and reviewer make those frozen tests pass without
  weakening them. The lead (the main session) never edits production
  code or tests; teammates commit their own work. Use for
  "/opsx-team-tdd <change>", or when the user asks to "tdd / test-first
  / team-tdd <change>", "write the tests first then implement <change>",
  or for a test-driven multi-agent workflow on a specific in-flight
  change. Do not use for the proposal phase, and do not use for a normal
  (tests-and-code-together) team apply.
argument-hint: "<change-id>"
model: claude-opus-4-8
effort: medium
author: gregory.rome@teads.com
version: 1.6.0
date: 2026-06-05
hooks:
  PreToolUse:
    - matcher: Agent
      hooks:
        - type: command
          command: bash "$HOME/.claude/hooks/opsx-gate.sh"
---

## Purpose

Drive a strict test-first cycle for an OpenSpec change through a small
team of agents: tests are written from the spec while no implementation
exists, hardened, then frozen while a separate engineer writes code to
pass them — which forces the code to satisfy the spec rather than the
suite agreeing with itself.

You — the main session — are the **lead**. You spawn four teammates:

- **tdd-implementer** — writes unit + e2e tests straight from the
  change spec (mocking where relevant), commits.
- **tdd-reviewer** — reads the spec and audits the test diff,
  hunting for tests a wrong implementation would still pass.
- **implementer** — runs `/opsx:apply`, writes production code until
  the frozen suite is green, commits.
- **reviewer** — runs `/opsx:verify` and reviews the implementation
  diff against the spec.

Each teammate commits its own production code or test work — the lead
and the reviewers never write or commit those. The lead's only
mutations are: running the tests to record the baseline, and (Phase 3)
running `/opsx:sync` / `/opsx:archive` and committing **those generated
spec artifacts**. The lead never authors a code or test commit.

## Arguments

`$ARGUMENTS` is the change id — a directory under `openspec/changes/`
(not `archive/`). It is **mandatory**.

If `$ARGUMENTS` is empty, use `AskUserQuestion` to ask which in-flight
change to run — do not invent one.

## Preflight

Before creating the team:

- **Agent teams are experimental.** If
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is not set, stop and tell
  the user to enable it before retrying — `TeamCreate` will fail
  without it.
- The activation gates — the change being active and having spec deltas —
  are enforced automatically by the `opsx-gate.sh` PreToolUse hook declared
  in this skill's frontmatter, the moment you spawn the first teammate. If a
  gate fails, the spawn is blocked with an `OPSX GATE FAIL …` message; relay
  it to the user and stop.
- Run `git status --short` and `git branch --show-current` in a single
  Bash call. If `git status --short` produces **any** output (the tree
  is not clean), ask the user via `AskUserQuestion` whether to proceed —
  do not auto-stash and do not judge which changes are "related".
- Record the **starting commit hash**: `git rev-parse --short HEAD`.
  You will diff the test work against this, and use it to tell
  "teammate is working" from "teammate is stuck".
- Re-read the change's **spec deltas** — every `spec.md` under
  `openspec/changes/<change-id>/specs/` (one file per capability) — so
  you can brief each teammate accurately. **"The spec deltas" below
  always means this path**; the body uses the short form from here on.
  Teammates start with **no** context from this session, so each
  briefing must spell the full path out at least once.
- Make sure you are not in plan mode. ExitPlanMode if needed.

## Team setup

Create the team and spawn all four teammates in a single coordinated
setup pass:

1. `TeamCreate` with:
   - `team_name: opsx-tdd-<change-id>`
   - `description: "Test-first implementation of OpenSpec change <change-id> via lead/tdd-implementer/tdd-reviewer/implementer/reviewer"`
2. Spawn the four teammates via the `Agent` tool, each with `team_name`
   set to the team above and `name` set as below. Models are tuned per
   role: **Sonnet** for the execution-heavy writers, **Opus** for the
   judgment-heavy reviewers.

   The `Agent` tool exposes `model` but has **no `effort` parameter** —
   reasoning effort cannot be set at spawn. Encode the intended effort
   ("medium") as a sentence in each teammate's briefing instead (e.g.
   *"Apply medium reasoning effort — this is focused, spec-bounded work,
   not open-ended investigation."*). Every initial briefing MUST end
   with the **Communication rules block** below.

   **Shared briefing template** (all four): the change id; that its
   spec deltas live under `openspec/changes/<change-id>/specs/` (every
   `spec.md` beneath it); instruction to wait for the lead's request
   before doing anything; the medium-effort note; the communication
   rules block. Per-role deltas:

   - `tdd-implementer` — `model: claude-sonnet-4-6`.
   - `tdd-reviewer` — `model: claude-opus-4-8`. Its wait-for request
     will include the starting commit hash.
   - `implementer` — `model: claude-sonnet-4-6`.
   - `reviewer` — `model: claude-opus-4-8`.

   The writers (`tdd-implementer`, `implementer`) use `subagent_type:
   general-purpose`. The reviewers use the dedicated read-only agents —
   `tdd-reviewer` for the test audit, `tdd-impl-reviewer` for the
   implementation review (both omit `Write`/`Edit`, so they cannot mutate
   code or tests). The reviewers' "think carefully" instruction arrives
   with the actual dispatch (Steps 1.3 / 2.2) — do not preview it at spawn.

If the project's `CLAUDE.md` documents a more specialized
`subagent_type` for any of these roles, use it instead. If a named
reviewer agent is unavailable, fall back to `general-purpose` — it is
always present.

Spawn all four in parallel (single message, multiple `Agent` tool
calls). Each will acknowledge and immediately go idle — that is normal,
not an error.

### Communication rules block (append verbatim to every initial briefing)

```
Communication rules:
- All replies to the lead MUST go through the SendMessage tool. Plain-text output is invisible to the lead and will be lost.
- After each turn you will automatically go idle. That is normal and does not indicate completion or failure.
- If a lead message claims your code or tests are broken: before "fixing" anything, paste raw evidence (git rev-parse HEAD, the exact tool output, the relevant file lines) and ask the lead to verify against the same SHA.
- Committed work is append-only: never amend, rebase, squash, or otherwise rewrite a commit you have already reported to the lead. The lead records each reported SHA as a fixed anchor; rewriting it strands that anchor off-history and corrupts every later diff. To fix already-committed test or production code, add a NEW commit on top.
- All commits MUST follow the commit conventions documented in the project's `CLAUDE.md`. If `CLAUDE.md` directs you to a specific commit skill, use it; otherwise commit directly.
```

Execute the workflow steps below in order. Use `SendMessage` to
dispatch work and read teammate replies as they arrive.

## Task tracking — per deliverable, not per step

Use `TaskCreate`/`TaskUpdate` to track each **concrete deliverable**,
not each workflow step. Create tasks like:

- `tdd-implementer Commit A (initial tests)`
- `tdd-reviewer report`
- `tdd-implementer Commit B (test hardening)`
- `implementer Commit C (opsx:apply, green suite)`
- `reviewer report`
- `implementer Commit D (review fixes, still green)`
- `lead Commit E (sync)`
- `lead Commit F (archive)`

Loop iterations get fresh task IDs. Update task status the moment each
deliverable lands, not at end-of-step.

## Wait-for-reply protocol

For every step that says "Wait for ... reply":

- **Idle is not silence.** Before any nag-message, run:
  ```bash
  git log --oneline <starting-commit-hash>..HEAD
  git status
  ```
  If commits landed since the dispatch, or files are dirty in the
  teammate's lane, they are working — wait, do not nag. Replies
  routinely cross with idle notifications.
- Only after **both** come back empty, retry once with a shorter
  request listing the required outputs.
- Re-run the two disk checks after that retry. If they are **still**
  both empty and the teammate has not replied, call `AskUserQuestion`
  with: teammate name, requested task, disk state from `git log` /
  `git status`, retries attempted, and two concrete options.
- If a response is incomplete, send one correction with a checklist of
  missing items. If still incomplete, escalate via `AskUserQuestion`.
- **The reverse cross also happens:** a teammate may message "I don't
  have the findings / need input" for work you **already** dispatched —
  their inbox or the task list lagged your send. Don't re-issue the full
  task. Confirm what you sent is in their inbox, reply with a one-line
  "it's in your inbox — process that message" (optionally re-pasting
  just the action list), and let them proceed. Treat it like an
  idle-cross, not a failure.

## Verify-before-demand protocol

Before sending any `SendMessage` that asserts a teammate's code or
tests are broken, reproduce the failure locally against the current
`HEAD`:

```bash
git rev-parse HEAD                          # record the SHA you actually observed
<project-test-runner> <relevant tests> -q   # e.g. uv run pytest, npm test, cargo test
<project-type-checker> <file>               # e.g. uv run pyright, tsc --noEmit, go vet
```

Decision rules:

- If the tool comes back **clean**, the diagnostic was stale. Say
  nothing — do not message the teammate.
- If the tool **reproduces** the failure, include the exact command,
  observed HEAD SHA, and raw output in your message. Phrase the ask as
  "can you confirm or refute against `<SHA>`?" — not "fix this".
- **Never** paste a `<new-diagnostics>` system-reminder verbatim into a
  teammate message — those snapshots lag the working tree.
- **Never** threaten reassignment in the same message as a technical
  claim. When a teammate pushes back with raw evidence, stop and
  re-verify.

---

# Phase 1 — Test Phase (sequential)

The goal of this phase is a committed, hardened test suite derived
**only** from the spec, written while the implementation does not yet
exist. The tests are the contract the implementation will later be
forced to satisfy.

## Step 1.1 — Lead records the baseline

Run the project's full test suite yourself and record:

- `<test-results>` — pass/fail/error counts and the runner's summary
  line, verbatim.
- `<test-coverage>` — the coverage summary if the project produces one
  (e.g. `pytest --cov`, `go test -cover`, `nyc`/`c8`). If the project
  has no coverage tooling, note that and move on — do not install
  tooling just to produce a number.

Keep both; you will compare against them after the implementation phase
to show what the change added. Some suites legitimately fail or error
at baseline (the feature isn't built yet) — record the state as-is, do
not try to fix it.

## Step 1.2 — tdd-implementer writes the tests

Message `tdd-implementer`:

> Read every `spec.md` under `openspec/changes/<change-id>/specs/` (one
> per capability) end to end. Implement the unit tests and e2e tests
> this change requires, deriving every expected value and behavior
> **from the spec deltas**, not from any existing implementation. Use mocking where relevant (external services, I/O,
> time, randomness) so the tests are deterministic and isolated.
> Production code for this change does not exist yet — that is
> intentional. Write the tests against the **documented contract**
> (signatures, inputs, outputs, error cases, scenarios) in the spec.
> It is expected and correct that the new tests **fail or error** right
> now; do not write trivial passing tests to avoid red.
> When done, create one conventional commit containing only the test
> files. Report the commit SHA, the file list, and a one-line summary
> of which spec scenarios each test file covers.

Wait for the reply (see Wait-for-reply protocol). Capture the commit
SHA and file list.

## Step 1.3 — tdd-reviewer hardens the tests

Message `tdd-reviewer`:

> Read every `spec.md` under `openspec/changes/<change-id>/specs/`, then
> review the test diff: `git diff <starting-commit-hash>`. Your job is
> to find tests
> that a **wrong** implementation could still pass. For each test, ask
> *"would an incorrect implementation pass this?"* and flag:
> - **weak assertions** — asserts "not null"/"no error"/length only,
>   where the spec pins an exact value or shape;
> - **expected values not independently derived from the spec** — magic
>   numbers, or values that look copied from a presumed implementation
>   rather than computed from the spec;
> - **coupling to internals** — tests asserting on private helpers,
>   call order, or implementation details the spec doesn't mandate,
>   which would break on a valid refactor;
> - **missing cases** — spec scenarios, error paths, boundary/edge
>   conditions, or e2e flows with no corresponding test.
> Produce a numbered list (severity: blocker / nit / question), each
> item with a file/line reference and a concrete fix. If the suite is
> already strong, say so explicitly with an empty list. Think
> carefully — this review is the only thing standing between the team
> and a test suite that rubber-stamps a wrong implementation.

Wait for the reply. Keep the full review verbatim.

## Step 1.4 — tdd-implementer fixes review findings

Forward the full review to `tdd-implementer`:

> The reviewer audited your tests for the findings below. Apply every
> blocker and every nit you agree with; for anything you reject, reply
> with a one-line rationale grounded in the spec (do not silently
> ignore items). Keep deriving expected values from the spec deltas,
> not from a presumed implementation. When done, create one
> conventional commit with the hardened tests and report the new SHA
> plus a one-line note per finding (applied / rejected-with-reason).

Wait for confirmation. **Verify-before-demand applies** — diff the
hardened test files against disk and confirm each "applied" finding is
actually present (`git diff <prev-sha>..HEAD -- <test-paths>`, plus a
targeted `grep` for the assertion each finding demanded) before
trusting the report. If a rejected finding was a reviewer **blocker**,
read the cited spec yourself: send one correction if the rejection is
wrong, or surface a genuine judgment call via `AskUserQuestion` — do
not silently override either side.

## Step 1.5 — Record the frozen-tests checkpoint

Record the **tdd commit hash**: `git rev-parse --short HEAD`. From here
on the test files are **frozen**: the implementation phase may not
modify, delete, or weaken any test. This SHA is the boundary the
implementation diff will be measured against.

---

# Phase 2 — Implementation Phase (sequential)

Begin only after Phase 1 is fully committed and the frozen-tests
checkpoint is recorded.

## Step 2.1 — implementer makes the suite green

Message `implementer`:

> Run `/opsx:apply <change-id>` and write the production code for this
> change. **End goal: every test passes.** Hard constraints:
> - Do **not** modify, delete, skip, `xfail`, or otherwise weaken any
>   test under the frozen test files (those committed up to
>   `<tdd-commit-hash>`). If a test looks genuinely wrong against the
>   spec deltas, do **not** edit it — stop and report it to the lead
>   with the spec citation.
> - Make the code **genuinely correct for the spec**, generalizing
>   properly — do not hardcode outputs to satisfy these specific test
>   cases. A solution that pattern-matches the test inputs is a failure
>   even if the suite goes green.
> Do not stop until the full suite passes under those constraints.
> Commit your production code (one or more conventional commits, scoped
> to what you touched; test files stay untouched). Report the final
> SHA, the file list, and confirmation that the full suite passes.

Wait for the reply. Then **independently run the full suite yourself**
and confirm green (Verify-before-demand applies). Also confirm
`git diff --stat <tdd-commit-hash> -- <test-paths>` is empty — i.e. the
frozen tests were not touched. If a test file changed, that is a
constraint violation: send the implementer one message quoting the
diff and asking them to revert the test change and fix the code
instead.

**If the implementer reports a frozen test is wrong against the spec**
(the escape hatch above), read the cited spec section yourself. If the
test is genuinely wrong: message `tdd-implementer` (not the
implementer) with the specific spec-grounded fix, have them commit the
corrected test, **re-record the frozen-tests checkpoint SHA** (Step
1.5), then resume Step 2.1. If the test is actually correct, tell the
implementer to satisfy it. If it is a genuine judgment call, escalate
via `AskUserQuestion` — never let the implementer edit a frozen test
to resolve it.

## Step 2.2 — reviewer verifies and reviews

Message `reviewer`:

> Run `/opsx:verify <change-id>` and then review the full
> implementation diff: `git diff <tdd-commit-hash>` against the spec
> deltas (`openspec/changes/<change-id>/specs/`) **and** the change's
> `design.md` (which fixes structure and mechanism the spec deltas may
> leave open). Produce a structured review: numbered issues (severity:
> blocker / nit / question), each with a file/line reference and a
> concrete suggestion. **A green suite does not mean the code is
> correct** — read the requirements directly and check the code against
> them, not just the tests; a passing test can still leave a
> requirement unsatisfied. Look specifically for: spec/design
> divergence; **code hardcoded or special-cased to the test inputs**
> rather than implementing the general behavior the spec describes; a
> requirement the tests assert only shallowly (e.g. a dependency
> declared but never actually used); missing error handling; tasks
> marked done that aren't; security and style. Also confirm the frozen
> tests were not weakened. If the implementation is clean against both
> spec and design, say so explicitly with an empty list.

Wait for the reply. Keep the full review and the `/opsx:verify` result
verbatim.

## Step 2.3 — implementer fixes review findings

Forward the review to `implementer`:

> The reviewer produced the critique below. Apply every blocker and
> every nit you agree with; reject only with a spec-grounded one-line
> rationale. The same hard constraints still hold: do **not** modify,
> delete, or weaken any frozen test, and make the code genuinely
> correct for the spec rather than hardcoded to the test cases. Do not
> stop until the full suite still passes. Commit the fixes (`refactor`
> for unreleased code, `fix` only if it shipped) and report the new
> SHA plus a one-line note per finding.

Wait for confirmation. Re-run the suite yourself and re-confirm the
frozen tests are untouched. If the verify result had must-fix items,
loop Step 2.2–2.3 (fresh task IDs, e.g. `reviewer pass 2 report`) up to
**three** total passes. If it still fails after the third, stop and ask
the user — repeated failure usually means the spec or the test contract
is wrong, not that one more tweak will fix it.

---

# Phase 3 — Final Phase (sequential, lead performs directly)

Don't apply the Wait-for-reply protocol here — you are the only actor.

Begin only after the suite is green, the review is resolved, and the
frozen tests are confirmed untouched. The lead performs these directly
— do not delegate.

Phase 3 mutates the repo irreversibly (sync writes main specs, archive
moves the change) and commits to the working branch. **Before starting,
re-confirm the true HEAD un-proxied** (see Verify-before-demand) —
syncing or archiving on top of a stale-cached HEAD is a real corruption
risk.

## Step 3.1 — Sync

Run `/opsx:sync <change-id>`. Then create a commit for whatever it changed by
following project conventions: if `CLAUDE.md` directs to a
specific commit skill, use it; otherwise commit directly.


## Step 3.2 — Archive

Launch an Heroku agent to run `/opsx:archive <change-id>`. Then create a commit for
whatever it changed by following project conventions: if `CLAUDE.md` directs to a
specific commit skill, use it; otherwise commit directly.

## Step 3.3 — Report

Run `git log --oneline <starting-commit-hash>..HEAD` and surface the
full commit trail (tests → hardening → implementation → fixes → sync →
archive) so the user sees the test-first audit history. Re-run the
suite one last time and report the final `<test-results>` /
`<test-coverage>` next to the baseline you recorded in Step 1.1, so the
delta from the change is visible.

Execute the following script to get this session usage and add it to the report as a table.

```bash
bash "$HOME/.claude/scripts/team-usage.sh"
```

The report must be displayed to the user and saved as an artifact in the archived change directory (`openspec/changes/archive/<YYYY-MM-DD>-<change-id>/report.md`).

## Step 3.4 — Teardown

Send a shutdown request to each teammate (`tdd-implementer`,
`tdd-reviewer`, `implementer`, `reviewer`) via `SendMessage` — a
natural-language request, not a literal payload. Once all four have
shut down, clean up the team.

## Guardrails

- Refer to teammates by name in SendMessage, not the agent UUID.
- Convert any relative dates you encounter to absolute ISO dates before
  writing them into artifacts.
- When in doubt, ask the user rather than making a unilateral decision.
