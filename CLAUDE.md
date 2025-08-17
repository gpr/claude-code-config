# Global Development Standards

## Tools

- Use `plugin:repomix-mcp:repomix` MCP tools when you need a broad understanding of project structure, cross-cutting concerns, or multi-module relationships. For targeted searches (specific function, single file, known path), use built-in Read/Grep/Glob.
- Use Context7 MCP for library documentation when the API is unfamiliar, recently changed, or version-sensitive. Skip for stable, well-known standard library calls.

### CLI tools

IMPORTANT: When running Bash commands, always use these tools instead of their defaults

| tool | replaces | notes |
|------|----------|-------|
| `rg` | grep | fast regex |
| `fd` | find | fast file finder |
| `ast-grep` | - | AST-aware search — prefer over rg when matching code patterns (function signatures, import statements, class definitions). Use rg for string literals, comments, log messages. |
| `trash` | rm | recoverable delete — **never `rm -rf`** |

## Philosophy

- **No speculative features** — Don't add features, flags, or configuration unless actively needed.
- **No premature abstraction** — Don't create utilities until you've written the same code three times.
- **Replace, don't deprecate** — Remove old implementations entirely when the replacement is in place and all internal callers are updated. No shims, dual formats, or migration paths. Flag dead code.
- **Bias toward action** — For easily reversed decisions, decide and move. State your assumption so the reasoning is visible.
- **Ask before committing to big decisions** — YOU MUST ask before changing interfaces, data models, architecture, or running destructive/write operations on external services. This includes: schema changes, endpoint signature changes, database migrations, external API calls that mutate state, CI/CD config changes.
- **Finish the job** — Handle edge cases you can see. Clean up what you touched. Flag adjacent breakage you notice, but don't fix things you weren't asked to fix.

## Code Quality

- When suppressing a warning with an inline ignore, YOU MUST add a justification comment explaining why.
- Fail fast with clear, actionable error messages. Never swallow exceptions silently. Include context: what operation, what input, suggested fix.
- No commented-out code — delete it.

## Workflow

**Before committing:** Run relevant tests — not the full suite. Use project-level CLAUDE.md for the specific command to run individual test files.

**Commits:** Conventional commits (`feat`/`fix`/`refactor`/`perf` for production; `chore`/`test`/`docs` for the rest). Use `refactor` (not `fix`) for bugs not yet released. Imperative mood, ≤72 char subject, one logical change per commit. Never push directly to main. Never commit secrets.

**When adding dependencies, CI actions, or tool versions:** YOU MUST look up the current stable version — never assume from memory.