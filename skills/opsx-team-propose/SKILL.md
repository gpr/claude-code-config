---
name: opsx-team-propose
description: |
  Drive the front end of an OpenSpec change end-to-end with a lead +
  two-reviewer team. Lead runs `/opsx:explore` then `/opsx:ff`,
  commits the draft, dispatches parallel scope and technical reviews,
  arbitrates disagreements, edits the proposal, and commits.
when_to_use: |
  Use whenever the user says "propose a change with a team",
  "team-propose <idea>", "explore and propose with reviewers",
  "/opsx-team-propose <idea>", "team-explore this idea", or asks for
  a multi-agent / team-based OpenSpec proposal workflow. Output is a
  reviewed change directory under `openspec/changes/<slug>/` ready
  for `/opsx-team-apply`.
argument-hint: "<short idea or change slug, or empty to ask>"
model: claude-opus-4-7
effort: high
disable-model-invocation: true
allowed-tools:
  - Agent
  - SendMessage
  - TeamCreate
  - TaskCreate
  - TaskUpdate
  - AskUserQuestion
  - Edit
  - Write
  - Read
  - Bash(git status:*)
  - Bash(git log:*)
  - Bash(git branch:*)
  - Bash(openspec *)
author: gregory.rome@teads.com
version: 1.1.0
date: 2026-05-23
---

## Purpose

Turn an idea into a well-formed, stress-tested OpenSpec proposal before
any code is written. The shape mirrors how a careful design review
happens: the author drafts, two reviewers with different lenses read it
independently, they cross-comment, and the author arbitrates — pulling
the user in only when the reviewers genuinely disagree.

You — the main session — are the **lead**. You spawn two teammates:

- **reviewer-scope** — reviews the proposal for scope boundaries,
  clarity of intent, acceptance criteria, and whether requirements are
  unambiguous and aligned with the stated idea.
- **reviewer-tech** — reviews the proposal for technical feasibility,
  edge cases, test strategy, dependencies, risk, and alternatives.

Reviewers never edit anything; they only return text reviews. The lead
edits proposal artifacts directly because they are docs, not production
code. The lead commits both the initial proposal and the refined
version.

## Arguments

`$ARGUMENTS` is a free-text idea description **or** a target change
slug under `openspec/changes/`.

If `$ARGUMENTS` is empty, use `AskUserQuestion` to elicit the idea —
do not invent one.

## Context

Current git status: !`git status --short`
Current branch: !`git branch --show-current`
In-flight changes: !`openspec list || echo "openspec is missing, stopping here"`

## Preflight

Before creating the team:

- **Agent teams are experimental.** If
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is not set in settings,
  stop and tell the user to enable it before retrying. Without it,
  `TeamCreate` will fail.
- If `git status --short` shows any file outside `openspec/changes/`,
  the working tree has unrelated uncommitted changes — stop and ask
  the user via `AskUserQuestion`. Do not auto-stash.
- If `openspec` CLI is missing, stop and tell the user to run
  `mise install`.
- Resolve a working **slug**: derive a kebab-case slug from the idea,
  or use the slug the user provided. Confirm with the user via
  `AskUserQuestion` if you are not confident — the slug is durable and
  will name the change directory.

## Team setup

Create the team and spawn both reviewers in a single coordinated pass:

1. `TeamCreate` with:
   - `team_name: opsx-propose-<slug>`
   - `description: "Propose OpenSpec change <slug> via lead + two-reviewer discussion"`
2. Spawn two reviewers via the `Agent` tool in **parallel** (single
   message, two tool calls), each with `team_name` set to the team
   above, `name` set as below, `subagent_type: general-purpose`, and
   `model: sonnet`. The neutral `general-purpose` system prompt is
   intentional — the lens is set entirely by the spawn briefing so
   the agent's default prompt doesn't bias the review (e.g. a
   code-reviewer agent would push the review toward diff/style
   framing, which is the wrong frame for design-doc artifacts).
   - `reviewer-scope` briefing: the idea, the target slug, artifacts
     will appear under `openspec/changes/<slug>/`, wait for the
     lead's review request which will include a commit SHA. Lens:
     **scope boundaries, clarity of intent, acceptance criteria
     completeness, requirement unambiguity, alignment with stated
     intent**. *"Apply medium reasoning effort — this is structured
     doc review, not open-ended investigation. Reviewers never edit
     anything; return text only."*
   - `reviewer-tech` briefing: same structure. Lens: **technical
     feasibility, edge cases, test strategy, dependencies, risk,
     alternatives considered**. Same effort + no-edit guidance.

Each reviewer will acknowledge and go idle. Idle notifications between
turns are normal — do not treat them as failures.

## Workflow

Use `SendMessage` to dispatch work and read replies as they arrive.
Use `TaskCreate`/`TaskUpdate` to track each step on the shared task
list so progress is visible.

For every step that says "Wait for ... reply":

Teammate replies arrive automatically as idle notifications — you do
not need to poll. The timeouts below are a **safety net** for stuck
teammates, not an active polling cadence.

- If no notification has arrived after ~3 minutes wall-clock, retry
  once with a shorter request that lists required outputs.
- If still nothing after ~2 additional minutes, call
  `AskUserQuestion` with: teammate name, requested task, retries
  attempted, current blocker, and two concrete options.
- If a response is incomplete, send one correction message with a
  checklist of missing items.
- If still incomplete after that correction, call `AskUserQuestion`
  with the same status details.

### Step 1 — Explore

Lead runs `/opsx:explore $ARGUMENTS` directly in-session. Capture the
resulting notes. If exploration surfaces blocking unknowns — competing
interpretations of the idea, missing context, hard external
dependencies — use `AskUserQuestion` before proceeding. Do not move to
Step 2 with unresolved blockers; the proposal will only inherit them.

### Step 2 — Propose

When the idea is clear, lead runs `/opsx:ff <slug>` directly. This
materializes `openspec/changes/<slug>/` with `proposal.md`,
`design.md`, `tasks.md`, and the deltas under `specs/`.

Then run `/commit` with a conventional commit. Default subject:
`chore(openspec): propose <slug>`. If `/opsx:ff` produced something
beyond pure OpenSpec docs (rare), match the scope to what actually
changed. Capture the commit SHA.

### Step 3 — Parallel review

In a single turn, send the **same** request (with the commit SHA) to
both reviewers via two `SendMessage` calls:

> Review commit `<SHA>` for proposed OpenSpec change `<slug>`. Read
> `openspec/changes/<slug>/proposal.md`,
> `openspec/changes/<slug>/design.md`,
> `openspec/changes/<slug>/tasks.md`, and the deltas under
> `openspec/changes/<slug>/specs/`. Apply **your** lens (you were
> briefed with it on spawn) and ignore that another reviewer exists.
> Produce a structured review: numbered list of issues — severity is
> blocker / nit / question — each with a file/section pointer and a
> concrete suggestion. If the proposal is clean from your lens, say so
> explicitly with an empty issue list.

Wait for both replies. Keep each review verbatim.

### Step 4 — Cross-review discussion

In a single turn, forward each reviewer's review verbatim to the
**other** reviewer:

> Here is the other reviewer's critique of the same proposal. For each
> of their numbered items, respond with one of:
> - **AGREE** — you concur, optionally add a one-line reinforcement.
> - **DISAGREE** — you do not concur. Give a rationale: the proposal
>   already addresses it, the suggestion is wrong, or it is out of
>   scope.
> - **ADD-ON** — you partly agree and have something to add — extend
>   the item, do not just restate it.
> Do not edit the proposal. Keep responses tight.

Wait for both replies. This is the "discussion" — it surfaces
convergence and divergence without round-tripping more than once.

### Step 5 — Lead synthesis

Build a single action list from the four artifacts (two reviews, two
cross-responses):

- Items **both** reviewers AGREE on → accept.
- Items one reviewer raised where the other ADD-ONs or stays silent →
  accept by default.
- Items where the reviewers explicitly DISAGREE, **or** where a single
  reviewer's blocker has non-obvious tradeoffs that would materially
  change scope → call `AskUserQuestion` with both positions framed
  neutrally and two concrete options. **Strong-doubt threshold**: any
  DISAGREE on a blocker, or any item that would change scope, the
  contract, or the migration story.
- Items judged out of scope for the proposal phase → defer with a
  one-line note that will go into the refine commit's body.

If the action list is empty, skip Step 6 and report success at Step 7.

### Step 6 — Apply

Lead edits the proposal artifacts under `openspec/changes/<slug>/`
directly using `Edit`/`Write`. These are docs, not production code —
no implementer teammate is needed.

After edits, validate the proposal is still well-formed:

```
openspec validate <slug>
```

If validation fails, fix and re-run before committing.

Then run `/commit`. Default subject: `chore(openspec): refine <slug> proposal`.
Body: bullet list of applied items, plus any deferred items with the
one-line reason. Subject ≤72 chars, imperative mood, no trailing
period.

### Step 7 — Handoff

Run `git log --oneline -10` and surface the recent commits so the user
sees the propose + refine commits. Tell the user the proposal is ready
for `/opsx-team-apply <slug>`.

## Teardown

1. Ask each reviewer to shut down via `SendMessage` — a
   natural-language request (e.g. *"Please shut down, your review
   work is complete."*), not a literal `shutdown_request` payload.
   Each reviewer may accept or reject; if rejected, surface the
   reason to the user and stop.
2. Once both reviewers have shut down, ask the user via
   `AskUserQuestion` whether to clean up the team. On confirmation,
   run the team cleanup (per the
   [agent-teams docs](https://code.claude.com/docs/en/agent-teams.md#clean-up-the-team)).
   This removes `~/.claude/teams/opsx-propose-<slug>/`.
3. If the user prefers to keep the team for traceability, skip
   cleanup — the team config and task list remain on disk.

## Guardrails

- **Never** `git push`. **Never** `cog bump`. Both belong to the user.
- **Never** edit production code in this skill — only proposal
  artifacts under `openspec/changes/<slug>/`. If exploration reveals
  that the idea requires code edits before a proposal can be drafted,
  stop and ask the user — that signals scope confusion, not a missing
  step.
- Reviewers never edit anything. If a reviewer reply contains a patch,
  treat it as a suggestion and decide in Step 5.
- Refer to teammates by name in `SendMessage` (`reviewer-scope`,
  `reviewer-tech`), not the agent UUID. Idle notifications between
  turns are normal.
- Convert any relative dates ("Thursday", "next week") to absolute ISO
  dates before writing them into artifacts.
- If `/opsx:explore` or `/opsx:ff` fail, stop and surface the error —
  do not retry blindly; the failure usually indicates the idea or slug
  needs reshaping.
- Limit the discussion to one round (Step 4). If the reviewers
  identify genuinely new issues during cross-response that were not in
  their original reviews, include them in Step 5 but do not initiate
  a second round — escalate ambiguity to the user instead.