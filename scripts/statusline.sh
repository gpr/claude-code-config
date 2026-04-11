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
        (.worktree.original_branch // "")
    ] | map(tostring) | join("\u0000")'
)

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
    : "${current_dir:=unknown}"
    : "${project_dir:=$current_dir}"
    : "${model_name:=Unknown}"
fi

# Git info
if cd "$project_dir" 2>/dev/null; then
    git_branch=$(git -c core.useBuiltinFSMonitor=false branch --show-current 2>/dev/null)
    # Try origin first, then any remote, convert SSH to HTTPS, strip .git suffix
    raw_remote=$(git remote get-url origin 2>/dev/null)
    if [ -z "$raw_remote" ]; then
        raw_remote=$(git remote | head -1 | xargs -I{} git remote get-url {} 2>/dev/null)
    fi
    github_url=$(echo "$raw_remote" \
        | sed 's|git@github\.com:|https://github.com/|' \
        | sed 's|\.git$||')
    # Only keep the URL if it points to GitHub
    case "$github_url" in
        https://github.com/*) ;;
        *) github_url="" ;;
    esac
    github_project="${github_url#https://github.com/}"
fi

# Build folder display: project_dir, or current_dir/project_dir if different
proj_name=$(basename "$project_dir")
curr_name=$(basename "$current_dir")
if [ "$current_dir" = "$project_dir" ]; then
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

# LINE 1: [Model] folder | branch
line1=$(printf '\033[37m[%s]\033[0m' "$short_model")
if [ -n "$github_url" ]; then
    # OSC 8 hyperlink: \e]8;;URL\atext\e]8;;\a
    line1="$line1 $(printf '%b' "\033[94m🐙 \e]8;;${github_url}\a${github_project}\e]8;;\a 📁 \e]8;;vscode://file${project_dir}\a\033[2m${folder_name}\e]8;;\a\033[0m")"
else
    line1="$line1 $(printf '%b' "\033[94m📁 \e]8;;vscode://file${project_dir}\a${folder_name}\e]8;;\a\033[0m")"
fi
if [ -n "$git_branch" ]; then
    if [ -n "$worktree_branch" ]; then
        line1="$line1 $(printf '%b \033[96m🌿 %s \033[2m⤴ %s\033[0m' "$SEP" "$git_branch" "$worktree_branch")"
    else
        line1="$line1 $(printf '%b \033[96m🌿 %s\033[0m' "$SEP" "$git_branch")"
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