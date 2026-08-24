---
name: incident
description: Works with incident.io incidents through the incident_io MCP server — pins the active incident, reads incident, alert, escalation and on-call data, posts updates to incident channels, and routes requests to incident.io's backend agents. Use when the user mentions an incident reference such as INC-123, says "my incident" or "the incident", mentions being paged or on-call, says "@incident ...", or runs /incident.
allowed-tools:
  # Read-only tools only. incident_message, incident_create, incident_update,
  # follow_up_create, ask and ask_incident are deliberately omitted so they
  # keep prompting — they mutate a live incident. Do not "fix" this.
  - mcp__incident_io__incident_pin
  - mcp__incident_io__identity_get
  - mcp__incident_io__incident_show
  - mcp__incident_io__incident_list
  - mcp__incident_io__incident_stats
  - mcp__incident_io__escalations_list
  - mcp__incident_io__escalation_list
  - mcp__incident_io__escalation_show
  - mcp__incident_io__escalation_stats
  - mcp__incident_io__alert_list
  - mcp__incident_io__alert_show
  - mcp__incident_io__alert_stats
  - mcp__incident_io__follow_up_list
  - mcp__incident_io__schedule_list
  - mcp__incident_io__schedule_show
  - mcp__incident_io__catalog_type_list
  - mcp__incident_io__catalog_entry_list
  - mcp__incident_io__catalog_entry_show
  - ReadMcpResourceTool
---

# incident.io

Tools are named `mcp__incident_io__<name>`; this file uses the short name.
Each tool's schema documents its own parameters and response shape — read
that instead of expecting it here.

## Find the incident

1. **Reference given** (`INC-123`, `inc-456`) → `incident_pin(incident_id=…)`.
2. **"my incident", "the incident", no reference** → `incident_pin()` to read
   the pinned one.
3. **Nothing pinned** ("I got paged") → `escalations_list`, then offer the top
   3–5 as one line each via `AskUserQuestion`:
   `INC-123 Database CPU is high (paged 2 min ago)`. Recommend one if it's
   clearly most relevant. Don't dump full escalation details. Pin the choice.

Then `incident_show` for structured detail, or `ask_incident` for a narrative
summary. Use `AskUserQuestion` for any list the user has to choose from.

## MCP resources

Read these with `ReadMcpResourceTool(server="incident_io", uri=…)` — the
`Read` tool cannot fetch them.

- `config://organisation` — severity, custom field, role and priority IDs,
  needed for filtering and for `incident_update`.
- `playbook://analysis` — strategies for analytical work with the `*_stats`
  tools. Read before answering aggregate questions.
- `telemetry://datasources` — datasources available to `ask`/`ask_incident`.

## Which tool

- **Structured data** (counts, filters, specific fields) → the data tools;
  faster and cheaper than the agent tools. Start analytical questions at
  `incident_stats` / `alert_stats` / `escalation_stats`.
- **Your own analysis, shared to the channel** → `incident_message`.
- **Incident actions** (status, severity, roles, follow-ups) → `ask_incident`.
- **Org questions** (on-call, catalog, schedules, overrides) → `ask`.

`ask` and `ask_incident` return a `session_id`. Reuse it for related
follow-ups — asking a question, then accepting the resulting suggestion.
Omit it when switching topics.

## Mutations need the user's word

Posting to a channel, changing status or severity, creating incidents or
follow-ups, and assigning roles are all visible to the responder team.
Confirm the exact action with the user before each one, including when they
phrase it as already decided ("@incident change status to resolved"). Never
post your own findings or conclusions unprompted — put them in chat and wait.

## Expanding @incident requests

The backend agent cannot see your session: not the code you read, the fix you
pushed, or the PR you opened. Before dispatching, ask whether it needs that
context.

`@incident send an update` after 20 minutes of debugging is not
self-contained. Pass what you found and did:

> Send an update to say we found the trace image renderer was spending ~2
> minutes in a tight font glyph-loading loop, causing excessive memory
> pressure on the worker-ai pod. We've pushed a fix in commit ff35f9c that
> replaces the O(n^2) truncation loop with a single-pass truncateToWidth
> approach.

`@incident who is on-call for platform?` is self-contained — pass it through.

## Suggestions

Ask `ask_incident` to generate suggestions ("suggest an incident update").
Don't draft them locally; the backend agent has the context and the tools.

An `ask_incident` response may carry a `suggestion` with `id`,
`suggestion_type` and `content`. Always present it for approval before
acting — `AskUserQuestion` with accept / decline / modify, showing the parsed
content. For `suggestion_type: update`, map:

- `incident_status_name` → Status → {value}
- `severity_id` → Severity → {value}
- `name` → Name → {value}
- `message` → the message text

For `role`, `follow_up` and `escalation`, describe whichever content fields
are present.

Action the answer with a follow-up `ask_incident` on the same `session_id`:
`accept suggestion <id>`, `decline suggestion <id>`, or
`update suggestion <id>, change severity to SEV-3`. If the user moves on
without answering, drop it.

## Writing channel messages

You are writing as the user, so represent them, not yourself.

- **Keep their level of certainty.** "I believe X might be causing this"
  stays "looks like" or "appears to be", never "caused by". Prefer "the
  issue" or "the cause" over "root cause".
- **Match their framing.** They pushed a fix → say they pushed a fix. Still
  investigating → say that.
- **Stick to claims they made.** Describe what was observed and done.

`message` — 1–2 sentences, first person, conversational. `inline code` for
paths and values, **bold** sparingly for outcomes, `[text](url)` for links.
No emojis, headers or bullets. Point at the thread if there's detail.

`thread_message` — full technical detail, code blocks, logs. **Bold** for
section titles rather than headers, sentence case throughout, bullets and
code blocks to organise. Skip the thread for simple status confirmations.

`user` — the full name from `identity_get`, or "incident.io" if unknown.

**Confirmed fix:**

> Pushed a fix for the connection pool exhaustion — there was a missing index
> on `users.email`. Query time `5s → 50ms` (PR#5678). See thread for details.

**Still investigating:**

> Looked into the connection pool exhaustion — it looks like a missing index
> on `users.email` might be the cause. Still confirming. See thread for what
> I've found so far.

## Presenting data in chat

- Lead with `INC-123`, severity and status.
- Keep the hedging in AI investigation findings from
  `incident_show(include: ["investigation"])`.
- Workload from the `*_stats` tools is in minutes — present hours: "42 hours
  of responder time (8 overnight)".
- Lead with the biggest group (count, workload, change), not the full list.
- Connect alerts to incidents: "Alert X from Datadog triggered INC-123, which
  consumed 12 hours of responder time."

## Pull requests

With an incident pinned, footer PR bodies so incident.io links them back.
Get the ID from `incident_pin()`.

```
> *🤖 Generated with incident.io as part of [INC-12345](https://app.incident.io/~/incidents/12345)*
```

## When things fail

- **401/403** — auth lives in the macOS Keychain; ask the user to
  reauthenticate in the incident.io macOS app.
- **404** — check the incident reference exists.
- **Backend agent unreachable** — `ask`/`ask_incident` need connectivity; the
  data tools may still work.
