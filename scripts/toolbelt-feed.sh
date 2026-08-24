#!/usr/bin/env bash
# ~/.claude/scripts/toolbelt-feed.sh — statusLine feed for the iTerm2 toolbelt (SPEC.md §5.1).
#
# Invoked (via the statuslines.sh dispatcher) by every Claude Code session independently,
# with the session JSON on stdin. Writes/refreshes the feed-owned fields of
# ~/.claude-toolbelt/panes/<PANE_UUID>.json and always exits 0, printing nothing.
#
# Deviation from SPEC.md §5.1 ("always print exactly one line to stdout"): this script prints
# nothing. It is invoked by ~/.claude/scripts/statuslines.sh, which passes through the real
# status line's own output. See NOTES.md.
#
# Hard requirements per spec: no network calls, no git calls, no subshell fan-out. Runs every
# 5s per session across N sessions (refreshInterval).

set -u
umask 077

STATE_DIR="$HOME/.claude-toolbelt"
PANES_DIR="$STATE_DIR/panes"
LOG_FILE="$STATE_DIR/log"

# Resolve jq the same way ~/.claude/scripts/statusline.sh does: the mise shim fails when a
# project's mise.toml isn't trusted, so bypass PATH entirely.
JQ=/opt/homebrew/bin/jq
[ -x "$JQ" ] || JQ=/usr/bin/jq

log() {
  # $1=message. Never logs cwd/paths unless CLAUDE_TOOLBELT_DEBUG=1 (§6.3) — callers must not
  # pass path-bearing messages unconditionally.
  [ -x "$JQ" ] || return 0
  printf '%s toolbelt-feed %s\n' "$(date +%s)" "$1" >>"$LOG_FILE" 2>/dev/null
}

main() {
  local payload
  payload=$(cat)

  [ -x "$JQ" ] || return 0

  # Guard: no ITERM_SESSION_ID, or no ':' in it => write nothing (§5.1 step 2).
  case "${ITERM_SESSION_ID:-}" in
    *:*) ;;
    *) return 0 ;;
  esac

  # tmux changes ITERM_SESSION_ID semantics; out of scope for v1 (§8) — warn once per invocation
  # and write nothing rather than a wrong file.
  if [ -n "${TMUX:-}" ]; then
    log "TMUX set, skipping pane $ITERM_SESSION_ID"
    return 0
  fi

  # Pane UUID: strip up to the first ':' via pure bash parameter expansion (no fork), then
  # uppercase with tr. Deliberately not ${var^^} (bash4+) — statuslines.sh invokes this script
  # as `bash <path>`, and which bash that resolves to on PATH isn't guaranteed to be 4+ (the
  # system /bin/bash on macOS is 3.2). tr is one extra fork but portable across bash versions.
  local pane_uuid_raw pane_uuid
  pane_uuid_raw=${ITERM_SESSION_ID#*:}
  [ -n "$pane_uuid_raw" ] || return 0
  # iTerm2's UUID is already uppercase in practice; skip the tr fork on that common path and
  # only pay for it when a lowercase char is actually present (glob match, no fork either way).
  case "$pane_uuid_raw" in
    *[a-z]*) pane_uuid=$(printf '%s' "$pane_uuid_raw" | tr 'a-z' 'A-Z') ;;
    *) pane_uuid=$pane_uuid_raw ;;
  esac
  [ -n "$pane_uuid" ] || return 0

  [ -d "$PANES_DIR" ] || mkdir -p "$PANES_DIR" 2>/dev/null || return 0

  local pane_file tmp_file
  pane_file="$PANES_DIR/$pane_uuid.json"
  tmp_file="$PANES_DIR/$pane_uuid.json.tmp.$$"

  # Single jq invocation: read-merge the existing pane file (via --slurpfile, parsed by jq
  # itself — no separate read process) against the feed-owned fields extracted from stdin, and
  # write the result. Fusing read + extract + merge into one process is the dominant cost lever.
  local existing_flag=(--argjson existing '[null]')
  [ -f "$pane_file" ] && existing_flag=(--slurpfile existing "$pane_file")

  "$JQ" -c "${existing_flag[@]}" \
    --arg pane_uuid "$pane_uuid" \
    --arg raw "$ITERM_SESSION_ID" \
    --argjson now "$(date +%s)" \
    '(($existing[0]) // {}) + {
        claude_session_id: (.session_id // null),
        session_name: (.session_name // null),
        model: (.model.display_name // null),
        model_id: (.model.id // null),
        cost_usd: (.cost.total_cost_usd // null),
        context_used_pct: (.context_window.used_percentage // null),
        context_window_size: (.context_window.context_window_size // null),
        input_tokens: (.context_window.total_input_tokens // null),
        output_tokens: (.context_window.total_output_tokens // null),
        cwd: (.cwd // null),
        project_dir: (.workspace.project_dir // null),
        cc_version: (.version // null),
        pane_uuid: $pane_uuid,
        iterm_session_id_raw: $raw,
        feed_updated_at: $now
      }' \
    <<<"$payload" >"$tmp_file" 2>/dev/null || { rm -f "$tmp_file"; return 0; }

  mv -f "$tmp_file" "$pane_file" 2>/dev/null || rm -f "$tmp_file"
  return 0
}

main
exit 0
