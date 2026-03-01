# ~/.claude

Personal Claude Code configuration — global settings, guardrails, and scripts that apply to every project.

## What's here

```
.claude/
├── CLAUDE.md          # Global instructions: philosophy, workflow, tool preferences
├── CLAUDE.doc.md      # Reference doc explaining what each instruction does
├── settings.json      # Model, permissions, hooks, sandbox, plugins
└── scripts/
    ├── statusline.sh  # Two-line status bar (model, branch, context %, cost, time)
    └── format.sh      # PostToolUse hook — auto-formats files after edits
```

### CLAUDE.md

Development standards loaded into every session:

- **Tool preferences** — `rg` over grep, `fd` over find, `ast-grep` for code patterns, `trash` instead of rm
- **Philosophy** — no speculative features, no premature abstraction, replace don't deprecate, bias toward action, ask before big decisions
- **Code quality** — lint-ignore requires justification, fail fast with context, no commented-out code
- **Workflow** — conventional commits, run relevant tests before committing, never push to main, look up current versions

### settings.json

- **Permissions** — deny list blocks `rm -rf`, `sudo`, `git push --force`, reads of credentials/keychains/wallets
- **Hooks** — `format.sh` runs after every Write/Edit, bash hooks block `rm -rf` and direct pushes to main
- **Sandbox** — enabled with auto-allow bash, scoped network access, Docker excluded
- **Plugins** — Context7, code-review, security-guidance, plugin-dev, hookify, and others

### scripts/statusline.sh

Two-line status bar displayed below the prompt:

```
[Opus] my-project │ 🌿 feat/auth
████████⣿⣿⣿⣿ 67% │ $0.42 │ ⏱ 12m 34s ↻85%
```

Shows model, folder, git branch, context window usage with color-coded progress bar (green/yellow/red), session cost, elapsed time, and cache hit rate.

### scripts/format.sh

PostToolUse hook that auto-detects and runs the project's formatter after every file edit. Supports Prettier, ESLint, Ruff, Black, rustfmt, gofmt, clang-format, and more — picks the right tool based on file extension and project config.

## Credits

CLAUDE.md instructions and statusline script inspired by [trailofbits/claude-code-config](https://github.com/trailofbits/claude-code-config).
