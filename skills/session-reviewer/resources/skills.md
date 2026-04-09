# Skill Quality Criteria

Only recommend creating or updating a skill if ALL criteria pass.

## Required Criteria

- [ ] **Reusable**: Will help in future sessions, not just this one instance
- [ ] **Non-trivial**: Required discovery or investigation, not a simple docs lookup
- [ ] **Specific**: Clear trigger conditions ("when you see X, do Y")
- [ ] **Verified**: Solution was actually applied and worked in session

## Anti-patterns (Reject These)

- Generic knowledge Claude already handles well
- Simple facts that belong in CLAUDE.md instead
- Solutions that only work for this exact file/context
- Duplicates existing skill with trivial differences

## Confidence Scoring

**HIGH**: All criteria pass + pattern appeared 2+ times in session
**MEDIUM**: All criteria pass + pattern appeared once
**LOW**: One criterion questionable → Do not recommend, add to Deferred
