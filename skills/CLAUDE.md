# Skills System Documentation

## Purpose & Philosophy

**Skills** are reusable knowledge capsules extracted from work sessions. They capture non-obvious solutions, project-specific patterns, and debugging techniques that would be valuable in future sessions.

Skills are **semantically triggered**: Claude Code's retrieval system searches skill descriptions and content when similar problems, error messages, or contexts appear. This makes skills fundamentally different from commands (which are explicitly invoked) and agents (which require deliberate delegation).

Think of skills as your project's growing memory—each valuable discovery gets preserved and automatically surfaces when relevant again.

## When to Create a Skill

### Quality Criteria (ALL Must Pass)

- **Reusable**: Will help in future sessions, not just this one instance
- **Non-trivial**: Required discovery or investigation, not a simple docs lookup
- **Specific**: Clear trigger conditions ("when you see X, do Y")
- **Verified**: Solution was actually applied and worked in session

### Good Candidates for Skills

1. **Non-obvious Solutions**
   - Debugging techniques that required significant investigation
   - Workarounds for tool/framework limitations
   - Solutions where error messages were misleading

2. **Project-Specific Patterns**
   - Conventions and configurations unique to this codebase
   - Architectural decisions not documented elsewhere
   - Setup procedures that differ from standard patterns

3. **Tool Integration Knowledge**
   - Library/API usage not well-covered in documentation
   - Integration patterns between multiple tools
   - Configuration gotchas discovered through trial-and-error

4. **Error Resolution**
   - Specific error messages and their actual root causes
   - Symptoms that indicate particular underlying issues
   - Debug procedures for recurring problem types

5. **Workflow Optimizations**
   - Multi-step processes that can be streamlined
   - Patterns that make common tasks more efficient
   - Shortcuts discovered through repetition

### Anti-Patterns (Don't Create Skills For)

- **Generic knowledge**: Things Claude already handles well
- **Simple facts**: Content that belongs in CLAUDE.md instead
- **One-off solutions**: Fixes that only work for this exact file/context
- **Documentation duplication**: Recreating what official docs already cover well
- **Trivial operations**: Standard procedures anyone would know
- **Unverified theories**: Solutions that weren't tested and confirmed

### Confidence Scoring

**HIGH**: All criteria pass + pattern appeared 2+ times in session → Create immediately

**MEDIUM**: All criteria pass + pattern appeared once → Validate with user first

**LOW**: One criterion questionable → Do not create, consider adding to Deferred or CLAUDE.md instead

## File Structure Conventions

Skills can be simple (single file) or complex (with supporting materials).

### Simple Skills (Single SKILL.md)

For straightforward knowledge that fits in one markdown file:

```
.claude/skills/
└── my-skill-name/
    └── SKILL.md
```

Use simple structure when:
- Solution is self-contained
- No code examples needed beyond inline snippets
- No supporting scripts or tools required

### Complex Skills (With Resources)

For richer skills with examples, scripts, or extensive documentation:

```
.claude/skills/
└── my-complex-skill/
    ├── SKILL.md           # Main skill content
    ├── resources/         # Supporting documentation
    │   ├── details.md
    │   └── references.md
    ├── examples/          # Concrete examples
    │   └── example-1.md
    └── scripts/           # Helper scripts
        └── helper.sh
```

Use complex structure when:
- Multiple detailed examples enhance understanding
- Supporting scripts make the skill easier to apply
- Additional documentation provides valuable context
- The skill references external resources extensively

## YAML Frontmatter Specification

Every SKILL.md file must start with YAML frontmatter between `---` delimiters.

### Required Fields

```yaml
---
name: descriptive-kebab-case-name
description: |
  Precise description that enables semantic matching. Include:
  (1) What problem this solves
  (2) Specific trigger conditions - exact error messages, symptoms, scenarios
  (3) Key technologies/frameworks involved
  Use phrases like "Use when:", "Helps with:", "Solves:"
author: Claude Code
version: 1.0.0
date: 2026-01-27
---
```

- **name**: kebab-case identifier, descriptive but concise (e.g., `nextjs-server-side-error-debugging`)
- **description**: Multi-line description optimized for semantic search (see Description Best Practices below)
- **author**: Creator of the skill (typically "Claude Code" or user's name)
- **version**: Semantic version (1.0.0 for new skills)
- **date**: Creation date in YYYY-MM-DD format

### Optional Fields

```yaml
---
# ... required fields ...
allowed-tools:
  - Read
  - Write
  - Bash
agent: Plan
---
```

- **allowed-tools**: List of tools Claude can use when applying this skill. Use to limit scope or prevent dangerous operations.
- **agent**: Specify a particular agent to invoke when this skill is triggered (rarely used, for complex skills requiring specialized context)

### Description Best Practices

The description field is **critical** for skill discovery. It determines when the skill surfaces during semantic matching.

**Include these elements:**

1. **Exact error messages**: Full error text that users will encounter
2. **Observable symptoms**: What the user experiences that leads them to need this skill
3. **Technology markers**: Framework names, tool names, file types (for context filtering)
4. **Action phrases**: "Use when...", "Helps with...", "Solves...", "Fix for..."
5. **Common variations**: Alternative phrasings of the problem

**Good description example:**

```yaml
description: |
  Fix for "ENOENT: no such file or directory" errors when running npm scripts
  in monorepos. Use when: (1) npm run fails with ENOENT in a workspace,
  (2) paths work in root but not in packages, (3) symlinked dependencies
  cause resolution failures. Covers node_modules resolution in Lerna,
  Turborepo, and npm workspaces.
```

**Bad description example:**

```yaml
description: Helps with npm problems in monorepos
```

The good example includes specific error text, multiple trigger conditions, and exact tool names that will match user queries.

## Standard Markdown Sections

After the YAML frontmatter, structure your skill content with these sections:

### 1. Problem

Clear, concise description of the problem this skill addresses. What pain point does this solve? Why is it non-obvious?

```markdown
## Problem

Server-side errors in Next.js don't appear in the browser console, making
debugging frustrating when you're looking in the wrong place.
```

### 2. Context / Trigger Conditions

When should this skill be activated? Be specific with exact error messages, observable symptoms, and environmental conditions.

```markdown
## Context / Trigger Conditions

- Page displays "Internal Server Error" or custom error page
- Browser console shows no errors
- Using getServerSideProps, getStaticProps, or API routes
- Error only occurs on navigation/refresh, not on client-side transitions
```

### 3. Solution

Step-by-step instructions to resolve the problem. Use subsections for complex solutions.

```markdown
## Solution

### Step 1: Check Server Logs

The error appears in the terminal where `npm run dev` is running, not in the browser.

### Step 2: Add Error Handling

Add try-catch blocks with console.error for clarity:

\`\`\`typescript
export async function getServerSideProps() {
  try {
    // Your code here
  } catch (error) {
    console.error('Server-side error:', error);
    throw error;
  }
}
\`\`\`

### Step 3: Use Next.js Error Handling

Return `{ notFound: true }` or `{ redirect: {...} }` instead of throwing.
```

### 4. Verification

How to confirm the solution worked. Include expected outcomes.

```markdown
## Verification

After checking terminal, you should see:
1. Actual stack trace with file and line numbers
2. Error details that weren't visible in browser
3. Ability to identify the exact line causing the issue
```

### 5. Example

Concrete example of applying this skill. Show before/after or input/output.

```markdown
## Example

**Scenario**: API call fails in getServerSideProps

**Before**:
- Browser shows generic error page
- Console is empty
- No idea where to look

**After**:
- Check terminal running `npm run dev`
- See: `TypeError: Cannot read property 'data' of undefined at pages/index.tsx:42`
- Fix the null check on line 42
```

### 6. Notes

Important caveats, edge cases, related considerations, and when NOT to use this skill.

```markdown
## Notes

- This applies to all server-side code in Next.js, not just data fetching
- In development, Next.js sometimes shows a modal with partial error info
- The `reactStrictMode` option can cause double-execution that makes debugging confusing
- Don't use this for client-side React errors—those DO appear in browser console
```

### 7. References (Optional)

Links to official documentation, articles, or resources that informed this skill. Include when web research was conducted.

```markdown
## References

- [Next.js Data Fetching: getServerSideProps](https://nextjs.org/docs/pages/building-your-application/data-fetching/get-server-side-props)
- [Next.js Error Handling](https://nextjs.org/docs/pages/building-your-application/routing/error-handling)
- [Stack Overflow: Server-side errors in Next.js](https://stackoverflow.com/questions/...)
```

## Quality Gates

Before finalizing a skill, verify:

- [ ] **Completeness**: All required frontmatter fields present
- [ ] **Searchability**: Description contains specific trigger conditions and error messages
- [ ] **Verification**: Solution was tested and confirmed to work
- [ ] **Specificity**: Content is specific enough to be actionable
- [ ] **Reusability**: Content is general enough to apply in multiple contexts
- [ ] **Security**: No sensitive information (credentials, internal URLs, API keys)
- [ ] **Uniqueness**: Doesn't duplicate existing skills or documentation
- [ ] **Research**: Web research conducted for technology-specific topics (when appropriate)
- [ ] **Citations**: References section included if web sources were consulted
- [ ] **Currency**: Current best practices incorporated (post-2025 when relevant)

## Supporting Documentation Patterns

### When to Create resources/

Create a `resources/` subdirectory when:
- Additional context documents enhance understanding
- Technical deep-dives provide valuable background
- Research findings should be preserved
- Comparison matrices or decision trees are needed

Example: `skills/my-skill/resources/architecture-details.md`

### When to Create examples/

Create an `examples/` subdirectory when:
- Multiple concrete examples improve clarity
- Different use cases need separate demonstrations
- Real-world scenarios are complex enough to warrant dedicated files

Example: `skills/my-skill/examples/production-scenario.md`

### When to Create scripts/

Create a `scripts/` subdirectory when:
- Helper scripts make applying the skill easier
- Automation tools support the solution
- Test fixtures or setup scripts are needed

Example: `skills/my-skill/scripts/setup-environment.sh`

## Versioning & Maintenance

### Semantic Versioning

Skills follow semantic versioning:

- **1.0.0**: Initial creation
- **1.1.0**: Minor updates (additional examples, clarifications, non-breaking improvements)
- **2.0.0**: Major updates (substantial solution changes, breaking changes to approach)

Update the `version` and `date` fields in YAML frontmatter when modifying skills.

### When to Update a Skill

Update an existing skill rather than creating a new one when:
- You discover additional trigger conditions for the same problem
- The solution can be enhanced without changing its fundamental approach
- Edge cases or caveats need to be added
- Better examples become available
- References to documentation need updating

### Deprecation

When a skill becomes outdated:

1. Add a deprecation notice at the top of the skill:
   ```markdown
   > **DEPRECATED**: This skill is outdated as of [date]. Use [new-skill-name] instead.
   > Reason: [Brief explanation of why this is deprecated]
   ```

2. Update the version to indicate deprecation (e.g., 1.2.0-deprecated)

3. Consider moving to an `archived-skills/` directory after a grace period

### Archival

When skills are no longer relevant:
- Move to `.claude/skills/archived/[skill-name]/`
- Keep for historical reference but won't be semantically matched
- Document why it was archived in a README.md in the archived directory

## Relationship to Other Components

### Skills vs Agents vs Commands

**Use a Skill when:**
- Knowledge is reusable and pattern-based
- Semantic triggering is desired (automatic activation)
- The solution fits in documentation form
- You want to capture "how we do things"

**Use an Agent instead when:**
- Work requires isolation and focused context
- Multiple tools need orchestration in a specific way
- A specialist role/persona is needed
- Task is complex enough to justify dedicated execution environment

**Use a Command instead when:**
- Workflow needs explicit invocation
- Procedure is short and repetitive (< 50 lines)
- Parameters need to be passed from user
- It's a quick reference pattern, not deep knowledge

**Decision Tree:**

```
Is it automatically triggered by context?
├─ Yes → Skill
└─ No → Is it explicitly invoked?
    ├─ Yes → Is it < 50 lines and procedural?
    │   ├─ Yes → Command
    │   └─ No → Agent
    └─ Unclear → Start with Skill (simplest)
```

### Skills Complement CLAUDE.md

- **CLAUDE.md**: Project conventions, preferences, architectural decisions—always-on context
- **Skills**: Specific problem-solution pairs—activated when semantically relevant

If something applies to every interaction (code style preferences, architectural principles), put it in CLAUDE.md. If it's triggered by specific contexts (error messages, particular tasks), make it a skill.

## Installation & Locations

### User-Level Skills

Located in `~/.claude/skills/`, available across all projects:

```
~/.claude/skills/
├── global-skill-1/
│   └── SKILL.md
└── global-skill-2/
    └── SKILL.md
```

Use for skills that apply across multiple projects (general debugging techniques, common framework patterns).

### Project-Level Skills

Located in `.claude/skills/`, specific to the current project:

```
project-root/
└── .claude/skills/
    ├── project-specific-skill/
    │   └── SKILL.md
    └── another-local-skill/
        └── SKILL.md
```

Use for project-specific conventions, local architectural patterns, or team-specific workflows. **Commit these to version control** to share with team.

### Precedence

Project-level skills take precedence over user-level skills when names conflict. This allows project-specific overrides of global patterns.

## Examples & Templates

### Template

See `/Users/gregory.rome/.claude/skills/claudeception/resources/skill-template.md` for the complete template with all sections and checklist.

### Example Skills in This Repository

**Simple skill example:**
- `atlassian-mcp-confluence-publishing/SKILL.md` - Single-file skill

**Complex skill examples:**
- `claudeception/SKILL.md` - Meta-skill with resources/ and examples/ directories
- `session-reviewer/SKILL.md` - Skill with multiple supporting documentation files

**Well-structured skill examples:**
- `typescript-project-standards/SKILL.md` - Project setup conventions
- `python-project-standards/SKILL.md` - Project setup conventions

### Quick Start: Creating Your First Skill

1. Create directory: `.claude/skills/my-skill-name/`
2. Copy template from `claudeception/resources/skill-template.md`
3. Fill in YAML frontmatter with emphasis on detailed description
4. Write clear Problem and Solution sections
5. Add concrete Example
6. Test by checking if description would match your actual problem statement
7. Commit to project or user config

## Continuous Improvement

Skills are living knowledge. As you work:

1. **Notice patterns**: Did this problem come up again? Is the skill still accurate?
2. **Update liberally**: Better examples, additional edge cases, refined descriptions
3. **Remove friction**: If a skill isn't surfacing when needed, improve its description
4. **Retire gracefully**: Deprecate skills when tools/frameworks change

The goal is a growing, curated knowledge base that makes each session more efficient than the last.

---

**See Also:**
- `/Users/gregory.rome/.claude/agents/CLAUDE.md` - Agents documentation
- `/Users/gregory.rome/.claude/commands/CLAUDE.md` - Commands documentation
- `/Users/gregory.rome/.claude/skills/claudeception/SKILL.md` - Meta-skill for extracting skills
- `/Users/gregory.rome/.claude/skills/session-reviewer/SKILL.md` - Reviewing sessions for extractable knowledge
