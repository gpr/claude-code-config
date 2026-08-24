---
name: spec-plan-implement-review
description: |
  This skill should be used when the user asks to "spec out a change", "run the
  spec-plan-implement-review workflow", "propose and implement a change with
  spec and plan", or wants a full spec → plan → implement → review → archive
  cycle for a change under specs/ and changes/.
argument-hint: "[request]"
author: Grégory Romé
version: 1.1.0
date: 2026-08-19
---

You are an agent lead for a structured development process.

## Context

Use the user's request: <request>$ARGUMENTS</request> and the existing context.

## Workflow

First clarify the request with the user, explore the current specification `specs/` to identify which areas need improvement, AskUserQuestion to gather more information and clarify the requirements.

Create a <change-id> (kebab-case slug summarizing the change, e.g. `add-retry-backoff`) and a corresponding changes/<change-id> directory to track the changes.
Write down the proposal for the changes in a changes/<change-id>/proposal.md file, including the rationale for the changes and any relevant references. Evaluate the <complexity> (low/medium/high/xhigh) of the change for the agent and document it in changes/<change-id>/proposal.md.

Launch an opus agent to review changes/<change-id>/proposal.md and create a specification for the proposed changes. The specification should include detailed descriptions of the changes, their impact. Get the result and write it down in changes/<change-id>/spec.md.

Commit changes/<change-id>/spec.md

Launch an sonnet Plan agent to create a design and a plan for the proposed changes based on changes/<change-id>/proposal.md and changes/<change-id>/spec.md. Get the result and write it down in changes/<change-id>/plan.md and changes/<change-id>/design.md.

Commit changes/<change-id>/plan.md and changes/<change-id>/design.md.

If the <complexity> is high or xhigh, launch an opus agent to review changes/<change-id>/plan.md and changes/<change-id>/design.md and fix the issues directly in changes/<change-id>/plan.md and changes/<change-id>/design.md.

Launch a sonnet general-purpose agent to implement the proposed changes based on changes/<change-id>/design.md, changes/<change-id>/proposal.md, changes/<change-id>/spec.md and changes/<change-id>/plan.md. The implementation should include code, configuration files, and any other relevant artifacts needed to realize the proposed changes. Never modify changes/<change-id>/. Ensure that all tests are green.

Commit all the related changes

In parallel:
- Perform a review with `/code-review <complexity> --fix`.
- Launch a general-purpose agent (opus) to verify the implementation against changes/<change-id>/spec.md and fix all issues directly in the implementation. Ensure that all tests are green.

Commit all the related changes

Update specs/ with the changes/<change-id>/spec.md, move changes/<change-id>/ to changes/archived/<change-id>/, and commit the changes.

Record the change in the changelog with a summary of the changes, their impact, and any relevant references. Add the total time spent on the change and the total number of tokens used (in/out/cached) to the changelog entry. Commit the changelog.
