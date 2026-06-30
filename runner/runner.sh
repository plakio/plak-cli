#!/usr/bin/env bash

set -euo pipefail

runner_usage() {
    cat <<'EOF'
Plak Runner

Usage:
  runner <command> [arguments] [--flags]

Commands:
  backup      Create a WordPress backup. Not implemented yet.
  migrate     Restore a WordPress backup. Not implemented yet.
  help        Show this help text.
EOF
}

runner_main() {
    local command="${1:-help}"
    if [ "$#" -gt 0 ]; then
        shift
    fi

    case "$command" in
        backup)
            runner_backup "$@"
            ;;
        migrate)
            runner_migrate "$@"
            ;;
        help|--help|-h)
            runner_usage
            ;;
        *)
            runner_error "Unknown command: $command"
            runner_usage >&2
            exit 1
            ;;
    esac
}


# --- Shared Helpers ---
# Source: shared/archive
runner_require_command() {
    local command="$1"
    if ! command -v "$command" >/dev/null 2>&1; then
        runner_error "Required command not found: $command"
        return 1
    fi
}

# Source: shared/logging
runner_error() {
    echo "Error: $*" >&2
}

runner_info() {
    echo "$*"
}

# Source: shared/private-dir
runner_private_dir() {
    local current_dir
    current_dir=$(pwd)

    if [ -d "${current_dir}/_wpeprivate" ]; then
        echo "${current_dir}/_wpeprivate"
        return 0
    fi

    if [ -d "../private" ]; then
        (cd ../private && pwd)
        return 0
    fi

    if mkdir -p "../private" 2>/dev/null; then
        (cd ../private && pwd)
        return 0
    fi

    if [ -d "../tmp" ]; then
        (cd ../tmp && pwd)
        return 0
    fi

    if mkdir -p "$HOME/private" 2>/dev/null; then
        echo "$HOME/private"
        return 0
    fi

    runner_error "Could not find or create a writable private directory."
    return 1
}

# Source: shared/wp-cli
runner_wp_cli() {
    if command -v wp >/dev/null 2>&1; then
        echo "wp"
        return 0
    fi

    local candidate
    for candidate in "/usr/local/bin/wp" "$HOME/bin/wp" "/opt/wp-cli/wp"; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    runner_error "WP-CLI is required but was not found."
    return 1
}

# --- Command Functions ---
# Source: commands/backup
runner_backup() {
    runner_error "The backup command is not implemented yet."
    return 2
}

# Source: commands/migrate
runner_migrate() {
    runner_error "The migrate command is not implemented yet."
    return 2
}

# Pass all script arguments to the main function.
runner_main "$@"
