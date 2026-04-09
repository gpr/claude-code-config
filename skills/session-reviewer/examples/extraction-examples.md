# Extraction Examples

Examples of good vs bad extraction decisions.

## Good Skill Extraction

**Session moment**: User struggled for 20 minutes to configure ESLint with TypeScript and Prettier. Solution required specific plugin order and config overrides not in any docs.

**Why extract**: Non-obvious, verified working, will help future TypeScript projects.

**Result**:
```markdown
---
name: eslint-ts-prettier
description: Configure ESLint with TypeScript and Prettier without conflicts. Use when setting up linting for TypeScript projects or resolving ESLint/Prettier conflicts.
---
```

## Bad Skill Extraction (Reject)

**Session moment**: User asked how to create a React component.

**Why reject**: Trivial knowledge Claude already has. Not project-specific.

---

## Good Subagent Extraction

**Session moment**: User asked to review a PR. Claude read 15 files, analyzed patterns, checked test coverage, reviewed security implications. Main context became cluttered, later questions got worse responses.

**Why extract**: Clear specialist role, isolation would have helped, bounded scope ("review this PR"), will recur.

**Result**:
```markdown
---
name: pr-reviewer
description: Review pull requests for code quality, security, and test coverage. Use when reviewing PRs or analyzing code changes.
tools: Read, Grep, Glob
---
```

## Bad Subagent Extraction (Reject)

**Session moment**: User asked to rename a variable across 3 files.

**Why reject**: Simple task, doesn't need isolation, won't recur as a "role."

---

## Good Hook Extraction

**Session moment**: Three times during session, user asked Claude to run tests after modifying code. Forgot once and introduced a regression.

**Why extract**: Clear trigger (file modification), consistent action needed, no judgment required.

**Result**:
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write",
      "command": "npm test --reporter=dot"
    }]
  }
}
```

## Bad Hook Extraction (Reject)

**Session moment**: User sometimes wanted to commit after changes, sometimes not.

**Why reject**: Requires user judgment each time. Better as a reminder in CLAUDE.md.
