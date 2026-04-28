#!/bin/bash
CACHE_DIR="$HOME/.claude/cache"
CACHE_FILE="$CACHE_DIR/rate_limits.json"

[ -z "$ANTHROPIC_API_KEY" ] && exit 0

mkdir -p "$CACHE_DIR"

headers=$(curl -s -D - -o /dev/null --max-time 10 \
    "https://api.anthropic.com/v1/messages" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d '{"model":"claude-haiku-3-5-20241022","max_tokens":1,"messages":[{"role":"user","content":"."}]}' \
    2>/dev/null)
[ -z "$headers" ] && exit 1

tokens_limit=$(echo "$headers" | grep -i "^anthropic-ratelimit-tokens-limit:" | sed 's/.*: *//' | tr -d '\r\n')
tokens_remaining=$(echo "$headers" | grep -i "^anthropic-ratelimit-tokens-remaining:" | sed 's/.*: *//' | tr -d '\r\n')

case "$tokens_limit" in ''|*[!0-9]*) exit 1;; esac
case "$tokens_remaining" in ''|*[!0-9]*) exit 1;; esac

used_pct=$(awk "BEGIN { if ($tokens_limit > 0) printf \"%.0f\", (($tokens_limit - $tokens_remaining) * 100.0 / $tokens_limit); else print \"0\" }")
cached_at=$(date -u +%s)
tmp="${CACHE_FILE}.tmp.$$"
printf '{"tokens_limit":%s,"tokens_remaining":%s,"tokens_pct":%s,"cached_at":%s}\n' \
    "$tokens_limit" "$tokens_remaining" "$used_pct" "$cached_at" > "$tmp" && mv "$tmp" "$CACHE_FILE"
