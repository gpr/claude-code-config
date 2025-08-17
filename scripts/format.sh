#!/bin/bash

# PostToolUse hook script for formatting files after Write|Edit|MultiEdit operations
# This script auto-detects project formatters and applies them to modified files

set -euo pipefail

# Function to log messages
log() {
    echo "[format.sh] $1" >&2
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
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
    local basename_file="$(basename "$file")"

    case "$ext" in
        js|jsx|ts|tsx|mjs|cjs)
            # JavaScript/TypeScript formatting
            if [[ -f "$project_root/package.json" ]]; then
                cd "$project_root"
                if command_exists prettier && [[ -f "node_modules/.bin/prettier" || $(npm list --depth=0 prettier 2>/dev/null) ]]; then
                    npx prettier --write "$file" && formatted=true
                elif command_exists eslint && [[ -f "node_modules/.bin/eslint" || $(npm list --depth=0 eslint 2>/dev/null) ]]; then
                    npx eslint --fix "$file" 2>/dev/null && formatted=true
                elif [[ -f ".prettierrc" || -f ".prettierrc.json" || -f ".prettierrc.js" ]] && command_exists prettier; then
                    prettier --write "$file" && formatted=true
                fi
            elif command_exists prettier; then
                prettier --write "$file" && formatted=true
            fi
            ;;
        py)
            # Python formatting
            cd "$project_root"
            if [[ -f "pyproject.toml" ]] && command_exists ruff; then
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
            # Rust formatting
            if [[ -f "$project_root/Cargo.toml" ]]; then
                cd "$project_root"
                if command_exists cargo; then
                    cargo fmt --all 2>/dev/null && formatted=true
                fi
            elif command_exists rustfmt; then
                rustfmt "$file" && formatted=true
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
                cd "$project_root"
                mvn fmt:format 2>/dev/null && formatted=true
            elif command_exists google-java-format; then
                google-java-format --replace "$file" && formatted=true
            fi
            ;;
        rb)
            # Ruby formatting
            if command_exists rubocop; then
                rubocop -a "$file" 2>/dev/null && formatted=true
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
                local temp_file=$(mktemp)
                jq '.' "$file" > "$temp_file" && mv "$temp_file" "$file" && formatted=true
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
            if command_exists prettier; then
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
        # This is useful when the hook doesn't pass specific files
        log "No files specified, checking for recently modified files..."
        
        # Look for files modified in the last minute
        local recent_files
        if command_exists git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            git diff --name-only HEAD~1 HEAD 2>/dev/null | head -20 | while read -r file; do
                [[ -n "$file" ]] && format_file "$file" "$project_root"
            done
        fi
    fi
}

# Execute main function with all arguments
main "$@"