#!/usr/bin/env bash
# Report per-agent (lead + each teammate) token consumption and active time
# for a Claude Code session, plus the team total.
#
# Usage:
#   team-usage.sh [session-id] [project-dir]
#
# Defaults:
#   session-id  -> $CLAUDE_CODE_SESSION_ID (the current session)
#   project-dir -> derived from $PWD using Claude Code's path-encoding scheme
#
# Data model — two distinct teammate sources, both rolled up:
#   lead        = <project-dir>/<session-id>.jsonl
#   subagent    = <project-dir>/<session-id>/subagents/agent-<id>.jsonl
#                 (Agent-tool spawns; identity from agent-<id>.meta.json .agentType)
#   team member = <project-dir>/<other-session>.jsonl   (TeamCreate teammates)
#                 A TeamCreate teammate writes its OWN top-level session
#                 transcript, NOT a file under the lead's subagents/ dir.
#                 Link: every line of both the lead and its teammates carries
#                 a .teamName; a teammate transcript also carries .agentName
#                 (the human label, e.g. "tdd-implementer"); the lead does not.
#                 So: teammates = sibling *.jsonl whose .teamName == the lead's
#                 .teamName and which have an .agentName.
set -euo pipefail

SID="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
PD="${2:-}"

if [ -z "$SID" ]; then
  echo "error: no session id (pass one or set CLAUDE_CODE_SESSION_ID)" >&2
  exit 1
fi

# Encode cwd the way Claude Code does: replace '/' and '.' with '-'.
# Claude Code keys the project dir by the CANONICAL cwd, so resolve symlinks
# first (e.g. /Users/x -> /opt/x). Try the resolved path, then fall back to
# the raw $PWD, so it works with or without a symlinked working dir.
encode() { printf '%s' "$1" | sed 's/[/.]/-/g'; }
if [ -z "$PD" ]; then
  real=$(realpath "$PWD" 2>/dev/null || printf '%s' "$PWD")
  PD="$HOME/.claude/projects/$(encode "$real")"
  if [ ! -e "$PD/$SID.jsonl" ] && [ "$real" != "$PWD" ]; then
    alt="$HOME/.claude/projects/$(encode "$PWD")"
    [ -e "$alt/$SID.jsonl" ] && PD="$alt"
  fi
fi

LEAD="$PD/$SID.jsonl"
SUBS="$PD/$SID/subagents"

if [ ! -e "$LEAD" ]; then
  echo "error: lead transcript not found: $LEAD" >&2
  echo "hint: pass the project dir explicitly as the 2nd argument" >&2
  exit 1
fi

# Aggregate one transcript (stdin) into a single JSON object.
# args: $1 = display name, $2 = kind (lead | team-member | subagent)
agg() {
  jq -s --arg name "$1" --arg kind "$2" '
    # Parse an ISO timestamp to epoch seconds, tolerating an optional
    # fractional-second part and/or an existing trailing Z (jq fromdateiso8601
    # wants exactly one trailing Z and no fraction).
    def iso(t): (t | sub("\\.[0-9]+";"") | sub("Z$";"") + "Z" | fromdateiso8601);
    map(select(.message.usage)) | {
    name:$name,
    kind:$kind,
    msgs:length,
    input:(map(.message.usage.input_tokens//0)|add // 0),
    output:(map(.message.usage.output_tokens//0)|add // 0),
    cache_read:(map(.message.usage.cache_read_input_tokens//0)|add // 0),
    cache_creation:(map(.message.usage.cache_creation_input_tokens//0)|add // 0),
    first_ts:(if length>0 then (map(.timestamp)|min) else null end),
    last_ts:(if length>0 then (map(.timestamp)|max) else null end),
    span_sec:(if length>0
      then ((map(iso(.timestamp))|max)-(map(iso(.timestamp))|min))
      else 0 end)
  }'
}

# The lead's team (if any): first .teamName seen in the lead transcript.
# Select inside jq (not via `head`) so jq never gets SIGPIPE from an early-
# closing pipe, which under `set -o pipefail`/`set -e` would abort the script.
TEAM=$(jq -rn 'first(inputs | .teamName // empty) // empty' "$LEAD" 2>/dev/null)

{
  agg "lead" "lead" < "$LEAD"

  # Source 1: Agent-tool subagents — files under the lead's subagents/ dir.
  if [ -d "$SUBS" ]; then
    for aj in "$SUBS"/agent-*.jsonl; do
      [ -e "$aj" ] || continue
      id=$(basename "$aj" .jsonl)
      meta="$SUBS/$id.meta.json"
      label="$id"
      if [ -e "$meta" ]; then
        at=$(jq -r '.agentType // empty' "$meta")
        [ -n "$at" ] && label="$at"
      fi
      agg "$label" "subagent" < "$aj"
    done
  fi

  # Source 2: TeamCreate teammates — sibling top-level *.jsonl transcripts in
  # the same project whose .teamName matches the lead's and which carry an
  # .agentName. Only scanned when the lead actually belongs to a team.
  #
  # Caveat: linkage is by .teamName (a string), not a per-run team id. If the
  # SAME team name is reused across separate runs, this attributes every
  # matching teammate transcript to each such lead. The authoritative per-run
  # member list lived in ~/.claude/teams/<team>/config.json, which is removed
  # on team cleanup — so once a team is torn down, name is the only link left.
  if [ -n "$TEAM" ]; then
    for tj in "$PD"/*.jsonl; do
      [ -e "$tj" ] || continue
      [ "$tj" = "$LEAD" ] && continue
      # Cheap pre-filter: skip files that never mention the team name.
      grep -qF -- "$TEAM" "$tj" 2>/dev/null || continue
      # Precise confirm: belongs to this team AND is a named teammate.
      # first(...) inside jq avoids the head/SIGPIPE pitfall (see TEAM above).
      label=$(jq -rn --arg t "$TEAM" '
        first(inputs | select(.teamName==$t and .agentName) | .agentName) // empty' \
        "$tj" 2>/dev/null)
      [ -n "$label" ] || continue
      agg "$label" "team-member" < "$tj"
    done
  fi
} | jq -s '
  def fmt($x): ([$x,0]|max) as $s
    | ($s/3600|floor|tostring)+"h"+((($s%3600)/60)|floor|tostring)+"m"+(($s%60)|tostring)+"s";
  def iso(t): (t | sub("\\.[0-9]+";"") | sub("Z$";"") + "Z" | fromdateiso8601);
  . as $rows
  | ($rows|map(.input+.output+.cache_read+.cache_creation)|add) as $ttok
  | ($rows|map(.span_sec)|add) as $busy
  | ([$rows[]|.first_ts|select(.!=null)]|min) as $wall_start
  | ([$rows[]|.last_ts|select(.!=null)]|max) as $wall_end
  | ($rows|map(.msgs)|add) as $tmsgs
  | {
      members: ($rows | map({
        name, kind, msgs,
        total_tokens:(.input+.output+.cache_read+.cache_creation),
        input, output, cache_read, cache_creation,
        active_time: fmt(.span_sec)
      })),
      team_total: {
        members: ($rows|length),
        messages: $tmsgs,
        tokens: $ttok,
        busy_time_sum: fmt($busy),
        wall_clock: (if $wall_start and $wall_end
          then fmt(iso($wall_end) - iso($wall_start))
          else "0h0m0s" end)
      }
    }'
