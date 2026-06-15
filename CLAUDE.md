# Global Development Standards

## Tools

- `plugin:repomix-mcp:repomix` — broad structure, cross-cutting concerns, multi-module relationships. Built-in Read/Grep/Glob for targeted searches (specific function, single file, known path).
- `plugin:context7:context7` — library docs when an API is unfamiliar, recently changed, or version-sensitive; skip stable stdlib. Verify signatures here (or via source/LSP) before calling an unfamiliar API.
- LSP over Grep for symbols, type errors, and references. Grep only for string literals, comments, log messages.

### CLI tools

When running Bash commands, prefer these over defaults:

| tool | replaces | notes |
|------|----------|-------|
| `rg` | grep | fast regex |
| `fd` | find | fast file finder |
| `ast-grep` | - | AST-aware search — prefer over rg for code patterns (signatures, imports, class definitions). rg for string literals, comments, log messages. |
| `trash` | rm | recoverable delete (destructive `rm` flags are blocked by hooks) |
| `jq` | python/sed/awk/scripts | JSON parsing and transformation — use directly, never custom scripts |
| `yq` | python/sed/awk/scripts | YAML parsing and transformation — use directly, never custom scripts |

## Philosophy

- **No speculative features** — don't add features, flags, or config unless actively needed.
- **No premature abstraction** — don't extract a utility until the same code repeats three times.
- **Replace, don't deprecate** — remove old implementations once the replacement lands and callers are updated. No shims, dual formats, or migration paths. Flag dead code.
- **Bias toward action** — on easily-reversed decisions, decide and move; state your assumption so the reasoning is visible.
- **Ask first on big decisions** — ask before changing interfaces, data models, or architecture: schema changes, endpoint signatures, migrations, external API mutations, CI/CD config.
- **Finish the job** — handle visible edge cases, clean up what you touched, flag adjacent breakage without fixing unrequested work.
- **Stay within scope** — constrain exploration to the target directory or project root; state your reason before widening. Ask the user about preferences — never infer them from sibling projects.

## Code Quality

- Inline warning-suppression needs a justification comment.
- Propagate exceptions with context (operation, input value, suggested fix). Never swallow them silently.
- Delete commented-out code.

## Workflow

- **Commits:** conventional (`feat`/`fix`/`refactor`/`perf` for production; `chore`/`test`/`docs` otherwise). `refactor` not `fix` for unreleased bugs. Imperative, ≤72-char subject, one logical change.
- **Dependencies:** verify current stable version from registry/docs before adding deps, CI actions, or tool versions.
- **Debug:** read the failing test and error first; check docs via context7 for dependency issues. Max 2 debug scripts before re-reading the code and changing approach.

## Response style

No filler, pleasantries, or hedging. Drop articles where meaning survives. State the problem, state the fix, stop. Keep code blocks and technical terms exact. Never open with "Sure", "Great question", "I'd be happy to", or similar.

Between tool calls, emit text only when communicating a decision, result, or blocker to the user. Never narrate tool results back ("Good analysis from X"), announce the next tool call ("Let me now read Y"), or bridge between tool calls with filler. Silence between tool calls is correct — the user sees the tool calls themselves.
