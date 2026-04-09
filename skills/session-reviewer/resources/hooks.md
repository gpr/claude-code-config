# Hook Quality Criteria

Only recommend creating or updating a hook if ALL criteria pass.

## Required Criteria

- [ ] **Event-driven**: Clear, specific trigger event (file save, tool use, subagent stop, etc.)
- [ ] **Automatic benefit**: Should happen without user asking every time
- [ ] **Non-blocking**: Won't significantly slow down workflow
- [ ] **Consistent**: Same trigger always warrants same response (no judgment needed)

## Anti-patterns (Reject These)

- Actions that need user judgment each time
- Expensive operations that should be batched instead
- "Hooks" that are really just reminders (put in CLAUDE.md)
- Hooks that duplicate Claude's built-in behaviors

## Valid Hook Events

Reference these when defining trigger:
- `PreToolUse` — Before a tool executes
- `PostToolUse` — After a tool completes
- `SubagentStop` — When a subagent finishes
- `Stop` — When Claude finishes responding

## Confidence Scoring

**HIGH**: All criteria pass + same action was manually done 3+ times in session
**MEDIUM**: All criteria pass + pattern appeared 1-2 times
**LOW**: One criterion questionable → Do not recommend, add to Deferred
