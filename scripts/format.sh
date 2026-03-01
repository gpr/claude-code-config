#!/bin/bash

# PostToolUse hook script for formatting files after Write|Edit|MultiEdit operations
# This script auto-detects project formatters and applies them to modified files

set -euo pipefail

# Function to log messages
log() {
    echo "[format.sh] $1" >&2
}

# Function to find project root by looking for common project files
find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/package.json" ]] || [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/Cargo.toml" ]] || [[ -f "$dir/go.mod" ]] || [[ -f "$dir/.git/config" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "$PWD"
}

# Cache command availability to avoid repeated forks (compatible with bash 3.x)
_cmd_cache=""
command_exists() {
    local cmd="$1"
    case "$_cmd_cache" in
        *"|${cmd}=1|"*) return 0 ;;
        *"|${cmd}=0|"*) return 1 ;;
    esac
    if command -v "$cmd" >/dev/null 2>&1; then
        _cmd_cache="${_cmd_cache}|${cmd}=1|"
        return 0
    else
        _cmd_cache="${_cmd_cache}|${cmd}=0|"
        return 1
    fi
}

# Function to format a single file based on its extension and available tools
format_file() {
    local file="$1"
    local project_root="$2"
    local formatted=false

    if [[ ! -f "$file" ]]; then
        log "File not found: $file"
        return 0
    fi

    log "Formatting: $file"

    # Get file extension
    local ext="${file##*.}"

    case "$ext" in
        js|jsx|ts|tsx|mjs|cjs)
            # JavaScript/TypeScript formatting
            if [[ -f "$project_root/package.json" ]]; then
                if [[ -x "$project_root/node_modules/.bin/prettier" ]]; then
                    "$project_root/node_modules/.bin/prettier" --write "$file" && formatted=true
                elif [[ -x "$project_root/node_modules/.bin/eslint" ]]; then
                    "$project_root/node_modules/.bin/eslint" --fix "$file" 2>/dev/null && formatted=true
                elif [[ -f "$project_root/.prettierrc" || -f "$project_root/.prettierrc.json" || -f "$project_root/.prettierrc.js" ]] && command_exists prettier; then
                    prettier --write "$file" && formatted=true
                fi
            elif command_exists prettier; then
                prettier --write "$file" && formatted=true
            fi
            ;;
        py)
            # Python formatting
            if [[ -f "$project_root/pyproject.toml" ]] && command_exists ruff; then
                ruff format "$file" 2>/dev/null && formatted=true
            elif command_exists black; then
                black "$file" 2>/dev/null && formatted=true
            elif command_exists autopep8; then
                autopep8 --in-place "$file" && formatted=true
            fi
            # Also try import sorting
            if command_exists isort; then
                isort "$file" 2>/dev/null
            elif command_exists ruff; then
                ruff check --select I --fix "$file" 2>/dev/null
            fi
            ;;
        rs)
            # Rust formatting — format single file, not the whole project
            if command_exists rustfmt; then
                rustfmt "$file" 2>/dev/null && formatted=true
            fi
            ;;
        go)
            # Go formatting
            if command_exists gofmt; then
                gofmt -w "$file" && formatted=true
            fi
            if command_exists goimports; then
                goimports -w "$file"
            fi
            ;;
        java)
            # Java formatting
            if [[ -f "$project_root/pom.xml" ]] && command_exists mvn; then
                (cd "$project_root" && mvn fmt:format 2>/dev/null) && formatted=true
            elif command_exists google-java-format; then
                google-java-format --replace "$file" && formatted=true
            fi
            ;;
        rb)
            # Ruby formatting
            if [[ -f "$project_root/Gemfile" ]] && command_exists bundle; then
                (cd "$project_root" && bundle exec rubocop -a "$file" 2>/dev/null) && formatted=true
            elif command_exists rubocop; then
                rubocop -a "$file" 2>/dev/null && formatted=true
            elif command_exists standardrb; then
                standardrb --fix "$file" 2>/dev/null && formatted=true
            fi
            ;;
        php)
            # PHP formatting
            if command_exists php-cs-fixer; then
                php-cs-fixer fix "$file" 2>/dev/null && formatted=true
            fi
            ;;
        c|cpp|cc|cxx|h|hpp)
            # C/C++ formatting
            if command_exists clang-format; then
                clang-format -i "$file" && formatted=true
            fi
            ;;
        cs)
            # C# formatting
            if command_exists dotnet; then
                dotnet format --include "$file" 2>/dev/null && formatted=true
            fi
            ;;
        json)
            # JSON formatting
            if command_exists jq; then
                local temp_file
                temp_file="$file.tmp.$$"
                if jq '.' "$file" > "$temp_file" 2>/dev/null; then
                    mv "$temp_file" "$file" && formatted=true
                else
                    rm -f "$temp_file"
                fi
            elif command_exists prettier; then
                prettier --write "$file" && formatted=true
            fi
            ;;
        yaml|yml)
            # YAML formatting
            if command_exists prettier; then
                prettier --write "$file" && formatted=true
            fi
            ;;
        md|markdown)
            # Markdown formatting
            if [[ -x "$project_root/node_modules/.bin/prettier" ]]; then
                "$project_root/node_modules/.bin/prettier" --write "$file" 2>/dev/null && formatted=true
            elif command_exists prettier; then
                prettier --write "$file" && formatted=true
            fi
            ;;
        html|css|scss|sass|less)
            # Web formatting
            if command_exists prettier; then
                prettier --write "$file" && formatted=true
            fi
            ;;
    esac

    if [[ "$formatted" == true ]]; then
        log "Formatted: $file"
    else
        log "No formatter found for: $file"
    fi
}

# Main execution
main() {
    # Find project root
    local project_root
    project_root=$(find_project_root)
    log "Project root: $project_root"

    # If files are provided as arguments, format those
    if [[ $# -gt 0 ]]; then
        for file in "$@"; do
            # Convert relative paths to absolute
            if [[ "$file" != /* ]]; then
                file="$PWD/$file"
            fi
            format_file "$file" "$project_root"
        done
    else
        # If no arguments, try to format recently modified files
        log "No files specified, checking for recently modified files..."

        if command_exists git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            local files
            files=$(git diff --name-only HEAD 2>/dev/null | head -20) || true
            local f
            for f in $files; do
                [[ -n "$f" ]] && format_file "$f" "$project_root"
            done
        fi
    fi
}

# Execute main function with all arguments
main "$@"
