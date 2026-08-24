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

## Bash Retry Logging

When a Bash command's output causes you to issue a different follow-up Bash command (retry, refined query, alternate approach — not a plain re-run), append one line to `~/.claude/logs/bash-retry.jsonl` before running the new command:

```
echo '{"ts":"<ISO8601>","prev_command":"<...>","new_command":"<...>","reason":"<why the output triggered this>"}' >> ~/.claude/logs/bash-retry.jsonl
```

Skip this for routine multi-step workflows (e.g. `mkdir` then `cd`) — only log when the prior output's content (error, empty result, unexpected format) drove the change.

## Working Style

- If a slash command or skill is loaded with no accompanying task, ask one short question and stop. Do not start autonomous repo exploration or open multi-step investigations unprompted.

## Sandbox & Tooling

Bash runs sandboxed. Writes are allowed only under cwd, `$TMPDIR`, `/tmp/claude`, and the paths in `settings.json` → `sandbox.filesystem.allowWrite`. `git`, `docker`, `aws`, `gh`, `trash`, and `prek` are in `excludedCommands`, which exempts them from *command* approval — it does **not** grant them writes outside those paths.

- Committing to a repo whose `.git` is outside the project root fails: from a `~/.claude` session, `git -C ~ add <file>` gives `Unable to create '/Users/gregory.rome/.git/index.lock': Operation not permitted`. Use `dangerouslyDisableSandbox: true` for that git call. Read-only git (`status`, `diff`, `log`) works fine.

- Sandbox path settings take absolute paths only. Neither `$HOME` nor `~` is expanded — a relative-looking entry resolves against cwd and silently matches nothing. A trailing `/**` is allowed and stripped.
- `Operation not permitted` on a path outside cwd is usually the sandbox, not a real permissions problem. Confirm by rerunning with `dangerouslyDisableSandbox: true`.
- Project trees are intentionally not on `allowWrite`. Writing into a git worktree outside the project root (`mise trust`, `chmod`, installs) fails; `git` itself is exempt, so `git worktree add` works. Use `dangerouslyDisableSandbox: true` for the follow-on step — `cd` does not help, since `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1` pins the writable root to the project dir.
- Writes to `~/.claude/{skills,agents,hooks,commands,projects,plugins,settings*.json}` are blocked by a hardcoded protection list that `allowWrite` cannot override. Use Edit/Write instead of Bash, or `dangerouslyDisableSandbox`.
- `fd` and `rg` honour `.gitignore`. The allowlist-style `.gitignore` in `$HOME` hides almost everything, so they return nothing there — use `fd -I` / `rg --no-ignore`, or `find`.
