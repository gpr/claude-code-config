#!/usr/bin/env bash
# ~/.claude/scripts/statuslines.sh — dispatcher.
#
# Claude Code allows exactly one statusLine command. This repo's toolbelt feed and the user's
# pre-existing ~/.claude/scripts/statusline.sh both need to run on every statusLine trigger, so
# this dispatcher fans stdin out to both and prints only the real status line's output.
#
# Order matters: toolbelt-feed.sh runs FIRST, discarding its own stdout/stderr. Claude Code
# cancels an in-flight statusLine script whenever a new update triggers before it finishes; if
# the (slow, git-touching) statusline.sh ran first, a cancellation mid-run could lose the pane
# write. Feed-first means the write already landed by the time the slow half starts.
#
# Always exits 0. A missing/broken toolbelt-feed.sh must never blank the real status line.

set -u

payload=$(cat)

REAL_STATUSLINE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/statusline.sh"

if [ -f "$REAL_STATUSLINE" ]; then
  printf '%s' "$payload" | bash "$REAL_STATUSLINE"
fi

[ -d "$HOME/.cache/claude" ] || mkdir -p "$HOME/.cache/claude"
printf '%s' "$payload" | jq > $HOME/.cache/claude/statusline.json 2>/dev/null

exit 0
