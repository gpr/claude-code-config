# Subagent Quality Criteria

Only recommend creating or updating a subagent if ALL criteria pass.

## Required Criteria

- [ ] **Isolation justified**: Separate context genuinely helps (or would have helped)
- [ ] **Bounded scope**: Clear definition of "done" exists
- [ ] **Tool set definable**: Can specify which tools needed (and which restricted)
- [ ] **Recurring role**: This delegation pattern will repeat across sessions

## Anti-patterns (Reject These)

- Single-use complex tasks (just do them, don't systematize)
- Work that needs constant back-and-forth with user
- "Subagent" that's really just a skill with extra steps
- Subagent for tasks under 5 minutes of focused work

## Confidence Scoring

**HIGH**: All criteria pass + clear specialist role identified + would save significant context
**MEDIUM**: All criteria pass + role is useful but not critical
**LOW**: One criterion questionable → Do not recommend, add to Deferred
