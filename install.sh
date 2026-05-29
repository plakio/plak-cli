#!/usr/bin/env bash

set -euo pipefail

DEV_MODE=false
for arg in "$@"; do
    case "$arg" in
        --dev) DEV_MODE=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

os_name=$(uname -s)
install_dir="${PLAK_INSTALL_DIR:-/usr/local/bin}"

if [ -z "${PLAK_INSTALL_DIR:-}" ] && [ "$os_name" = "Darwin" ]; then
    if [ "$(uname -m)" = "arm64" ]; then
        install_dir="/opt/homebrew/bin"
    fi
fi

destination="$install_dir/plak"
download_url="${PLAK_INSTALL_URL:-https://raw.githubusercontent.com/plakio/plak-cli/main/plak.sh}"

if [ "$DEV_MODE" = true ]; then
    script_path="${BASH_SOURCE[0]:-}"
    if [ -z "$script_path" ]; then
        echo "--dev requires running ./install.sh --dev from a local checkout." >&2
        exit 1
    fi

    script_dir=$(cd "$(dirname "$script_path")" && pwd)
    source_script="$script_dir/plak.sh"

    if [ ! -f "$source_script" ]; then
        echo "plak.sh not found. Run ./compile.sh first." >&2
        exit 1
    fi
else
    if ! command -v curl >/dev/null 2>&1; then
        echo "curl is required to install Plak." >&2
        exit 1
    fi

    source_script=$(mktemp)
    trap 'rm -f "$source_script"' EXIT
    curl -fsSL "$download_url" -o "$source_script"
fi

needs_sudo=false
if [ "$(id -u)" -ne 0 ]; then
    install_parent=$(dirname "$install_dir")
    if { [ -d "$install_dir" ] && [ ! -w "$install_dir" ]; } ||
        { [ ! -d "$install_dir" ] && [ ! -w "$install_parent" ]; }; then
        needs_sudo=true
    fi
fi

run_install_command() {
    if [ "$needs_sudo" = true ]; then
        sudo "$@"
    else
        "$@"
    fi
}

if [ ! -d "$install_dir" ]; then
    run_install_command mkdir -p "$install_dir"
fi

run_install_command cp "$source_script" "$destination"
run_install_command chmod +x "$destination"

echo "Installed Plak to $destination"
