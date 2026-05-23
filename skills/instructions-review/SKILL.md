---
name: instructions-review
description: |
  Review an instruction file (CLAUDE.md, AGENTS.md, SKILL.md, rules/*.md)
  against format spec, behavioral impact, and token cost.
  Use when: user says "review this CLAUDE.md", "audit this skill",
  "/instructions-review <path>", or asks to evaluate an instruction file
  for redundancy, conformance, or trigger effectiveness.
argument-hint: "<absolute path to instruction file>"
author: Grégory Romé
version: 1.0.0
date: 2026-05-07
---

## Target

File under review: $ARGUMENTS

## Axes

1. **Format** — conformance to https://code.claude.com/docs/en/skills.md. Check only documented frontmatter fields, path globs (verify they match intended files including `~/.claude/...`), file size, and structural conventions.

2. **Impact** — classify each section or bullet:
   - *Load-bearing*: changes Claude's behavior beyond what always-loaded context already does.
   - *Redundant*: duplicates always-loaded context.
   - *Inert*: meta-commentary, structural restatement, or descriptions of what Claude is.

3. **Cost** — tokens loaded per trigger, trigger frequency (command-invoked vs. path-scoped vs. always-on), and redundancy against:
   - Claude Code built-in system prompt
   - `~/.claude/CLAUDE.md`
   - `~/.claude/skills/CLAUDE.md` (when target is a skill)
   - Sibling rule files loading alongside the target

## Method

- Fetch https://code.claude.com/docs/en/skills.md with WebFetch before reviewing.
- Read the target plus every always-loaded source it could conflict with. Name each source checked.
- For path-scoped rules, verify the glob matches the files it claims to target.

## Output

1. **Findings table** — `Location | Category | Problem | Evidence`, one row per issue.
2. **Conflicts and redundancies** — explicit citations: "Line N of target duplicates line M of <source>."
3. **Rewrite** — single proposed full-file replacement. No diff, no alternatives.
4. **Line-count delta** and one-sentence rationale.

## Constraints

- If two instructions conflict, name the winner and why. Do not list both.
- No closing summary.
