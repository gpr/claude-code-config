# CLAUDE.md Instruction Outcomes

This document explains what each instruction in the two CLAUDE.md files causes Claude Code to do (or not do) in practice.

---

## `~/.claude/CLAUDE.md` — Global Development Standards

This file applies to **every project**. It shapes how Claude Code searches, edits, commits, and reasons across all repositories.

### Tools

| Instruction | Outcome |
|---|---|
| Use `repomix` MCP for broad understanding; built-in tools for targeted searches | Claude picks the right tool by scope: Repomix for "how does auth work across modules?", Grep/Glob for "find `parseToken` in `src/auth.ts`". Avoids slow whole-repo packs when a single file read suffices. |
| Use Context7 MCP for unfamiliar/version-sensitive APIs; skip for stable stdlib | Claude fetches live docs only when the API might have changed (e.g., Next.js App Router). Skips the network round-trip for `Array.map` or `os.path.join`. |
| Use `rg` instead of `grep` | All content searches run via ripgrep — faster and respects `.gitignore` by default. |
| Use `fd` instead of `find` | File lookups use `fd` — faster, saner defaults, `.gitignore`-aware. |
| Prefer `ast-grep` for code patterns; `rg` for strings/comments | Structural queries (function signatures, imports) use AST matching to avoid false positives. Literal text searches stay with `rg`. |
| Use `trash` instead of `rm`; **never `rm -rf`** | Every file deletion is recoverable. Prevents accidental permanent data loss. |

### Philosophy

| Instruction | Outcome |
|---|---|
| No speculative features | Claude will not add config flags, feature toggles, or "nice to have" parameters unless the current task requires them. Less code to maintain. |
| No premature abstraction | Claude writes inline/duplicate code until a pattern repeats three times, then extracts a shared helper. Prevents over-engineered one-off utilities. |
| Replace, don't deprecate | When swapping an implementation, Claude deletes the old code entirely instead of leaving compatibility shims, `@deprecated` markers, or dual paths. Dead code gets flagged for removal. |
| Bias toward action | For low-risk, reversible decisions, Claude picks an approach and states the assumption rather than asking. Keeps momentum; the stated assumption makes it easy to course-correct. |
| Ask before big decisions | Claude **stops and asks** before changing interfaces, schemas, data models, external API calls, CI config, or anything architecturally significant. Prevents irreversible mistakes. |
| Finish the job | Claude handles visible edge cases in the code it touches and cleans up surrounding mess, but does not expand scope to unrelated areas. Adjacent issues get flagged, not fixed. |

### Code Quality

| Instruction | Outcome |
|---|---|
| Lint-ignore requires justification comment | Every `// eslint-disable`, `# noqa`, `@SuppressWarnings`, etc. is accompanied by a comment explaining *why*. Prevents silent suppression of real bugs. |
| Fail fast with actionable errors | Error handling includes operation context, the offending input, and a suggested fix. No bare `catch {}` or `pass`. Problems surface immediately with enough info to act on. |
| No commented-out code | Dead code gets deleted, not commented. Keeps the codebase clean; version control already preserves history. |

### Workflow

| Instruction | Outcome |
|---|---|
| Run relevant tests before committing | Claude runs the test file(s) related to the change, not the full suite. Catches regressions without wasting time on unrelated tests. |
| Conventional commits | Every commit message follows the `type: subject` format (`feat`, `fix`, `refactor`, `perf`, `chore`, `test`, `docs`). Imperative mood, max 72-char subject, one logical change per commit. Enables automated changelogs and clear history. |
| Use `refactor` for unreleased bugs | Bugs caught before release get `refactor:` (not `fix:`) since there's nothing to "fix" from a user's perspective. Keeps the changelog accurate. |
| Never push directly to main | All work goes through branches/PRs. Protects the main branch from untested or unreviewed changes. |
| Never commit secrets | Claude refuses to stage files containing API keys, tokens, passwords, or credentials. |
| Look up current stable versions | When adding a dependency, GitHub Action, or tool version, Claude checks the live registry instead of guessing from training data. Prevents pinning to outdated or yanked versions. |
