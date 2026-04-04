# Skills System Documentation

This directory contains custom Claude Code skills — reusable prompt-driven
commands invoked via `/skill-name` in Claude Code sessions.

## Structure

```
skills/
├── CLAUDE.md                  # This file
├── .claude/settings.local.json # Local permissions (e.g. allowed Bash patterns)
├── commit/SKILL.md            # /commit — conventional commit workflow (fork, haiku)
└── session-reviewer/          # /session-reviewer — extract reusable components
    ├── SKILL.md               #   Main skill (delegated to Plan agent)
    ├── examples/              #   Extraction examples
    └── resources/             #   Quality gates for hooks, skills, subagents
```

## Skill Conventions

Each skill lives in its own directory with a `SKILL.md` file. Key frontmatter fields:

| Field | Required | Notes |
|-------|----------|-------|
| `name` | Yes | Kebab-case identifier |
| `description` | Yes | Multi-line; first line is the trigger description shown to users |
| `argument-hint` | No | Hint shown in autocomplete (e.g. `"[files...]"`) |
| `context` | No | `fork` = independent context; omit for inline execution |
| `agent` | No | Delegate to a subagent type (e.g. `Plan`, `Explore`) |
| `model` | No | Override model (e.g. `haiku` for fast/cheap tasks) |
| `allowed-tools` | No | Restrict tool access when using `agent` |
| `author` | Yes | Attribution |
| `version` | Yes | SemVer |
| `date` | Yes | ISO date of last update |

## Skill Body Patterns

- `$ARGUMENTS` — replaced with user-supplied arguments at invocation
- `` !`command` `` — shell commands executed before the skill prompt runs (gather context)
- Resource files in subdirectories are referenced as relative paths from the skill body

## Reference

For the full specification, see:
- https://code.claude.com/docs/en/skills.md
- https://code.claude.com/docs/llms.txt (complete docs index)
