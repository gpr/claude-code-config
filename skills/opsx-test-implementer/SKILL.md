---
name: opsx-test-implementer
description: Implement OpenSpec tests with review steps, no production code
argument-hint: "<change-id>"
model: claude-opus-4-6
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

- `Implement tests for change <change-id>`
- `Review tests`
- `Fix review findings`
- `Commit`

### Steps

1. Implement tests for an OpenSpec change <change-id>. You are given spec and design documents; read them end to end before writing any test. Every test you write must be **independently derivable from the spec** — no guessing at implementation details. Write only tests, no production code. If `openspec/changes/<change-id>/tasks.md` contains tasks related to testing, implement them as well and make the tasks completed as you implement them.
2. Launch @"tdd-reviewer (agent)" by providing the test implementation `git diff` and the spec files `tree openspec/changes/<change-id>/specs/` as input, to audit the new tests for change <change-id>
3. Loop on all findings from the test review:
    - If `blocker` or `nit`, fix it directly in the test files
    - If `question`, AskUserQuestion with the finding details
4. Commit

## TDD mindset

You are writing tests *before* production code exists. Write no production
code — only tests. Your job is to define the desired behavior so precisely
that only a correct implementation can turn the suite green.

**The single question for every test you write**: "Could a wrong
implementation pass this?" If yes, strengthen the assertion or add a
triangulating case.

### Driving correct implementations

- **Triangulation**: Test at least two distinct inputs per rule so the
  implementation cannot hardcode a return value. If `f(1) = 1`, also test
  `f(2) = 4` to force the general rule.
- **Boundary cases**: Test at edges the spec defines — zero, empty, max,
  off-by-one, type boundaries.
- **Error paths**: Every spec-defined error condition gets a test asserting
  the specific error type/message, not just "throws."
- **Ordering and structure**: When the spec defines output shape or
  ordering, assert the full structure, not just length or type.
- **Exact assertions**: Assert exact values the spec pins — never settle
  for "not null", "no error", or type-only checks.
- **One operation per test**: Multiple asserts are fine only when they
  verify facets of the same operation.
- **Public interfaces only**: Test observable outputs. Never assert on
  private methods, internal call order, or mechanisms the spec does not
  mandate.
- **Mock only at boundaries** (external I/O, network, databases, time).
  Let internal domain objects interact naturally — over-mocking tests
  wiring, not logic.

## Source of truth

The **spec is the contract**. Read every `openspec/changes/<change-id>/specs/**/spec.md`
end to end before writing any test.
Read `openspec/changes/<change-id>/design.md`, it fixes structure and mechanism
the spec leaves open — derive tests from both.
