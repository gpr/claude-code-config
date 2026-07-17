---
name: plan-and-implement
description: |
  Plan a change with an Opus agent, get user confirmation, then launch a
  Sonnet agent to implement it and a review agent running /code-review to
  check the result. Use when the user says "plan and implement", "plan
  this", "plan then build", "/plan-and-implement", or asks to plan a
  change before implementing. Also use when the user wants a phased
  workflow: research first, then execute with a fast agent, then review.
  Do NOT use for changes the user wants applied immediately without a
  plan review step.
argument-hint: "<what-to-change>"
disable-model-invocation: true
user-invocable: true
author: gregory.rome@teads.com
version: 2.0.0
date: 2026-07-17
---

## Context

<request>$ARGUMENTS</request>
<repo-status>!`git status --porcelain`</repo-status>
<current-branch>!`git branch --show-current`</current-branch>
<baseline-sha>!`git rev-parse HEAD`</baseline-sha>

## Preflight

1. If <request> is empty, ask the user what they want to change using `AskUserQuestion`.
2. If <repo-status> shows uncommitted changes, ask the user whether to proceed or stash first.

## Phase 1 — Plan (Opus agent)

Delegate research and planning to a dedicated planning agent. The lead
(this session) does not research the codebase itself — it briefs the
plan agent, relays its output, and drives user confirmation.

Spawn one teammate via the `Agent` tool:

- `name`: `planner`
- `model`: `claude-opus-4-8`
- `mode`: `plan`
- `subagent_type`: `Plan`

Brief the planner:

> Produce a concrete implementation plan for this change: <request>.
> Baseline SHA: <baseline-sha>. Branch: <branch>.
> Research the codebase first — read the relevant sections of every file
> that must change (not just paths), note existing test files for the
> affected code, and check related configuration, types, or interfaces
> that must stay in sync.
>
> Return the plan in exactly this structure:
>
> ```
> ## Implementation Plan: <short title>
>
> ### Complexity: <low | medium | high>
>
> ### Files to modify
> - `path/to/file.ext` — what changes and why
>
> ### Steps
> 1. <concrete step with file paths and line-level detail>
> 2. ...
>
> ### Tests
> - Which test files to update or create
> - Key scenarios to cover
>
> ### Risks / open questions
> - Anything ambiguous or potentially breaking
> ```
>
> Each step must name exact functions, types, or blocks to modify — not
> vague directives like "update the handler." The plan must be concrete
> enough for a separate agent with no conversation context to execute.
> Rate `Complexity` by scope and risk: low = single file / localized
> change, medium = a few files or moderate cross-cutting, high = many
> files, interface/schema changes, or significant risk. If you find
> ambiguity that would change the approach, flag it under open questions
> rather than guessing.

Wait for the planner's reply. When it returns, present the plan verbatim
to the user and record the `Complexity` rating — it drives the review
effort in Phase 4.

### Get confirmation

Use `AskUserQuestion` to confirm:

> Here's the implementation plan. Ready to proceed?

Options:
- **Proceed** — launch the implementer
- **Edit** — let the user give feedback to refine the plan

If the user chooses Edit, forward their feedback to the planner via
`SendMessage`, wait for the revised plan, present it again, and ask
again. Loop until they confirm.

## Phase 2 — Implement (Sonnet agent)

Once the user confirms, spawn a single Sonnet agent to execute the plan.

Create one teammate via the `Agent` tool:

- `name`: `implementer`
- `model`: `claude-sonnet-5`
- `mode`: `auto`
- `subagent_type`: `general-purpose`

Brief the implementer with the full plan, including:
- Every file path and what to change
- The baseline SHA for reference
- The branch name
- Any project conventions from CLAUDE.md (commit style, test commands)

End the briefing with:

```
Rules:
- Follow the plan exactly. If you discover the plan is wrong or incomplete, stop and report back instead of improvising.
- Commit each logical unit of work separately using conventional commits.
- Run the project's test suite after implementation. Fix any failures before reporting done.
- Report back: list of commits (SHA + message), files changed, test results.
```

Wait for the implementer's reply using the same wait protocol as your
other team skills: check `git log <baseline>..HEAD` and `git status`
before assuming silence. Only nag after 5+ minutes of no commits and no
reply.

## Phase 3 — Test + Diff

Once the implementer reports done:

1. Run the project's test suite yourself (look for test commands in
   CLAUDE.md, package.json, Makefile, etc.). If no test infrastructure
   exists, skip and note it.
2. Show the user the diff: `git diff <baseline-sha>..HEAD --stat` and
   a brief summary of what changed.

If tests fail, message the implementer with the failures and ask for
fixes. Loop up to 2 times. If still failing, stop and report to user.

## Phase 4 — Review (general-purpose agent running /code-review)

Map the planner's `Complexity` rating to a `/code-review` effort level:

| Complexity | `/code-review` effort |
|------------|-----------------------|
| low        | `low`                 |
| medium     | `medium`              |
| high       | `high`                |

Spawn a reviewer agent:

- `name`: `reviewer`
- `model`: `claude-sonnet-5`
- `mode`: `auto`
- `subagent_type`: `general-purpose`

Brief the reviewer:

> Invoke the `/code-review` skill with effort `<effort>` on the diff
> between <baseline-sha> and HEAD on branch <branch>. The goal of the
> change: <one-line summary from the plan>.
> Report its findings back verbatim: the full list of issues with
> severity, file/line references, and fix suggestions. If the review
> found nothing, say so with an empty issue list.

Wait for the review.

### Handle review findings

- If no blockers: present the review summary to the user. Done.
- If blockers exist: present them to the user with `AskUserQuestion`:
  - **Fix blockers** — forward to implementer for fixes, then re-review
  - **Accept as-is** — user overrides, done
  - **Abort** — user wants to undo; suggest `git reset --soft <baseline-sha>`

If fixing, message the implementer with the blocker list, wait for
fixes, then re-run the reviewer. Max 2 fix cycles before escalating to
the user.

## Phase 5 — Commit

Once the review is resolved (clean, accepted, or blockers fixed), invoke
the `/commit` skill to create the final commit. If `/commit` is not
available, commit directly using conventional commit conventions from
the project's CLAUDE.md.

## Teardown

Report to the user:
- Commits created (from `git log --oneline <baseline-sha>..HEAD`)
- Test results (pass/fail/skip counts)
- Review verdict (clean / issues accepted / blockers fixed)

## Guardrails

- Never `git push`. That belongs to the user.
- Never authorize `--force`, destructive resets, or hook bypasses.
- The lead (this session) never researches or edits production code — the planner researches, the implementer edits. The lead orchestrates and drives user confirmation.
- If the implementer reports merge conflicts or needs destructive operations, stop and ask the user.
- All communication with teammates goes through `SendMessage`.
- All questions to the user go through `AskUserQuestion`.
