#!/usr/bin/env bash
# ~/.claude/scripts/toolbelt-state.sh — hook handler for the iTerm2 toolbelt (SPEC.md §5.2, §4.3).
#
# One script for every state hook (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse,
# PermissionRequest, Stop, SessionEnd). Reads hook JSON on stdin, switches on
# .hook_event_name, and read-merge-writes the state-owned fields of
# ~/.claude-toolbelt/panes/<PANE_UUID>.json atomically.
#
# Hard requirements: never write to stdout (PreToolUse output is interpreted by Claude Code;
# for PermissionRequest, exit 0 + empty stdout means "no opinion" — confirmed against docs,
# see NOTES.md), always exit 0, complete well under the 1.5s SessionEnd budget and ideally
# under 50ms. Hooks run in parallel — last-write-wins on state fields, no lock (§4.2).

set -u
umask 077

STATE_DIR="$HOME/.claude-toolbelt"
PANES_DIR="$STATE_DIR/panes"
LOG_FILE="$STATE_DIR/log"

JQ=/opt/homebrew/bin/jq
[ -x "$JQ" ] || JQ=/usr/bin/jq

log() {
  [ -x "$JQ" ] || return 0
  printf '%s toolbelt-state %s\n' "$(date +%s)" "$1" >>"$LOG_FILE" 2>/dev/null
}

main() {
  local payload
  payload=$(cat)

  [ -x "$JQ" ] || return 0

  case "${ITERM_SESSION_ID:-}" in
    *:*) ;;
    *) return 0 ;;
  esac

  if [ -n "${TMUX:-}" ]; then
    log "TMUX set, skipping pane $ITERM_SESSION_ID"
    return 0
  fi

  # Pane UUID: bash parameter expansion (no fork) + tr only when actually needed — see the
  # matching comment in toolbelt-feed.sh for why (bash4-only ${var^^} isn't portable here).
  local pane_uuid_raw pane_uuid
  pane_uuid_raw=${ITERM_SESSION_ID#*:}
  [ -n "$pane_uuid_raw" ] || return 0
  case "$pane_uuid_raw" in
    *[a-z]*) pane_uuid=$(printf '%s' "$pane_uuid_raw" | tr 'a-z' 'A-Z') ;;
    *) pane_uuid=$pane_uuid_raw ;;
  esac
  [ -n "$pane_uuid" ] || return 0

  local pane_file
  pane_file="$PANES_DIR/$pane_uuid.json"

  # Single jq invocation does everything: reads .hook_event_name from the stdin payload, maps
  # it to a state (or decides "delete" for SessionEnd / "skip" for an unrecognized event), reads
  # the existing pane file via --slurpfile (no separate read process), and merges. Bash then
  # switches on the shape of jq's one-line output: a bare JSON string ("__DELETE__"/"__SKIP__")
  # for the two non-write cases, or the merged pane object itself for the write case — avoiding
  # a second jq call just to unwrap a tagged result.
  local existing_flag=(--argjson existing '[null]')
  [ -f "$pane_file" ] && existing_flag=(--slurpfile existing "$pane_file")

  local result
  result=$("$JQ" -c "${existing_flag[@]}" \
    --arg pane_uuid "$pane_uuid" \
    --arg raw "$ITERM_SESSION_ID" \
    --argjson now "$(date +%s)" \
    '
    (.hook_event_name // "") as $event
    | ({
        SessionStart: "idle", UserPromptSubmit: "working", PreToolUse: "working",
        PostToolUse: "working", PermissionRequest: "blocked", Stop: "idle"
      }[$event]) as $state
    # last_prompt (§4.2): set from this payload on UserPromptSubmit, whitespace-collapsed and
    # truncated so an unbounded prompt cannot bloat the pane file; cleared on SessionStart so a
    # pre-/clear prompt does not linger under the same pane_uuid; otherwise left untouched by the
    # ($existing[0] // {}) + {...} merge below, same pattern as toolbelt-feed.sh.
    | (if $event == "UserPromptSubmit" then
         ((.prompt // "") | gsub("\\s+"; " ") | .[0:200])
       elif $event == "SessionStart" then null
       else null
       end) as $last_prompt_update
    | if $event == "SessionEnd" then "__DELETE__"
      elif $state == null then "__SKIP__"
      else (($existing[0] // {}) + {
          state: $state, state_reason: $event, state_updated_at: $now,
          pane_uuid: $pane_uuid, iterm_session_id_raw: $raw
        } + (if $event == "UserPromptSubmit" or $event == "SessionStart"
             then { last_prompt: $last_prompt_update }
             else {}
             end))
      end
    ' <<<"$payload" 2>/dev/null)
  [ -n "$result" ] || return 0

  case "$result" in
    '"__DELETE__"') rm -f "$pane_file" ;;
    '"__SKIP__"') : ;;
    *)
      mkdir -p "$PANES_DIR" 2>/dev/null || return 0
      local tmp_file="$PANES_DIR/$pane_uuid.json.tmp.$$"
      printf '%s' "$result" >"$tmp_file" 2>/dev/null || { rm -f "$tmp_file"; return 0; }
      mv -f "$tmp_file" "$pane_file" 2>/dev/null || rm -f "$tmp_file"
      ;;
  esac
  return 0
}

main
exit 0
