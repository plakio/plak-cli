#!/usr/bin/env bash

set -euo pipefail

# BEGIN plak-release-channel
# Stable release channel shared by install.sh and `plak upgrade`.
#
# Publication is tag-driven: the newest vMAJOR.MINOR.PATCH tag is the stable
# release. Prereleases (v1.2.3-rc1), build metadata, foreign tags and tags with
# leading zeroes are ignored. The resolver reads the tag list from the GitHub
# API and never falls back to main or releases/latest.
#
# Keep this block byte-for-byte identical in shared/release and install.sh;
# tests/release-channel.sh extracts both markers and compares them.

plak_release_is_version() {
    [[ "${1:-}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

plak_release_is_stable_tag() {
    [[ "${1:-}" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

plak_release_numeric_gt() {
    local left="${1:-}" right="${2:-}"

    if [ "${#left}" -ne "${#right}" ]; then
        [ "${#left}" -gt "${#right}" ]
        return
    fi
    [[ "$left" > "$right" ]]
}

plak_release_version_gt() {
    local left="${1:-}" right="${2:-}"
    local left_major left_minor left_patch right_major right_minor right_patch

    plak_release_is_version "$left" || return 1
    plak_release_is_version "$right" || return 1

    IFS=. read -r left_major left_minor left_patch <<<"$left"
    IFS=. read -r right_major right_minor right_patch <<<"$right"

    if [ "$left_major" != "$right_major" ]; then
        plak_release_numeric_gt "$left_major" "$right_major"
        return
    fi
    if [ "$left_minor" != "$right_minor" ]; then
        plak_release_numeric_gt "$left_minor" "$right_minor"
        return
    fi
    plak_release_numeric_gt "$left_patch" "$right_patch"
}

plak_release_latest_stable_tag() {
    local line tag latest=""

    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%$'\r'}
        tag=${line##refs/tags/}
        plak_release_is_stable_tag "$tag" || continue
        if [ -z "$latest" ] || plak_release_version_gt "${tag#v}" "${latest#v}"; then
            latest=$tag
        fi
    done

    [ -n "$latest" ] || return 1
    printf '%s\n' "$latest"
}

plak_release_tag_names_from_json() {
    printf '%s\n' "${1:-}" \
        | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed -e 's/.*"name"[[:space:]]*:[[:space:]]*"//' -e 's/"$//' \
        || true
}

plak_release_api_request() {
    local url="$1"
    local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

    if [ -n "$token" ]; then
        curl -sS -L --connect-timeout 10 --max-time 60 \
            -H 'Accept: application/vnd.github+json' \
            -H 'X-GitHub-Api-Version: 2022-11-28' \
            -H "Authorization: Bearer ${token}" \
            -w '\n%{http_code}' "$url"
    else
        curl -sS -L --connect-timeout 10 --max-time 60 \
            -H 'Accept: application/vnd.github+json' \
            -H 'X-GitHub-Api-Version: 2022-11-28' \
            -w '\n%{http_code}' "$url"
    fi
}

plak_release_resolve_latest_tag() {
    local api_url="https://api.github.com/repos/plakio/plak-cli/tags"
    local page=1 per_page=100 max_pages=20
    local url response http_code body names count all="" latest

    while [ "$page" -le "$max_pages" ]; do
        url="${api_url}?per_page=${per_page}&page=${page}"
        if ! response=$(plak_release_api_request "$url"); then
            echo "Could not reach the GitHub API to list Plak release tags. Check your network connection." >&2
            return 1
        fi

        http_code=${response##*$'\n'}
        body=${response%$'\n'*}

        case "$http_code" in
            200) ;;
            401)
                echo "GitHub API authentication failed (HTTP 401). Check GITHUB_TOKEN/GH_TOKEN." >&2
                return 1
                ;;
            403|429)
                echo "GitHub API rate limit or access denied (HTTP $http_code). Retry later, or set GITHUB_TOKEN/GH_TOKEN for a higher limit." >&2
                return 1
                ;;
            404)
                echo "Could not list Plak release tags: repository or tags not found (HTTP 404)." >&2
                return 1
                ;;
            5??)
                echo "GitHub API is unavailable (HTTP $http_code). Retry later." >&2
                return 1
                ;;
            *)
                echo "Unexpected response from the GitHub API (HTTP $http_code) while listing Plak tags." >&2
                return 1
                ;;
        esac

        names=$(plak_release_tag_names_from_json "$body")
        count=$(printf '%s\n' "$names" | grep -c . || true)
        all="${all}${names}"$'\n'

        if [ "$count" -lt "$per_page" ]; then
            break
        fi
        page=$((page + 1))
    done

    if [ "$page" -gt "$max_pages" ]; then
        echo "Could not list all Plak release tags (more than $((max_pages * per_page)) tags)." >&2
        return 1
    fi

    if ! latest=$(printf '%s\n' "$all" | plak_release_latest_stable_tag); then
        echo "No stable Plak release tag (vMAJOR.MINOR.PATCH) was found." >&2
        return 1
    fi

    printf '%s\n' "$latest"
}

plak_release_script_url() {
    printf 'https://raw.githubusercontent.com/plakio/plak-cli/%s/plak.sh\n' "$1"
}

plak_release_validate_script() {
    local file="${1:-}" expected="${2:-}" embedded actual

    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        echo "Invalid Plak script: the downloaded file is missing or empty." >&2
        return 1
    fi
    if [ "$(head -n 1 "$file")" != '#!/usr/bin/env bash' ]; then
        echo "Invalid Plak script: expected the compiled Bash script." >&2
        return 1
    fi
    if ! bash -n "$file" 2>/dev/null; then
        echo "Invalid Plak script: the download is not valid Bash." >&2
        return 1
    fi

    embedded=$(sed -n 's/^PLAK_VERSION="\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p' "$file")
    case "$embedded" in
        ""|*$'\n'*)
            echo "Invalid Plak script: missing or ambiguous PLAK_VERSION." >&2
            return 1
            ;;
    esac

    if [ -n "$expected" ] && [ "$embedded" != "$expected" ]; then
        echo "Invalid Plak script: tag version ${expected} does not match embedded version ${embedded}." >&2
        return 1
    fi

    if ! actual=$(PLAK_NO_PATH_PRELUDE=1 bash "$file" version 2>/dev/null); then
        echo "Invalid Plak script: it cannot run 'version'." >&2
        return 1
    fi
    if [ "$actual" != "plak v${embedded}" ]; then
        echo "Invalid Plak script: 'version' reported '${actual}', expected 'plak v${embedded}'." >&2
        return 1
    fi

    printf '%s\n' "$embedded"
}
# END plak-release-channel

DEV_MODE=false
AUTO_YES=false
CLI_ONLY=false

# Agent/CI friendly switches. `PLAK_YES=1` installs the CLI and the local
# stack without asking; `PLAK_CLI_ONLY=1` keeps the old CLI-only behavior.
# `PLAK_INSTALL_DEPS=1` is kept as an alias for the full install.
case "${PLAK_YES:-0}" in
    1|true|yes|y) AUTO_YES=true ;;
esac
case "${PLAK_INSTALL_DEPS:-0}" in
    1|true|yes|y) AUTO_YES=true ;;
esac
case "${PLAK_CLI_ONLY:-0}" in
    1|true|yes|y) CLI_ONLY=true ;;
esac

for arg in "$@"; do
    case "$arg" in
        --dev) DEV_MODE=true ;;
        --yes|-y) AUTO_YES=true ;;
        --cli-only|--no-deps) CLI_ONLY=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

# A local checkout install (--dev) is a development convenience: do not pull in
# Homebrew or system services unless the caller explicitly asks with --yes.
if [ "$DEV_MODE" = true ] && [ "$AUTO_YES" != true ]; then
    CLI_ONLY=true
fi

plak_installer_has_tty() {
    ( : < /dev/tty ) 2>/dev/null
}

plak_installer_can_prompt() {
    plak_installer_has_tty && [ -w /dev/tty ]
}

plak_installer_confirm() {
    local prompt="$1" answer
    printf '%s [y/N] ' "$prompt" > /dev/tty 2>/dev/null || return 1
    if ! IFS= read -r answer < /dev/tty 2>/dev/null; then
        return 1
    fi
    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
    esac
    return 1
}

# Use Homebrew already installed outside PATH (the shell profile was never
# configured), or in a non-default prefix. `brew shellenv` fixes this process.
plak_installer_load_homebrew() {
    local candidate
    if command -v brew >/dev/null 2>&1; then
        return 0
    fi
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew "$HOME/.linuxbrew/bin/brew"; do
        if [ -x "$candidate" ] &&
            eval "$("$candidate" shellenv)" &&
            command -v brew >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# Persist Homebrew's shellenv for new terminals, as Homebrew's own installer
# only prints the instruction. Idempotent and limited to zsh/bash profiles.
plak_installer_persist_homebrew() {
    [ "${PLAK_NO_SHELL_PROFILE:-0}" = "1" ] && return 0

    local brew_bin line profile=""
    brew_bin=$(command -v brew 2>/dev/null) || return 0
    line="eval \"\$($brew_bin shellenv)\""

    case "${SHELL:-}" in
        */zsh*) profile="${ZDOTDIR:-$HOME}/.zprofile" ;;
        */bash*) profile="$HOME/.bash_profile" ;;
    esac

    if [ -z "$profile" ]; then
        echo "Add this line to your shell profile so new terminals find Homebrew:"
        echo "  $line"
        return 0
    fi
    if grep -qsF "$brew_bin shellenv" "$profile" 2>/dev/null; then
        return 0
    fi
    if { echo; echo "$line"; } >> "$profile" 2>/dev/null; then
        echo "Added Homebrew to PATH for new terminals in $profile."
    else
        echo "Add this line to $profile so new terminals find Homebrew:"
        echo "  $line"
    fi
}

# Download Homebrew's installer to a file first. `bash -c "$(curl ...)"` would
# run an empty script and report success when the download fails.
plak_installer_run_homebrew() {
    local url="$1"
    (
        set -e
        local script
        script=$(mktemp "${TMPDIR:-/tmp}/plak-homebrew.XXXXXX") || {
            echo "Error: could not create a temporary file for the Homebrew installer." >&2
            exit 1
        }
        trap 'rm -f "$script"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        trap 'exit 129' HUP

        if ! curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$script" ||
            [ ! -s "$script" ]; then
            echo "Error: could not download the Homebrew installer from $url." >&2
            exit 1
        fi

        if [ "$AUTO_YES" = true ]; then
            if plak_installer_has_tty; then
                NONINTERACTIVE=1 /bin/bash "$script" < /dev/tty
            else
                NONINTERACTIVE=1 /bin/bash "$script" < /dev/null
            fi
        else
            /bin/bash "$script" < /dev/tty
        fi
    )
}

plak_installer_ensure_homebrew() {
    if plak_installer_load_homebrew; then
        plak_installer_persist_homebrew
        return 0
    fi

    echo "On macOS, Plak installs its local stack through Homebrew."
    echo "Homebrew: https://brew.sh (or the .pkg at https://github.com/Homebrew/brew/releases/latest)"

    local install_homebrew=false
    if [ "$AUTO_YES" = true ]; then
        install_homebrew=true
    elif plak_installer_can_prompt &&
        plak_installer_confirm "Install Homebrew now?"; then
        install_homebrew=true
    fi

    if [ "$install_homebrew" != true ]; then
        echo "Homebrew is required for the local stack. Install it, then run this installer again." >&2
        return 1
    fi

    if [ "$AUTO_YES" = true ] && ! plak_installer_has_tty &&
        ! sudo -n true 2>/dev/null; then
        echo "Error: installing Homebrew requires sudo. Run the installer in a terminal, or configure passwordless sudo for the agent." >&2
        return 1
    fi
    if ! command -v xcode-select >/dev/null 2>&1 ||
        ! xcode-select -p >/dev/null 2>&1; then
        echo "Error: Homebrew requires the Xcode Command Line Tools." >&2
        echo "Run 'xcode-select --install', finish the installer, then rerun this installer." >&2
        return 1
    fi

    echo "Installing Homebrew..."
    homebrew_install_url="${PLAK_HOMEBREW_INSTALL_URL:-https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh}"
    if ! plak_installer_run_homebrew "$homebrew_install_url"; then
        echo "Error: Homebrew installation failed. Install it from https://brew.sh and run this installer again." >&2
        return 1
    fi
    if ! plak_installer_load_homebrew; then
        echo "Error: Homebrew was installed but 'brew' is not available. Open a new shell and run this installer again." >&2
        return 1
    fi
    plak_installer_persist_homebrew
    return 0
}

plak_path_has_dir() {
    case ":${PATH:-}:" in
        *":$1:"*) return 0 ;;
    esac
    return 1
}

os_name=$(uname -s)

# Resolve Homebrew before choosing the install directory. Otherwise a Mac
# without Homebrew would get the CLI in /usr/local/bin and Homebrew later in
# /opt/homebrew/bin, leaving two installations that can shadow each other.
# CLI-only installs intentionally skip this and stay in the default PATH.
if [ "$os_name" = "Darwin" ] && [ "$CLI_ONLY" != true ]; then
    if ! plak_installer_ensure_homebrew; then
        echo "Nothing was installed. Re-run with PLAK_CLI_ONLY=1 to install only the CLI." >&2
        exit 1
    fi
fi

install_dir="${PLAK_INSTALL_DIR:-}"

if [ -z "$install_dir" ]; then
    install_dir="/usr/local/bin"

    # For a full macOS install Homebrew is now on PATH, so Apple Silicon uses
    # its bin directory. CLI-only installs without Homebrew stay in
    # /usr/local/bin, which is part of the default macOS PATH.
    if [ "$os_name" = "Darwin" ] && [ "$(uname -m)" = "arm64" ] &&
        plak_path_has_dir "/opt/homebrew/bin"; then
        install_dir="/opt/homebrew/bin"
    fi
fi

destination="$install_dir/plak"

needs_sudo=false
if [ "$(id -u)" -ne 0 ]; then
    install_parent=$(dirname "$install_dir")
    if { [ -d "$install_dir" ] && [ ! -w "$install_dir" ]; } ||
        { [ ! -d "$install_dir" ] && [ ! -w "$install_parent" ]; }; then
        needs_sudo=true
    fi
fi

# Fail clearly in non-interactive agent/CI runs that need sudo but cannot
# prompt for a password. Interactive runs leave sudo to do its normal prompt.
if [ "$needs_sudo" = true ] && [ "$(id -u)" -ne 0 ] &&
    ! ( : < /dev/tty ) 2>/dev/null && ! sudo -n true 2>/dev/null; then
    echo "Error: installing to $install_dir requires sudo. Run this installer in a terminal, or configure passwordless sudo for the agent." >&2
    exit 1
fi

run_install_command() {
    if [ "$needs_sudo" = true ]; then
        sudo "$@"
    else
        "$@"
    fi
}

downloaded_script=""
source_script=""
staged_script=""

cleanup() {
    if [ -n "$downloaded_script" ]; then
        rm -f "$downloaded_script"
    fi
    if [ -n "$staged_script" ]; then
        run_install_command rm -f "$staged_script"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

expected_version=""

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

    if [ -n "${PLAK_INSTALL_URL:-}" ]; then
        # Explicit override for tests and advanced/offline use. It is not the
        # stable channel and it never falls back here implicitly.
        download_url="$PLAK_INSTALL_URL"
        echo "Downloading Plak from $download_url..."
    else
        echo "Resolving the latest stable Plak release..."
        if ! release_tag=$(plak_release_resolve_latest_tag); then
            echo "Error: could not determine the latest stable Plak release. Nothing was installed or replaced." >&2
            exit 1
        fi
        download_url=$(plak_release_script_url "$release_tag")
        expected_version="${release_tag#v}"
        echo "Downloading Plak ${release_tag}..."
    fi

    if ! source_script=$(mktemp "${TMPDIR:-/tmp}/plak-install.XXXXXX"); then
        echo "Error: could not create a temporary file in ${TMPDIR:-/tmp}. Nothing was installed or replaced." >&2
        exit 1
    fi
    downloaded_script="$source_script"

    if ! curl -fsSL --connect-timeout 10 --max-time 120 "$download_url" -o "$source_script"; then
        echo "Error: could not download Plak from $download_url. Nothing was installed or replaced." >&2
        exit 1
    fi
fi

if ! plak_release_validate_script "$source_script" "$expected_version" >/dev/null; then
    echo "Error: the downloaded Plak script failed validation. Nothing was installed or replaced." >&2
    exit 1
fi

if [ ! -d "$install_dir" ]; then
    run_install_command mkdir -p "$install_dir"
fi

install_dir=$(cd "$install_dir" && pwd)
destination="$install_dir/plak"

if [ -d "$destination" ]; then
    echo "Cannot install Plak: $destination is a directory." >&2
    exit 1
fi

# Stage on the destination filesystem so the final rename is atomic. The
# previous installation is only replaced after download and validation succeed.
staged_script=$(run_install_command mktemp "$install_dir/.plak-install.XXXXXX") || {
    echo "Error: could not create a staged file in $install_dir. Nothing was installed or replaced." >&2
    exit 1
}
run_install_command cp "$source_script" "$staged_script"
run_install_command chmod 755 "$staged_script"

if ! cmp -s "$source_script" "$staged_script"; then
    echo "Error: could not stage the Plak script in $install_dir. Nothing was installed or replaced." >&2
    exit 1
fi
if ! plak_release_validate_script "$staged_script" "$expected_version" >/dev/null; then
    echo "Error: the staged Plak script failed validation. Nothing was installed or replaced." >&2
    exit 1
fi

run_install_command mv -f "$staged_script" "$destination"
staged_script=""

echo "Installed Plak to $destination"

# Older universal installers could leave the script in /opt/homebrew/bin even
# when Homebrew was absent. A second copy on PATH can shadow this installation
# as soon as the shell changes directories or Homebrew is installed. Only
# remove regular files that are clearly the Plak script; Homebrew-managed
# symlinks are left untouched.
stale_candidates="${PLAK_STALE_PLAK_PATH:-/opt/homebrew/bin/plak /usr/local/bin/plak}"
if [ "$os_name" = "Darwin" ]; then
    for stale_plak in $stale_candidates; do
        [ "$destination" != "$stale_plak" ] || continue
        [ -f "$stale_plak" ] && [ ! -L "$stale_plak" ] || continue
        [ "$(head -n 1 "$stale_plak" 2>/dev/null)" = '#!/usr/bin/env bash' ] || continue
        grep -q '^PLAK_NAME="plak"$' "$stale_plak" 2>/dev/null || continue

        if run_install_command rm -f "$stale_plak" 2>/dev/null; then
            echo "Removed the previous Plak installation at $stale_plak."
        else
            echo "Warning: remove the previous Plak installation at $stale_plak (sudo rm -f $stale_plak)." >&2
        fi
    done
fi

if ! plak_path_has_dir "$install_dir"; then
    echo "" >&2
    echo "Warning: $install_dir is not in your PATH, so 'plak' will not be found in new shells." >&2
    echo "Add it to your shell profile and restart the shell. For example:" >&2
    echo "  export PATH=\"$install_dir:\$PATH\"" >&2
    echo "You can also run it with its full path: $destination" >&2
fi

# The universal installer ships the CLI. `plak install` installs the local
# stack (gum, FrankenPHP, MariaDB, Mailpit and WP-CLI). On macOS MariaDB and
# Mailpit come from Homebrew, so offer to install Homebrew and then the stack
# instead of leaving the user with a command that fails halfway through.
plak_installer_missing_deps() {
    local dep missing=""
    for dep in gum frankenphp mariadb mailpit wp; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing="${missing}${missing:+ }$dep"
        fi
    done
    printf '%s\n' "$missing"
}

plak_installer_run_stack() {
    local args=()
    [ "$AUTO_YES" = true ] && args+=(--yes)
    if plak_installer_has_tty; then
        "$destination" install ${args[@]+"${args[@]}"} < /dev/tty
    else
        "$destination" install ${args[@]+"${args[@]}"}
    fi
}

if [ "$CLI_ONLY" = true ]; then
    exit 0
fi

missing_deps=$(plak_installer_missing_deps)
if [ -n "$missing_deps" ]; then
    echo ""
    echo "Plak CLI is installed, but the local stack is not: $missing_deps"

    if [ "$AUTO_YES" = true ] ||
        { plak_installer_can_prompt && plak_installer_confirm "Install the local Plak stack now? This runs: $destination install"; }; then
        if [ "$AUTO_YES" = true ] && ! plak_installer_has_tty &&
            ! sudo -n true 2>/dev/null; then
            echo "Error: installing the local stack requires sudo. Run the installer in a terminal, or configure passwordless sudo for the agent." >&2
            exit 1
        fi
        echo "Installing the local Plak stack..."
        if ! plak_installer_run_stack; then
            echo "Plak CLI is installed, but the local stack setup failed. Run '$destination install' to retry." >&2
            exit 1
        fi
    else
        echo "Run: $destination install"
    fi
fi
