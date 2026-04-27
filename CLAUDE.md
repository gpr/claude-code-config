# Global Development Standards

## Tools

- Use `plugin:repomix-mcp:repomix` MCP tools when you need a broad understanding of project structure, cross-cutting concerns, or multi-module relationships. For targeted searches (specific function, single file, known path), use built-in Read/Grep/Glob.
- Use `plugin:context7:context7` MCP tools for library documentation when the API is unfamiliar, recently changed, or version-sensitive. Skip for stable, well-known standard library calls.
- Prefer LSP (symbol lookups, diagnostics) over Grep for finding code references, type errors, and renaming. Use Grep only for string literals, log messages, and comments.

### CLI tools

When running Bash commands, prefer these over defaults:

| tool | replaces | notes |
|------|----------|-------|
| `rg` | grep | fast regex |
| `fd` | find | fast file finder |
| `ast-grep` | - | AST-aware search — prefer over rg when matching code patterns (function signatures, import statements, class definitions). Use rg for string literals, comments, log messages. |
| `trash` | rm | recoverable delete (destructive `rm` flags are blocked by hooks) |
| `jq` | python/sed/awk/scripts | JSON parsing and transformation — use `jq` directly in Bash, never custom scripts |
| `yq` | python/sed/awk/scripts | YAML parsing and transformation — use `yq` directly in Bash, never custom scripts |

## Philosophy

- **No speculative features** — Don't add features, flags, or configuration unless actively needed.
- **No premature abstraction** — Don't create utilities until you've written the same code three times.
- **Replace, don't deprecate** — Remove old implementations entirely when the replacement is in place and all internal callers are updated. No shims, dual formats, or migration paths. Flag dead code.
- **Bias toward action** — For easily reversed decisions, decide and move. State your assumption so the reasoning is visible.
- **Ask before making big decisions** — YOU MUST ask before changing interfaces, data models, architecture, or running destructive/write operations on external services. This includes: schema changes, endpoint signature changes, database migrations, external API mutations, CI/CD config changes.
- **Finish the job** — Handle edge cases you can see. Clean up what you touched. Flag adjacent breakage you notice, but don't fix things you weren't asked to fix.
- **Stay within scope** — Constrain all exploration to the target directory or project root. Exhaust what is inside before looking outside, and state your reason if you must widen. Never scan sibling projects to infer preferences — ask the user directly.

## Code Quality

- When suppressing a warning with an inline ignore, YOU MUST add a justification comment explaining why.
- Propagate all exceptions with context: operation name, input value, and a suggested fix. Never swallow exceptions silently.
- No commented-out code — delete it.
- **Verify API and library function signatures** from documentation (context7), source code, or LSP before using them.

## Workflow

**Commits:** Conventional commits (`feat`/`fix`/`refactor`/`perf` for production; `chore`/`test`/`docs` for the rest). Use `refactor` (not `fix`) for bugs not yet released. Imperative mood, ≤72 char subject, one logical change per commit.

**Dependencies:** When adding dependencies, CI actions, or tool versions, always verify the current stable version from the registry or documentation.

## Response style

No filler, no pleasantries, no hedging. Drop articles where meaning survives. State the problem, state the fix, stop. Code blocks and technical terms stay exact. Never open with "Sure", "Great question", "I'd be happy to", or similar.

@RTK.md
