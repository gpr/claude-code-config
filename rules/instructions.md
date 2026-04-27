---
description: Prompt authoring standards for skills, agents, and CLAUDE.md — optimized for Claude 4.6 models
paths:
  - ".claude/skills/**/*.md"
  - ".claude/agents/*.md"
  - "**/CLAUDE.md"
---

# Authoring guidelines for Claude 4.6

These files are loaded into the context window. Every token competes with conversation, tool results, and thinking. Write for an agent, not a human reader.

## Token discipline

- One idea per sentence. Cut filler words, hedging, and transitions.
- Delete any sentence that restates what the surrounding structure already implies.
- Prefer tables and bullet lists over prose when conveying parallel information.
- If a rule needs justification, add a single "Why:" line — not a paragraph.

## Specificity

- State concrete, verifiable instructions. "Run `npm test` before committing" — not "test your changes."
- Name exact files, tools, flags, or patterns. Avoid "appropriate", "relevant", "as needed."
- When describing when a skill triggers, list literal phrases users say.

## Tone calibration (Claude 4.6)

Claude 4.6 is significantly more responsive to instructions than prior models. Aggressive emphasis causes overtriggering.

- Use normal imperative sentences. Reserve `MUST` / `NEVER` for irreversible or security-critical rules only.
- Drop anti-laziness nudges ("be thorough", "don't skip steps"). The model already follows through; these cause overengineering.
- Remove "if in doubt, use [tool]" — it worked for older models but overtriggers on 4.6.

## Structure

- Use markdown headers to separate sections. Claude parses structure the same way readers scan it.
- Use XML tags (`<example>`, `<context>`) when mixing instructions, input data, and examples in the same prompt.
- Keep examples close to the rule they illustrate. Wrap in `<example>` tags to distinguish from instructions.

## Anti-patterns

| Avoid | Replace with |
|-------|-------------|
| "Apply best practices" | State the specific practices |
| "Use clear and specific language" | (Meta — just write clearly) |
| "CRITICAL: YOU MUST always..." | Direct imperative: "Always..." |
| Explaining what Claude is | Instructions for what Claude does |
| Rules for hypothetical edge cases | Rules for observed problems only |
