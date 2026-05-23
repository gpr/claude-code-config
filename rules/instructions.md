---
paths:
  - "**/.claude/skills/**/*.md"
  - "**/.claude/agents/*.md"
  - "**/CLAUDE.md"
---

# Authoring guidelines for skills, agents, and CLAUDE.md

## Token discipline

- Delete any sentence that restates what the surrounding structure already implies.
- Prefer tables and bullet lists over prose for parallel information.
- If a rule needs justification, add a single "Why:" line — not a paragraph.

## Specificity

- State concrete, verifiable instructions. "Run `npm test` before committing" — not "test your changes."
- Name exact files, tools, flags, or patterns. Avoid "appropriate", "relevant", "as needed."
- When describing skill triggers, list literal phrases users say.

## Tone calibration

Recent Claude models are highly instruction-responsive — strong language overtriggers.

- Use normal imperative sentences. Reserve `MUST` / `NEVER` for irreversible or security-critical rules.
- Drop anti-laziness nudges ("be thorough", "don't skip steps") — they cause overengineering.
- Remove "if in doubt, use [tool]" — overtriggers on current models.

## Structure

- Use markdown headers to separate sections.
- Use XML tags (`<example>`, `<context>`) when mixing instructions, input data, and examples.
- Keep examples close to the rule they illustrate.

## Anti-patterns

| Avoid | Replace with |
|-------|-------------|
| "Apply best practices" | State the specific practices |
| "CRITICAL: YOU MUST always..." | Direct imperative: "Always..." |
| Explaining what Claude is | Instructions for what Claude does |
| Rules for hypothetical edge cases | Rules for observed problems only |
