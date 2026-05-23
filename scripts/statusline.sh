#!/bin/bash
# Two-line statusline with visual context progress bar
#
# Line 1: Model, folder, branch
# Line 2: Progress bar, context %, rate limits, cache hit %
#
# Context % uses Claude Code's pre-calculated remaining_percentage,
# which accounts for compaction reserves. 100% = compaction fires.

# Read stdin (Claude Code passes JSON data via stdin)
stdin_data=$(cat)

# Single jq call - extract all values at once
# Use null-delimited output to avoid IFS collapsing empty TSV fields
{
IFS= read -r -d '' current_dir
IFS= read -r -d '' project_dir
IFS= read -r -d '' model_name
IFS= read -r -d '' ctx_used
IFS= read -r -d '' cache_pct
IFS= read -r -d '' five_hour_pct
IFS= read -r -d '' seven_day_pct
IFS= read -r -d '' five_hour_resets
IFS= read -r -d '' worktree_branch
IFS= read -r -d '' worktree_original_cwd
IFS= read -r -d '' total_tokens
IFS= read -r -d '' total_cost
IFS= read -r -d '' effort_level
IFS= read -r -d '' thinking_enabled
IFS= read -r -d '' git_worktree_name
} < <(
    echo "$stdin_data" | jq -j '[
        .workspace.current_dir // "unknown",
        .workspace.project_dir // .workspace.current_dir // "unknown",
        .model.display_name // "Unknown",
        (try (
            if (.context_window.remaining_percentage // null) != null then
                100 - (.context_window.remaining_percentage | floor)
            elif (.context_window.context_window_size // 0) > 0 then
                (((.context_window.current_usage.input_tokens // 0) +
                  (.context_window.current_usage.cache_creation_input_tokens // 0) +
                  (.context_window.current_usage.cache_read_input_tokens // 0)) * 100 /
                 .context_window.context_window_size) | floor
            else "null" end
        ) catch "null"),
        (try (
            (.context_window.current_usage // {}) |
            if (.input_tokens // 0) + (.cache_read_input_tokens // 0) > 0 then
                ((.cache_read_input_tokens // 0) * 100 /
                 ((.input_tokens // 0) + (.cache_read_input_tokens // 0))) | floor
            else 0 end
        ) catch 0),
        (.rate_limits.five_hour.used_percentage // ""),
        (.rate_limits.seven_day.used_percentage // ""),
        (.rate_limits.five_hour.resets_at // ""),
        (.worktree.original_branch // ""),
        (.worktree.original_cwd // ""),
        (try (
            (.context_window.total_input_tokens // 0) +
            (.context_window.total_output_tokens // 0)
        ) catch 0),
        (.cost.total_cost_usd // ""),
        (.effort.level // ""),
        (if (.thinking? // null) != null and (.thinking | has("enabled")) then .thinking.enabled else "" end),
        (.workspace.git_worktree // "")
    ] | map(tostring) | join("\u0000")'
)

# Enterprise rate limit cache (API key users — skipped when claude.ai rate_limits present)
enterprise_tok_pct=""
_rl_cache="$HOME/.claude/cache/rate_limits.json"
if [ -f "$_rl_cache" ]; then
    read -r _cached_at _tok_pct < <(
        jq -r '[.cached_at // 0, .tokens_pct // ""] | @tsv' "$_rl_cache" 2>/dev/null
    )
    _now=$(date +%s)
    if [ "$(( _now - _cached_at ))" -le 300 ] 2>/dev/null; then
        enterprise_tok_pct="$_tok_pct"
    fi
    unset _cached_at _tok_pct _now
fi
unset _rl_cache

# Bash-level fallback: if jq crashed entirely, extract fields individually
if [ -z "$current_dir" ] && [ -z "$model_name" ]; then
    current_dir=$(echo "$stdin_data" | jq -r '.workspace.current_dir // .cwd // "unknown"' 2>/dev/null)
    project_dir=$(echo "$stdin_data" | jq -r '.workspace.project_dir // .workspace.current_dir // .cwd // "unknown"' 2>/dev/null)
    model_name=$(echo "$stdin_data" | jq -r '.model.display_name // "Unknown"' 2>/dev/null)
    ctx_used=""
    cache_pct="0"
    five_hour_pct=""
    seven_day_pct=""
    five_hour_resets=""
    worktree_branch=""
    worktree_original_cwd=""
    total_tokens="0"
    total_cost=""
    effort_level=""
    thinking_enabled=""
    git_worktree_name=""
    enterprise_tok_pct=""
    : "${current_dir:=unknown}"
    : "${project_dir:=$current_dir}"
    : "${model_name:=Unknown}"
fi

# Determine starting directory for git commands.
# Priority: Claude --worktree session original cwd > project_dir
if [ -n "$worktree_original_cwd" ]; then
    git_dir="$worktree_original_cwd"
else
    git_dir="$project_dir"
fi

# Git info — run from git_dir, then resolve the real repo root so that
# git linked worktrees (workspace.git_worktree set, .git is a file not a dir)
# work identically to normal checkouts.
git_branch=""
git_staged=0
git_modified=0
github_url=""
github_project=""
git_repo_root=""
if cd "$git_dir" 2>/dev/null; then
    # Resolve true repo root (handles both .git dirs and .git files used by worktrees)
    git_repo_root=$(git -c core.useBuiltinFSMonitor=false rev-parse --show-toplevel 2>/dev/null)
    git_branch=$(git -c core.useBuiltinFSMonitor=false branch --show-current 2>/dev/null)
    git_staged=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    git_modified=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    # Try origin first, then any remote, convert SSH to HTTPS, strip .git suffix
    raw_remote=$(git remote get-url origin 2>/dev/null)
    if [ -z "$raw_remote" ]; then
        raw_remote=$(git remote | head -1 | xargs -I{} git remote get-url {} 2>/dev/null)
    fi
    github_url=$(echo "$raw_remote" \
        | sed 's|[^@]*@github\.com:|https://github.com/|' \
        | sed 's|\.git$||')
    # Only keep the URL if it points to GitHub
    case "$github_url" in
        https://github.com/*) ;;
        *) github_url="" ;;
    esac
    github_project="${github_url#https://github.com/}"
fi

# In Claude --worktree sessions, show the worktree branch (from project_dir).
if [ -n "$worktree_original_cwd" ]; then
    git_branch=$(cd "$project_dir" 2>/dev/null && git -c core.useBuiltinFSMonitor=false branch --show-current 2>/dev/null)
fi

# Build folder display.
# Use the real repo root name when available (handles git worktrees where
# project_dir is a worktree subdirectory like .claude/worktrees/<name>).
# Fall back chain: git_repo_root > worktree_original_cwd > project_dir
if [ -n "$worktree_original_cwd" ]; then
    proj_name=$(basename "$worktree_original_cwd")
elif [ -n "$git_repo_root" ]; then
    proj_name=$(basename "$git_repo_root")
else
    proj_name=$(basename "$project_dir")
fi
curr_name=$(basename "$current_dir")
if [ "$current_dir" = "$project_dir" ] || [ "$current_dir" = "$git_repo_root" ]; then
    folder_name="$proj_name"
else
    folder_name="$curr_name/$proj_name"
fi

# Generate visual progress bar for context usage
progress_bar=""
bar_width=12

if [ -n "$ctx_used" ] && [ "$ctx_used" != "null" ]; then
    filled=$((ctx_used * bar_width / 100))
    empty=$((bar_width - filled))

    if [ "$ctx_used" -lt 50 ]; then
        bar_color='\033[32m'  # Green (0-49%)
    elif [ "$ctx_used" -lt 80 ]; then
        bar_color='\033[33m'  # Yellow (50-79%)
    else
        bar_color='\033[31m'  # Red (80-100%)
    fi

    progress_bar="${bar_color}"
    for ((i=0; i<filled; i++)); do
        progress_bar="${progress_bar}█"
    done
    progress_bar="${progress_bar}\033[2m"
    for ((i=0; i<empty; i++)); do
        progress_bar="${progress_bar}⣿"
    done
    progress_bar="${progress_bar}\033[0m"

    ctx_pct="${ctx_used}%"
else
    ctx_pct=""
fi

# Separator
SEP='\033[2m│\033[0m'

# Get short model name (e.g., "Sonnet 4.6" instead of "Claude Sonnet 4.6")
short_model=$(echo "$model_name" | sed -E 's/Claude [0-9.]+ //; s/^Claude //')

# Thinking indicator
case "$thinking_enabled" in
    true)  thinking_icon="🧠" ;;
    false) thinking_icon="💤" ;;
    *)     thinking_icon="" ;;
esac

# Effort badge (only when present)
effort_badge=""
if [ -n "$effort_level" ]; then
    effort_cap="$(echo "$effort_level" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
    case "$effort_level" in
        low)    effort_glyph="○" ;;
        medium) effort_glyph="◐" ;;
        high)   effort_glyph="●" ;;
        xhigh)  effort_glyph="◉" ;;
        ultra)  effort_glyph="◎" ;;
        *)      effort_glyph="◌" ;;
    esac
    effort_badge=$(printf ' %s %s' "$effort_glyph" "$effort_cap")
fi

# LINE 1: [Model] [thinking] [effort] folder | branch
line1=$(printf '\033[37m[%s]\033[0m' "$short_model")
if [ -n "$thinking_icon" ]; then
    line1="$line1 $thinking_icon"
fi
if [ -n "$effort_badge" ]; then
    line1="${line1}$(printf '%b' "$effort_badge")"
fi
if [ -n "$github_url" ]; then
    # OSC 8 hyperlink: \e]8;;URL\atext\e]8;;\a
    line1="$line1 $(printf '%b' "\033[94m🐙 \e]8;;${github_url}\a${github_project}\e]8;;\a 📁 \e]8;;vscode://file${project_dir}\a\033[2m${folder_name}\e]8;;\a\033[0m")"
else
    line1="$line1 $(printf '%b' "\033[94m📁 \e]8;;vscode://file${project_dir}\a${folder_name}\e]8;;\a\033[0m")"
fi
if [ -n "$git_branch" ]; then
    git_diff_stats=""
    [ "$git_staged" -gt 0 ] && git_diff_stats="$(printf '\033[32m+%s\033[0m' "$git_staged")"
    [ "$git_modified" -gt 0 ] && git_diff_stats="${git_diff_stats}$(printf '\033[33m~%s\033[0m' "$git_modified")"
    if [ -n "$worktree_branch" ]; then
        line1="$line1 $(printf '%b \033[96m🌿 %s\033[0m%b \033[2m⤴ %s\033[0m' "$SEP" "$git_branch" "${git_diff_stats:+ $git_diff_stats}" "$worktree_branch")"
    else
        line1="$line1 $(printf '%b \033[96m🌿 %s\033[0m%b' "$SEP" "$git_branch" "${git_diff_stats:+ $git_diff_stats}")"
    fi
fi

# LINE 2: Progress bar | Context % | rate limits | cache hit %
line2=""
if [ -n "$progress_bar" ]; then
    line2=$(printf '%b' "$progress_bar")
fi
if [ -n "$ctx_pct" ]; then
    if [ -n "$line2" ]; then
        line2="$line2 $(printf '\033[37m%s\033[0m' "$ctx_pct")"
    else
        line2=$(printf '\033[37m%s\033[0m' "$ctx_pct")
    fi
fi
# Total cumulative token consumption
if [ -n "$total_tokens" ] && [ "$total_tokens" != "0" ] 2>/dev/null; then
    if [ "$total_tokens" -ge 1000000 ] 2>/dev/null; then
        tok_display=$(awk "BEGIN {printf \"%.1fM\", $total_tokens/1000000}")
    elif [ "$total_tokens" -ge 1000 ] 2>/dev/null; then
        tok_display=$(awk "BEGIN {printf \"%.0fk\", $total_tokens/1000}")
    else
        tok_display="${total_tokens}"
    fi
    if [ -n "$line2" ]; then
        line2="$line2 $(printf '%b \033[2m%s tok\033[0m' "$SEP" "$tok_display")"
    else
        line2=$(printf '\033[2m%s tok\033[0m' "$tok_display")
    fi
fi
# Session cost (USD)
if [ -n "$total_cost" ]; then
    cost_display=$(awk "BEGIN {printf \"\$%.2f\", $total_cost}")
    if [ -n "$line2" ]; then
        line2="$line2 $(printf '%b \033[33m💰 %s\033[0m' "$SEP" "$cost_display")"
    else
        line2=$(printf '\033[33m💰 %s\033[0m' "$cost_display")
    fi
fi
# Rate limits (only shown when present, i.e., Claude.ai subscribers)
if [ -n "$five_hour_pct" ]; then
    five_int=$(printf '%.0f' "$five_hour_pct")
    if [ -n "$line2" ]; then
        line2="$line2 $(printf '%b \033[35m5h:%s%%\033[0m' "$SEP" "$five_int")"
    else
        line2=$(printf '\033[35m5h:%s%%\033[0m' "$five_int")
    fi
fi
if [ -n "$seven_day_pct" ]; then
    week_int=$(printf '%.0f' "$seven_day_pct")
    if [ -n "$line2" ]; then
        line2="$line2 $(printf '\033[35m7d:%s%%\033[0m' "$week_int")"
    else
        line2=$(printf '\033[35m7d:%s%%\033[0m' "$week_int")
    fi
fi
# Enterprise token rate limit (only when native rate_limits absent)
if [ -z "$five_hour_pct" ] && [ -n "$enterprise_tok_pct" ]; then
    tok_int=$(printf '%.0f' "$enterprise_tok_pct")
    if [ -n "$line2" ]; then
        line2="$line2 $(printf '%b \033[35mtok:%s%%\033[0m' "$SEP" "$tok_int")"
    else
        line2=$(printf '\033[35mtok:%s%%\033[0m' "$tok_int")
    fi
fi
# Format 5-hour reset time (resets_at is Unix epoch seconds)
reset_display=""
if [ -n "$five_hour_resets" ]; then
    reset_display=$(date -r "$five_hour_resets" "+%l%p %Z" 2>/dev/null \
        | sed 's/AM/am/;s/PM/pm/' | sed 's/^ //')
fi
if [ -n "$reset_display" ]; then
    line2="$line2 $(printf '\033[2m(%s)\033[0m' "$reset_display")"
fi
if [ "$cache_pct" -gt 0 ] 2>/dev/null; then
    if [ -n "$line2" ]; then
        line2="$line2 $(printf '%b \033[2m↻%s%%\033[0m' "$SEP" "$cache_pct")"
    else
        line2=$(printf '\033[2m↻%s%%\033[0m' "$cache_pct")
    fi
fi

# LINE 3: Added directories with vscode:// links (only when present)
line3=""
while IFS= read -r dir_path; do
    [ -z "$dir_path" ] && continue
    dir_name="${dir_path##*/}"
    [ -n "$line3" ] && line3="$line3 "
    line3="${line3}$(printf '%b' "\033[94m📁 \e]8;;vscode://file${dir_path}\a${dir_name}\e]8;;\a\033[0m")"
done < <(echo "$stdin_data" | jq -r '.workspace.added_dirs // [] | .[]')

if [ -n "$line3" ]; then
    printf '%b\n\n%b\n\n%b' "$line1" "$line2" "$line3"
else
    printf '%b\n\n%b' "$line1" "$line2"
fi
