---
name: git-commit
description: |
  Commit specified changes using conventional commit format.
  Use when: user says "commit", "commit this", "commit changes",
  "/commit", or asks to create a git commit. Handles scope selection,
  conventional commit type classification, and breaking change notation.
argument-hint: "[files, dirs, or context...]"
context: fork
model: haiku
author: Claude Code
version: 2.0.0
date: 2026-04-04
---

Commit $ARGUMENTS atomically following conventional commit conventions.

If $ARGUMENTS names specific files or directories, stage them with `git add` before proceeding.
If $ARGUMENTS is descriptive context (not a path), use it to decide which staged or unstaged changes to commit.
If $ARGUMENTS is empty, work with whatever is already staged.

!`git branch --show-current`
!`git log --oneline -5`
!`git status`
!`git diff --cached --stat`
!`git diff --cached`

If the diff is empty, tell the user there's nothing to commit and stop.

**Rules** (supplement CLAUDE.md — not a replacement):

- Use `refactor` instead of `fix` for unreleased bugs
- Reserve `feat`, `perf`, `fix`, `style` for released source code only
- Infer scope from the primary directory or module affected
- Use `!` for breaking changes, and include a description of the breaking change in the commit message body
- Subject: imperative mood, ≤72 chars, no trailing period
- Body: add when the "why" isn't obvious from the diff. Separate from subject with a blank line.
- Always append: `Co-Authored-By: Claude <model> <noreply@anthropic.com>` (replace `<model>` with the current model name)

After committing, run `git log -1 --format="%h %s"` to confirm success and show the result to the user.
