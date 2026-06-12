---
name: opsx-apply-tdd
description: |
  Implement OpenSpec in a strict test-driven way.
argument-hint: "<change-id>"
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

## Tasks

Create a Team of two teammates: `tdd-implementer` and `implementer`. Assign them the following sequential tasks:

1. `tdd-implementer`, claude-opus-4-6: execute `/opsx-test-implementer <change-id>`
2. `implementer`, claude-sonnet-4-6: execute `/opsx-implementer <change-id>`

Ensure that `implementer` starts only after `tdd-implementer` has completed, to respect the TDD process.

3. Once `implementer` has completed tear down the team

## Rules

- use only the `TaskCreate` tool to create tasks for the teammates, never create tasks directly in the chat
- use only `SendMessage` to communicate with the teammates, never write messages directly in the chat
- Use only the `AskUserQuestion` tool to ask the user, never ask questions directly in the chat.
- Ensure that each teammate completes their assigned task
- Handle user questions issued from the teammates if any, use `AskUserQuestion`, and relay the answer back to them with `SendMessage`.
