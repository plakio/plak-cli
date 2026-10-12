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
case "$os_name" in
    Linux|Darwin) ;;
    *) echo "Unsupported operating system: $os_name (Plak requires Linux or macOS Bash)." >&2; exit 1 ;;
esac
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
    if ! curl --connect-timeout 10 --max-time 120 -fsSL "$download_url" -o "$source_script"; then
        echo "Could not download Plak from $download_url. Nothing was installed." >&2
        exit 1
    fi
fi

# Plak is a compiled Bash script on every supported CPU, not a native binary.
# Reject foreign executables/HTML before executing or replacing anything.
if [ "$(head -n 1 "$source_script")" != '#!/usr/bin/env bash' ] || ! bash -n "$source_script"; then
    echo "Invalid Plak download: expected the compiled Bash script. Nothing was installed." >&2
    exit 1
fi
expected_version=$(sed -n 's/^PLAK_VERSION="\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)"$/plak v\1/p' "$source_script")
if [ -z "$expected_version" ] || [[ "$expected_version" == *$'\n'* ]]; then
    echo "Invalid Plak download: missing or ambiguous version identity. Nothing was installed." >&2
    exit 1
fi
validate_executable() {
    local result
    if ! result=$("$@" version 2>&1) || [ "$result" != "$expected_version" ]; then
        echo "Plak executable validation failed: expected '$expected_version', received '${result:-no output}'." >&2
        return 1
    fi
}
validate_executable bash "$source_script"

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

# Stage on the same filesystem so rename is atomic and never follows a previous
# plak symlink into another program (for example a multicall coreutils binary).
install_dir=$(cd "$install_dir" && pwd)
destination="$install_dir/plak"
if [ -d "$destination" ]; then
    echo "Cannot install Plak: $destination is a directory." >&2
    exit 1
fi
staged_script=$(run_install_command mktemp "$install_dir/.plak-install.XXXXXX")
cleanup() {
    [ "$DEV_MODE" = true ] || rm -f "$source_script"
    [ -z "${staged_script:-}" ] || run_install_command rm -f "$staged_script"
}
trap cleanup EXIT
run_install_command cp "$source_script" "$staged_script"
run_install_command chmod 755 "$staged_script"
validate_executable "$staged_script"
run_install_command mv -f "$staged_script" "$destination"
staged_script=""
validate_executable "$destination"

echo "Installed Plak to $destination"
