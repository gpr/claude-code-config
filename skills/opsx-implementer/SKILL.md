---
name: opsx-implementer
description: Implement OpenSpec with review and archiving steps
argument-hint: "<change-id>"
model: claude-sonnet-4-6
effort: medium
disable-model-invocation: true
user-invocable: true
author: gregory.rome@teads.com
version: 1.0.0
date: 2026-06-08
---

## Context

<change-id>$ARGUMENTS[0]</change-id>
<open-changes>!`openspec list`</open-changes>
<repo-status>!`git status --porcelain`</repo-status>

## Preparation

1. IF <change-id> is not provided, select the first one if alone, otherwise prompt the user to select one from the list of <open-changes>. ELSE validate that it exists in the list of <open-changes>
2. If <repo-status> indicates uncommitted changes, prompt the user to commit or stash them before proceeding
3. Execute all the tests to know the current state of the codebase before starting work on the change

## Task

Use TaskCreate to create the following tasks, marking each `completed` the moment it lands:

- `Implement code for change <change-id>`
- `Review code change`
- `Fix review findings`
- `Sync specs`
- `Archive change`
- `Commit`

### Implementation steps

1. Execute `/openspec-apply-change <change-id>` to scaffold the implementation for the change <change-id>, loop coding until all tests pass
2. Launch @"code-reviewer (agent)" to review the implementation, providing the implementation `git diff` and the spec files `tree openspec/changes/<change-id>/` as input
3. Loop on all findings from the code review:
    - If `blocker` or `nit`, fix it directly in the test files
    - If `question`, AskUserQuestion with the finding details
4. Execute `/openspec-sync-specs` for <change-id>
5. Launch an Haiku Agent to execute `/openspec-archive-change` for <change-id>
6. Commit
