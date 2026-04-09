---
name: session-reviewer
description: |
  Extract reusable skills, subagents, and hooks from session history. Use when:
  (1) user asks to review a session or extract learnings, (2) "what did we accomplish?",
  "review what we learned", "session retrospective", (3) user wants to identify patterns
  or improve project components after a work session, (4) "extract a hook/skill/agent
  from this session". Covers gap analysis against existing components and confidence-based
  extraction recommendations.
author: Claude Code
version: 2.0.0
date: 2026-03-30
agent: Plan
allowed-tools:
  - Read
  - Grep
  - Glob
---

# Session Review & Component Extraction

Review this session's history to identify reusable patterns and knowledge that should be captured as project components (skills, subagents, hooks).

## Problem

Valuable knowledge discovered during work sessions is lost when it isn't captured as reusable components. Manual review is tedious and inconsistent — patterns get missed, duplicates get created, and extraction quality varies.

## Context / Trigger Conditions

- User asks to review a session or extract learnings
- User says "what did we learn?" or "session retrospective"
- User wants to identify reusable patterns after completing work
- End of a session involving non-obvious debugging, workarounds, or discovery

## Solution

Use ONLY the session's history. Do NOT explore the codebase beyond what's needed to inventory existing components.

### Phase 1: Discovery

Scan session history for extraction signals:

**Skill signals**: Non-obvious solutions, project-specific knowledge uncovered, error root causes that differed from apparent meaning, tool/API usage beyond standard docs.

**Subagent signals**: Work requiring deep focus that polluted context, tasks that should have run in parallel, clear specialist roles emerging, multi-step workflows with decision points.

**Hook signals**: Same action manually repeated after specific events, quality checks done (or forgotten) after modifications, "I always forget to X after Y" moments.

### Phase 2: Inventory Existing Components

Before proposing anything, catalog what already exists:

- Skills: `Glob` for `.claude/skills/**/SKILL.md`
- Subagents: `Glob` for `.claude/agents/*.md`
- Hooks: `Read` on `.claude/settings.json` or `.claude/hooks.json`
- CLAUDE.md: `Read` on `CLAUDE.md`

Note each component's name, description, and purpose.

### Phase 3: Gap Analysis

For each discovery, classify as:

| Classification | Action |
|----------------|--------|
| Already covered | No action |
| Partial coverage | UPDATE existing component |
| Not covered | CREATE new component |
| Obsolete | DEPRECATE existing component |

Apply quality criteria before recommending. See supporting resources:
- `resources/hooks.md` for hook quality gates
- `resources/skills.md` for skill quality gates
- `resources/subagents.md` for subagent quality gates

### Phase 4: Propose

Output an improvement plan with:

1. **Extraction candidates** ranked by confidence (HIGH/MEDIUM/LOW)
2. **Draft implementations** for HIGH confidence items only
3. **Validation questions** for MEDIUM confidence items
4. **Deferred items** for LOW confidence (note why)

## Verification

After running the review:
- Each proposed component has a confidence score with justification
- HIGH confidence items include ready-to-use draft implementations
- No duplicates of existing components are proposed
- All proposals cite specific session moments as evidence

## Example

See `examples/extraction-examples.md` for concrete examples of good vs bad extraction decisions across skills, subagents, and hooks.

## Notes

- Only HIGH confidence items get draft implementations
- MEDIUM confidence items need user validation first
- When uncertain: prefer Skill over Subagent (simpler), prefer CLAUDE.md over Hook (less magic)
- Flag anything that duplicates Claude's built-in capabilities
- This skill operates on session history only — it does not explore or analyze the broader codebase
