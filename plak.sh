#!/usr/bin/env bash

# Plak - Bash entrypoint
# Source file for the compiled plak.sh distribution script.

set -euo pipefail

PLAK_NAME="plak"
PLAK_VERSION="0.4.62"
PLAK_HOME="${PLAK_HOME:-$HOME/.plak}"
PLAK_SSH_CONFIG="${PLAK_SSH_CONFIG:-$HOME/.ssh/config}"
PLAK_HOSTS_FILE="${PLAK_HOSTS_FILE:-/etc/hosts}"

# Ensure common user-managed binary locations are available when launched from
# restricted environments such as cron, launchd, systemd, or GUI shells.
# /home/linuxbrew/.linuxbrew/bin and ~/.linuxbrew/bin cover Homebrew on Linux,
# whose default prefix is neither /usr/local nor /opt/homebrew.
# Append (don't prepend) so an explicit PATH — e.g. a caller's or a hermetic
# test's — keeps its priority; we only supply entries that are missing.
# PLAK_NO_PATH_PRELUDE=1 disables the addition for hermetic tests.
if [ "${PLAK_NO_PATH_PRELUDE:-0}" != "1" ]; then
    for _plak_bin in /opt/homebrew/bin /home/linuxbrew/.linuxbrew/bin "$HOME/.linuxbrew/bin" /usr/local/bin /usr/local/sbin "$HOME/.local/bin"; do
        if [ -d "$_plak_bin" ] && [[ ":$PATH:" != *":$_plak_bin:"* ]]; then
            PATH="$PATH:$_plak_bin"
        fi
    done
fi
unset _plak_bin
export PATH

plak_setup_environment() {
    local os_name
    os_name=$(uname -s)

    case "$os_name" in
        Darwin)
            PLAK_OS="macos"
            ;;
        Linux)
            PLAK_OS="linux"
            ;;
        *)
            PLAK_OS="unsupported"
            ;;
    esac

    export PLAK_OS
}

plak_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

plak_has_tty() {
    [ -t 0 ] && [ -t 1 ]
}

plak_require_gum() {
    if ! plak_command_exists gum; then
        echo "Error: gum is required for interactive Plak commands." >&2
        echo "Install it from https://github.com/charmbracelet/gum or run: plak install" >&2
        exit 1
    fi

    if ! plak_has_tty; then
        echo "Error: this command needs an interactive terminal." >&2
        exit 1
    fi
}

plak_show_help() {
    cat <<'HELP'
Plak CLI

Usage:
  plak <command> [arguments]

Commands:
  remote      Manage SSH remotes and site bindings
  hosts       Manage entries in /etc/hosts
  sshkey      Manage SSH keys
  add         Create a WordPress or plain local site
  import      Create a local site from a backup ZIP or TAR
  clone       Duplicate a local site into an independent copy
  delete      Delete a local site
  list        List local sites
  login       Generate a one-time WordPress admin login link
  wp          Run WP-CLI inside a local WordPress site
  core        Inspect or update WordPress core versions
  network     Inspect multisite networks and create subsites
  agent       Prepare or repair a site for WP-MCP agents
  db          Manage local site databases
  snapshot    Create, list, restore, export or delete site snapshots
  history     Save component history, compare files and selectively roll back
  pull        Pull a remote WordPress site into Plak
  push        Push a local Plak site to a remote WordPress site
  enable      Start local site services
  disable     Stop local site services
  reload      Regenerate and reload the local site server
  trust       Trust the local HTTPS certificate
  ports       Reconfigure HTTP/HTTPS ports
  memory      Show or raise PHP memory_limit
  directive   Manage custom Caddyfile rules
  mappings    Manage extra domains for a site
  proxy       Manage standalone reverse proxies
  share       Create a temporary public tunnel for a site
  lan         Manage LAN access for local sites
  tailscale   Expose sites to a Tailscale network
  status      Check local dependencies and paths
  health      Diagnose services, disk and OPcache; tune cache and HTTP2
  install     Install required dependencies
  skill       Install the Plak agent skill
  upgrade     Upgrade the local site stack
  version     Show Plak version
  help        Show this help

Examples:
  plak remote list
  plak remote connect
  plak status
HELP
}

plak_display_command_help() {
    local command="${1:-}"

    case "$command" in
        remote)
            cat <<'HELP'
Usage:
  plak remote <action> [args]

Actions:
  list        List hosts from ~/.ssh/config (use --managed, --unmanaged, or --json)
  add         Add a remote. Flags: --host --user [--port] [--path] [--identity|--no-identity]
  edit        Edit a remote. Flags: --newname --host --user --port --path --identity --no-identity
  delete      Delete a remote. Use --yes to skip confirmation
  connect     ssh into a remote (cd into remote_path)
  attach      Bind a remote to a Plak site. Use --yes to skip replace confirmation
  detach      Unbind a remote from a Plak site. Use --yes to skip confirmation
  help        Show remote help

Agent-friendly: every action accepts non-interactive flags. See 'plak remote help' for details.
HELP
            ;;
        hosts)
            cat <<'HELP'
Usage:
  plak hosts <action>

Actions:
  list        List non-comment entries from /etc/hosts
  add         Add a hosts entry (positional: <ip> <domain>)
  delete      Delete a hosts entry (use --yes in non-interactive mode)
  help        Show hosts help
HELP
            ;;
        sshkey)
            cat <<'HELP'
Usage:
  plak sshkey <action>

Actions:
  list        List likely SSH private keys in ~/.ssh
  view        Show SSH key details and public key
  create      Create a new SSH key interactively
  delete      Delete an SSH key and its public key
  help        Show sshkey help
HELP
            ;;
        skill)
            if declare -F plak_skill_help >/dev/null 2>&1; then
                plak_skill_help
            else
                echo "Usage: plak skill install [codex|claude-code|opencode|hermes|pi|global|all]"
            fi
            ;;
        install)
            cat <<'HELP'
Usage:
  plak install [--yes]

Installs or guides installation for dependencies used by Plak sites.
HELP
            ;;
        status)
            echo "Usage: plak status"
            ;;
        health)
            echo "Usage: plak health [--json]"
            echo "       plak health opcache [--json]"
            echo "       plak health opcache set <directive>=<value>... [--restart]"
            echo "       plak health http2 [--json]"
            echo ""
            echo "  Reports services, FrankenPHP, disk, recent failure signals and"
            echo "  abandoned resources without changing anything. 'opcache' reads the"
            echo "  web process cache; 'opcache set' tunes validated directives and only"
            echo "  applies them when asked. 'http2' probes protocol negotiation."
            ;;
        add)
            echo "Usage: plak add <name> [--wp-version latest|nightly|<version>] [--multisite subdomains|subdirectories] [--plain] [--agent|--no-agent] [--no-reload]"
            echo ""
            echo "  --agent     Force agent preparation (WP-MCP and HTML Editor, then"
            echo "              register the site with wp-mcp-cli). WordPress only."
            echo "  --no-agent  Skip agent preparation even when wp-mcp-cli is installed."
            echo ""
            echo "  WordPress sites become agent-ready by default when wp-mcp-cli is"
            echo "  installed; use --no-agent to opt out."
            ;;
        agent)
            echo "Usage: plak agent <site> [--json]"
            echo ""
            echo "Prepares or repairs an existing WordPress site for agents: installs"
            echo "WP-MCP and HTML Editor, rotates the scoped Application Password,"
            echo "refreshes the wp-mcp-cli profile and verifies abilities."
            ;;
        delete)
            echo "Usage: plak delete <name> [--force|--yes] [--no-reload]"
            ;;
        list)
            echo "Usage: plak list [--totals] [--json]"
            ;;
        login)
            echo "Usage: plak login <site> [<user>] [--subsite <id>] [--raw]"
            ;;
        wp)
            echo "Usage: plak wp <site> <wp-cli arguments...>"
            echo "Arguments after <site> are passed unchanged to WP-CLI."
            ;;
        core)
            plak_core_usage
            ;;
        history)
            plak_history_usage
            ;;
        network)
            plak_network_usage
            ;;
        db)
            echo "Usage: plak db <backup|list>"
            ;;
        version)
            echo "Usage: plak version"
            ;;
        *)
            if declare -F plak_site_display_command_help >/dev/null 2>&1; then
                plak_site_display_command_help "$command"
                return
            fi
            plak_show_help
            ;;
    esac
}

main() {
    plak_setup_environment

    local PLAK_SITE_CMD
    if command -v plak >/dev/null 2>&1; then
        PLAK_SITE_CMD="plak"
    else
        PLAK_SITE_CMD="$0"
    fi
    export PLAK_SITE_CMD

    PLAK_QUIET=0
    PLAK_JSON=0
    local new_args=()
    local wp_passthrough=false
    for arg in "$@"; do
        # Once the top-level wp command is seen, its site and every remaining
        # argument belong to it, including --help, --quiet and --json.
        if [ "$wp_passthrough" = true ]; then
            new_args+=("$arg")
        elif [[ "$arg" == "--quiet" || "$arg" == "-q" ]]; then
            PLAK_QUIET=1
        elif [[ "$arg" == "--json" ]]; then
            PLAK_JSON=1
        elif [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
            plak_display_command_help "${new_args[0]:-${1:-}}"
            exit 0
        else
            new_args+=("$arg")
            if [ "${#new_args[@]}" -eq 1 ] && [ "$arg" = wp ]; then
                wp_passthrough=true
            fi
        fi
    done
    export PLAK_QUIET
    export PLAK_JSON
    if [ "$PLAK_JSON" = "1" ] && [ "$wp_passthrough" = false ]; then
        new_args+=("--json")
    fi
    set -- "${new_args[@]}"

    local command="${1:-help}"
    if [ "$#" -gt 0 ]; then
        shift
    fi

    case "$command" in
        add|import|clone|delete|rename|list|path|pull|push|login|enable|disable|reload|trust|db|snapshot|history|directive|proxy|tailscale|mappings|lan|ports|memory|log|share|wsl-hosts|url|upgrade|install|health)
            set +e
            ;;
    esac

    case "$command" in
        wp)
            plak_site_wp "$@"
            ;;
        core)
            plak_core "$@"
            ;;
        network)
            plak_network "$@"
            ;;
        agent)
            check_dependencies
            plak_site_agent "$@"
            ;;
        remote)
            plak_remote "$@"
            ;;
        hosts)
            plak_hosts "$@"
            ;;
        sshkey)
            plak_sshkey "$@"
            ;;
        skill)
            plak_skill "$@"
            ;;
        add)
            check_dependencies
            plak_site_add "$@"
            ;;
        import)
            check_dependencies
            plak_site_import "$@"
            ;;
        clone)
            check_dependencies
            plak_site_clone "$@"
            ;;
        delete)
            check_dependencies
            plak_site_delete "$@"
            ;;
        rename)
            check_dependencies
            plak_site_rename "$@"
            ;;
        list)
            check_dependencies
            plak_site_list "$@"
            ;;
        path)
            check_dependencies
            plak_site_path "$@"
            ;;
        pull)
            check_dependencies
            plak_site_pull "$@"
            ;;
        push)
            check_dependencies
            plak_site_push "$@"
            ;;
        login)
            check_dependencies
            plak_site_login "$@"
            ;;
        enable)
            check_dependencies
            plak_site_enable "$@"
            ;;
        disable)
            check_dependencies
            plak_site_disable "$@"
            ;;
        reload)
            check_dependencies
            plak_site_reload "$@"
            ;;
        trust)
            check_dependencies
            plak_site_trust "$@"
            ;;
        db)
            check_dependencies
            local action="${1:-}"
            [ "$#" -gt 0 ] && shift
            case "$action" in
                backup)
                    plak_site_db_backup "$@"
                    ;;
                list)
                    plak_site_db_list "$@"
                    ;;
                *)
                    plak_display_command_help "db"
                    exit 0
                    ;;
            esac
            ;;
        snapshot)
            check_dependencies
            plak_site_snapshot "$@"
            ;;
        history)
            plak_history "$@"
            ;;
        directive)
            check_dependencies
            local action="${1:-}"
            [ "$#" -gt 0 ] && shift
            case "$action" in
                add|update)
                    plak_site_directive_add_or_update "$@"
                    ;;
                delete)
                    plak_site_directive_delete "$@"
                    ;;
                list)
                    plak_site_directive_list "$@"
                    ;;
                *)
                    plak_site_display_command_help "directive"
                    exit 0
                    ;;
            esac
            ;;
        proxy)
            check_dependencies
            plak_site_proxy "$@"
            ;;
        tailscale)
            check_dependencies
            plak_site_tailscale "$@"
            ;;
        status)
            check_dependencies
            plak_status "$@"
            ;;
        health)
            plak_health "$@"
            ;;
        mappings)
            check_dependencies
            plak_site_mappings "$@"
            ;;
        lan)
            check_dependencies
            plak_site_lan "$@"
            ;;
        ports)
            check_dependencies
            plak_site_ports "$@"
            ;;
        memory)
            check_dependencies
            plak_site_memory "$@"
            ;;
        log)
            plak_site_log "$@"
            ;;
        share)
            check_dependencies
            plak_site_share "$@"
            ;;
        wsl-hosts)
            plak_site_wsl_hosts "$@"
            ;;
        url)
            check_dependencies
            plak_site_url "$@"
            ;;
        upgrade)
            plak_site_upgrade "$@"
            ;;
        status|doctor)
            plak_status "$@"
            ;;
        install)
            plak_install "$@"
            ;;
        version|--version|-v)
            plak_version "$@"
            ;;
        help)
            plak_show_help
            ;;
        *)
            echo "Error: unknown command '$command'" >&2
            echo ""
            plak_show_help
            exit 1
            ;;
    esac
}


# --- Shared Helpers ---
# Source: shared/remote
plak_remote_choose_ssh() {
    local hosts selected manual_label="Enter manually"
    hosts=$(plak_remote_parse_hosts | awk -F'|' '{print $1}')

    if [ -n "$hosts" ]; then
        selected=$(printf "%s\n%s\n" "$hosts" "$manual_label" | gum filter --placeholder "Choose SSH connection")
        [ -n "$selected" ] || return 1

        if [ "$selected" != "$manual_label" ]; then
            printf '%s\n' "$selected"
            return 0
        fi
    fi

    selected=$(gum input --width 0 --placeholder "user@host.com -p 2222" --prompt "SSH Connection: ")
    [ -n "$selected" ] || return 1
    selected="${selected##ssh }"
    printf '%s\n' "$selected"
}

# Source: shared/site/agent
# Agent site preparation.
#
# Turns a freshly created WordPress site into one an agent can drive over
# WP-MCP: install and activate the WP-MCP and HTML Editor plugins from Plak's
# own downloads, mint a scoped Application Password, register the site with
# wp-mcp-cli, and verify the abilities surface. Every step is idempotent so a
# failed preparation can be retried with `plak agent <site>` without creating a
# second site, a duplicate profile, or an extra Application Password.

# Pinned for a reproducible install; bump deliberately with the CLI.
PLAK_WPMCP_VERSION="${PLAK_WPMCP_VERSION:-v0.1.9}"
PLAK_WPMCP_INSTALL_URL="${PLAK_WPMCP_INSTALL_URL:-https://raw.githubusercontent.com/plakio/wp-mcp-cli/${PLAK_WPMCP_VERSION}/wp-mcp.sh}"
PLAK_AGENT_WP_MCP_URL="${PLAK_AGENT_WP_MCP_URL:-https://downloads.plak.io/wp-mcp-latest.zip}"
PLAK_AGENT_HTML_EDITOR_URL="${PLAK_AGENT_HTML_EDITOR_URL:-https://downloads.plak.io/html-editor-latest.zip}"
# One name for every password this flow mints, so retries can revoke the old
# one instead of accumulating credentials.
PLAK_AGENT_PASSWORD_NAME="Plak CLI (agent)"

plak_agent_user_agent() {
    printf 'PlakCLI/%s\n' "${PLAK_VERSION:-unknown}"
}

plak_agent_wpmcp_available() {
    plak_command_exists wp-mcp
}

# wp-mcp talks HTTPS to the site with its own curl/OpenSSL. Homebrew's curl on
# Linux does not read the system CA store, so the Caddy local root installed by
# `plak trust` is invisible to it (curl exit 60). When the system bundle exists
# and actually contains a Caddy local authority, point the subprocess at it.
# This is a no-op on macOS, where Homebrew curl uses the system keychain.
plak_agent_curl_ca_env() {
    PLAK_AGENT_CA_ENV=()
    [ "$(uname -s)" = "Linux" ] || return 0
    local bundle="${PLAK_AGENT_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"
    [ -s "$bundle" ] || return 0
    if grep -qi 'Caddy Local Authority' "$bundle" 2>/dev/null; then
        PLAK_AGENT_CA_ENV=("SSL_CERT_FILE=$bundle" "CURL_CA_BUNDLE=$bundle")
    fi
}

# Install wp-mcp-cli and its jq dependency. Homebrew on macOS, the pinned
# release script elsewhere. Never installs an unpinned "main" build.
plak_agent_install_cli() {
    if plak_agent_wpmcp_available; then
        echo "✅ wp-mcp is already installed."
        return 0
    fi

    if ! plak_command_exists jq; then
        install_dependency "jq" "jq" "jq" "jq" ""
    fi

    echo "📦 Installing wp-mcp-cli ${PLAK_WPMCP_VERSION}..."
    if [ "$OS" = macos ] && plak_command_exists brew; then
        if brew install plakio/tap/wp-mcp-cli >/dev/null 2>&1; then
            hash -r
            if plak_agent_wpmcp_available; then
                echo "✅ wp-mcp-cli installed."
                return 0
            fi
        fi
        plak_ui_warn "Homebrew install failed; falling back to the release script."
    fi

    if ! plak_command_exists curl; then
        plak_ui_error "curl is required to install wp-mcp-cli."
        return 1
    fi

    local tmp
    tmp=$(mktemp) || return 1
    if ! curl -fsSL "$PLAK_WPMCP_INSTALL_URL" -o "$tmp"; then
        rm -f "$tmp"
        plak_ui_error "Could not download wp-mcp-cli from $PLAK_WPMCP_INSTALL_URL."
        return 1
    fi

    local install_dir="${PLAK_WPMCP_BIN_DIR:-${BIN_DIR:-/usr/local/bin}}"
    if ! mkdir -p "$install_dir" 2>/dev/null; then
        $SUDO_CMD mkdir -p "$install_dir" || { rm -f "$tmp"; return 1; }
    fi
    if ! mv "$tmp" "$install_dir/wp-mcp" 2>/dev/null; then
        if ! $SUDO_CMD mv "$tmp" "$install_dir/wp-mcp"; then
            rm -f "$tmp"
            plak_ui_error "Could not install wp-mcp to $install_dir."
            return 1
        fi
    fi
    chmod +x "$install_dir/wp-mcp" 2>/dev/null || $SUDO_CMD chmod +x "$install_dir/wp-mcp"
    hash -r

    if ! plak_agent_wpmcp_available; then
        plak_ui_error "wp-mcp installed but not found on PATH. Restart your shell and re-run."
        return 1
    fi
    echo "✅ wp-mcp-cli installed."
}

# Download one plugin ZIP with Plak's User-Agent and reject anything that is
# not a ZIP, so a firewall block page served with HTTP 200 never reaches
# WP-CLI as a "plugin".
plak_agent_download_plugin() {
    local url="$1" dest="$2"
    if ! plak_command_exists curl; then
        plak_ui_error "curl is required to download agent plugins."
        return 1
    fi
    if ! curl --fail --location --silent --show-error \
        --user-agent "$(plak_agent_user_agent)" \
        --max-time 120 \
        --output "$dest" "$url"; then
        rm -f "$dest"
        plak_ui_error "Download failed for $url (check the downloads.plak.io firewall rule for PlakCLI)."
        return 1
    fi
    local magic=""
    if [ -f "$dest" ]; then
        magic=$(head -c 2 "$dest" 2>/dev/null || true)
    fi
    if [ "$magic" != "PK" ]; then
        rm -f "$dest"
        plak_ui_error "Downloaded file is not a ZIP plugin (blocked or corrupt): $url"
        return 1
    fi
    return 0
}

# Derive the WordPress plugin slug from a ZIP: the directory of the file that
# carries a "Plugin Name:" header. Falls back to the archive name.
plak_agent_zip_plugin_slug() {
    local zip="$1" slug="" frank
    if frank=$(command -v frankenphp 2>/dev/null); then
        # The PHP below is intentionally single-quoted so the shell does not expand it.
        # shellcheck disable=SC2016
        slug=$(PLAK_AGENT_ZIP_PATH="$zip" "$frank" php-cli -r '
            $path = getenv("PLAK_AGENT_ZIP_PATH");
            if (!class_exists("ZipArchive")) { exit(1); }
            $zip = new ZipArchive();
            if ($zip->open($path) !== true) { exit(1); }
            $slug = "";
            for ($i = 0; $i < $zip->numFiles; $i++) {
                $name = $zip->getNameIndex($i);
                if (!preg_match("#^([^/]+)/[^/]+\.php$#", $name, $m)) { continue; }
                $data = $zip->getFromIndex($i);
                if ($data !== false && preg_match("/^[ \t\/*#@]*Plugin Name:/mi", $data)) {
                    $slug = $m[1];
                    break;
                }
            }
            $zip->close();
            if ($slug === "") { exit(1); }
            echo $slug;
        ' 2>/dev/null) || slug=""
    fi
    if [ -z "$slug" ]; then
        slug=$(basename "$zip")
        slug="${slug%.zip}"
        slug="${slug%-latest}"
    fi
    [ -n "$slug" ] || return 1
    printf '%s\n' "$slug"
}

# Install and activate both agent plugins from the local ZIPs, then confirm
# each is actually active.
plak_agent_install_plugins() {
    local site_dir="$1"
    local public_dir="$site_dir/public"
    if [ ! -f "$public_dir/wp-config.php" ]; then
        plak_ui_error "WordPress site not found at $public_dir."
        return 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d) || return 1
    local wp_mcp_zip="$tmpdir/wp-mcp.zip" html_zip="$tmpdir/html-editor.zip"
    local rc=0

    if ! plak_agent_download_plugin "$PLAK_AGENT_WP_MCP_URL" "$wp_mcp_zip"; then rc=1; fi
    if [ "$rc" -eq 0 ] && ! plak_agent_download_plugin "$PLAK_AGENT_HTML_EDITOR_URL" "$html_zip"; then rc=1; fi
    if [ "$rc" -ne 0 ]; then
        rm -rf "$tmpdir"
        return 1
    fi

    local wp_mcp_slug html_slug
    wp_mcp_slug=$(plak_agent_zip_plugin_slug "$wp_mcp_zip") || wp_mcp_slug=""
    html_slug=$(plak_agent_zip_plugin_slug "$html_zip") || html_slug=""

    if ! ( cd "$public_dir" && plak_wp_cli plugin install "$wp_mcp_zip" --activate --force --quiet ); then rc=1; fi
    if [ "$rc" -eq 0 ] && ! ( cd "$public_dir" && plak_wp_cli plugin install "$html_zip" --activate --force --quiet ); then rc=1; fi
    rm -rf "$tmpdir"
    if [ "$rc" -ne 0 ]; then
        plak_ui_error "Could not install and activate the agent plugins."
        return 1
    fi

    # Installation success is not activation success: verify each slug.
    local slug
    for slug in "$wp_mcp_slug" "$html_slug"; do
        [ -n "$slug" ] || continue
        if ! ( cd "$public_dir" && plak_wp_cli plugin is-active "$slug" --skip-plugins --skip-themes ) >/dev/null 2>&1; then
            plak_ui_error "Plugin '$slug' is installed but not active."
            return 1
        fi
    done
    echo "   - ✅ WP-MCP and HTML Editor installed and active."
}

# wp-mcp talks to /wp-json/..., which only resolves when the site has a
# non-empty permalink structure. Plak creates sites with plain permalinks,
# where /wp-json/... is rendered by the theme instead of reaching the REST API,
# so every wp-mcp call would fail. Set a standard structure only when none is
# set (never clobber a deliberate one) and flush the rewrite rules.
plak_agent_ensure_rest_api() {
    local public_dir="$1"
    local current
    current=$( cd "$public_dir" && plak_wp_cli option get permalink_structure \
        --skip-plugins --skip-themes 2>/dev/null ) || current=""
    if [ -z "$current" ]; then
        if ! ( cd "$public_dir" && plak_wp_cli option update permalink_structure \
            '/%postname%/' --skip-plugins --skip-themes ); then
            plak_ui_error "Could not enable the pretty permalinks WP-MCP requires."
            return 1
        fi
    fi
    ( cd "$public_dir" && plak_wp_cli rewrite flush --hard --skip-plugins --skip-themes ) >/dev/null 2>&1 || true
    return 0
}

# WP-MCP ships with its abilities disabled and locked to the domain they were
# enabled on. An agent-ready site must turn them on, or every ability call is
# refused with wp_mcp_disabled even though discovery succeeds.
plak_agent_enable_wp_mcp() {
    local public_dir="$1" host="$2"
    if ! ( cd "$public_dir" && plak_wp_cli option update wp_mcp_ai_abilities_enabled \
        '1' --skip-plugins --skip-themes ) >/dev/null; then
        plak_ui_error "Could not enable WP-MCP abilities."
        return 1
    fi
    if ! ( cd "$public_dir" && plak_wp_cli option update wp_mcp_ai_abilities_domain \
        "$host" --skip-plugins --skip-themes ) >/dev/null; then
        plak_ui_error "Could not lock WP-MCP abilities to $host."
        return 1
    fi
    return 0
}

# Remove every password this flow created for a user.
plak_agent_revoke_passwords() {
    local public_dir="$1" user="$2"
    local rows
    rows=$( cd "$public_dir" && plak_wp_cli user application-password list "$user" \
        --fields=uuid,name --format=csv --skip-plugins --skip-themes 2>/dev/null ) || return 0
    [ -n "$rows" ] || return 0
    local uuid name
    while IFS=, read -r uuid name; do
        uuid="${uuid%$'\r'}"
        name="${name%$'\r'}"
        # WP-CLI's CSV formatter double-quotes values containing spaces, so
        # strip the quotes before comparing the name.
        name="${name#\"}"
        name="${name%\"}"
        [ -n "$uuid" ] || continue
        [ "$uuid" = "uuid" ] && continue
        [ "$name" = "$PLAK_AGENT_PASSWORD_NAME" ] || continue
        ( cd "$public_dir" && plak_wp_cli user application-password delete "$user" "$uuid" \
            --quiet --skip-plugins --skip-themes ) >/dev/null 2>&1 || true
    done <<< "$rows"
}

# Create a scoped Application Password, rotating any earlier one first.
plak_agent_create_password() {
    local public_dir="$1" user="$2"
    plak_agent_revoke_passwords "$public_dir" "$user"
    local pass
    pass=$( cd "$public_dir" && plak_wp_cli user application-password create "$user" \
        "$PLAK_AGENT_PASSWORD_NAME" --porcelain --skip-plugins --skip-themes ) || return 1
    [ -n "$pass" ] || return 1
    printf '%s\n' "$pass"
}

# Register (or refresh) the wp-mcp-cli profile. The secret travels through the
# environment, never argv, so it cannot leak via process listings or logs.
# Errors are surfaced rather than swallowed, so the real cause (e.g. a TLS trust
# failure) is visible instead of a generic "could not register".
plak_agent_register_profile() {
    local site_name="$1" user="$2" pass="$3"
    local url
    url=$(url_for "$site_name.localhost")
    plak_agent_curl_ca_env
    local output
    if ! output=$(WPMCP_USERNAME="$user" WPMCP_PASSWORD="$pass" \
        env ${PLAK_AGENT_CA_ENV[@]+"${PLAK_AGENT_CA_ENV[@]}"} \
        wp-mcp --json auth login "$url" --name "$site_name" 2>&1); then
        [ -n "$output" ] && plak_ui_error "$output"
        return 1
    fi
    return 0
}

plak_agent_verify() {
    local site_name="$1"
    plak_agent_curl_ca_env
    env ${PLAK_AGENT_CA_ENV[@]+"${PLAK_AGENT_CA_ENV[@]}"} \
        wp-mcp --json --site "$site_name" discover >/dev/null 2>&1
}

plak_agent_site_reachable() {
    local site_name="$1" url
    url=$(url_for "$site_name.localhost")
    local _
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if curl -ks --max-time 1 -o /dev/null "$url/" 2>/dev/null; then
            return 0
        fi
        sleep 0.3
    done
    return 1
}

# Prepare a freshly created/imported/cloned WordPress site for agents when
# wp-mcp-cli is available. Unlike `plak add --agent`, a failure here must not
# fail the caller: the site is already valid and repair is a retry away. Prints
# the retry hint instead. Sites without wp-mcp are left alone and told clearly.
plak_agent_maybe_prepare() {
    local site_name="$1"
    local site_dir="$SITES_DIR/$site_name.localhost"
    if [ ! -f "$site_dir/public/wp-config.php" ]; then
        return 0
    fi
    if ! plak_agent_wpmcp_available; then
        echo "ℹ️  '$site_name.localhost' is not agent-ready (wp-mcp-cli not installed). Run 'plak install' then 'plak agent $site_name'."
        return 0
    fi
    if plak_agent_prepare "$site_name"; then
        return 0
    fi
    echo "⚠️  '$site_name.localhost' was created, but agent preparation did not finish. Retry with: plak agent $site_name" >&2
    return 0
}

# Prepare an existing WordPress site for agents. Idempotent: safe to re-run.
plak_agent_prepare() {
    local site_name="$1"
    local site_dir="$SITES_DIR/$site_name.localhost"
    local public_dir="$site_dir/public"

    if [ ! -f "$public_dir/wp-config.php" ]; then
        plak_ui_error "WordPress site '$site_name.localhost' not found."
        return 1
    fi
    if ! plak_agent_wpmcp_available; then
        plak_ui_error "wp-mcp-cli is required. Run 'plak install' first."
        return 1
    fi
    if ! plak_agent_site_reachable "$site_name"; then
        plak_ui_error "Site '$site_name.localhost' is not answering yet. Run 'plak reload' and retry: plak agent $site_name"
        return 1
    fi

    echo "🤖 Preparing '$site_name.localhost' for agents (WP-MCP + HTML Editor)..."
    plak_agent_install_plugins "$site_dir" || return 1
    plak_agent_ensure_rest_api "$public_dir" || return 1
    plak_agent_enable_wp_mcp "$public_dir" "$site_name.localhost" || return 1

    local pass
    pass=$(plak_agent_create_password "$public_dir" admin) || {
        plak_ui_error "Could not create an application password."
        return 1
    }
    if ! plak_agent_register_profile "$site_name" admin "$pass"; then
        # Do not leave an orphan credential behind if registration failed.
        plak_agent_revoke_passwords "$public_dir" admin
        plak_ui_error "Could not register '$site_name' with wp-mcp-cli."
        return 1
    fi
    if ! plak_agent_verify "$site_name"; then
        plak_ui_error "WP-MCP is registered, but its abilities could not be discovered."
        return 1
    fi

    # Record readiness so `plak list` and the dashboard can report it without
    # re-running WP-CLI. A failed removal later (e.g. site deleted) is harmless.
    : > "$site_dir/agent-ready"

    plak_ui_success "Agent ready: wp-mcp profile '$site_name' at $(url_for "$site_name.localhost")"
    return 0
}

# Source: shared/site/history
# The generated distribution embeds this literal PHP program; no standalone
# PHP/Python dependency and no mutation of the site's Git index is needed.
plak_history_program() {
    cat <<'PHP'
function historyFail(string $message): never { throw new RuntimeException($message); }
function historyJson(mixed $value): string { return json_encode($value, JSON_THROW_ON_ERROR | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES); }
function historyWrite(string $path, mixed $data): void {
    $tmp=$path.'.tmp-'.bin2hex(random_bytes(6));
    if(file_put_contents($tmp,historyJson($data))===false || !rename($tmp,$path)) historyFail('Cannot publish '.$path);
}
function historyMkdir(string $path): void {
    if(!is_dir($path) && !mkdir($path,0700,true)) historyFail('Cannot create '.$path);
}
function historyRemove(string $path): void {
    if(is_link($path) || is_file($path)) { if(!unlink($path)) historyFail('Cannot remove '.$path); return; }
    if(!is_dir($path)) return;
    if(!chmod($path,fileperms($path)|0700)) historyFail('Cannot prepare directory for removal: '.$path);
    foreach(new FilesystemIterator($path,FilesystemIterator::SKIP_DOTS) as $entry) historyRemove($entry->getPathname());
    if(!rmdir($path)) historyFail('Cannot remove directory '.$path);
}
function historyPath(string $path): string {
    if(!preg_match('~^(plugins|themes|mu-plugins)/[^/]+(?:/[^/]+)*$~D',$path)) historyFail('Select a component or file beneath plugins/, themes/ or mu-plugins/.');
    foreach(explode('/',$path) as $part) if($part==='.' || $part==='..' || $part==='.git' || preg_match('/[\x00-\x1f\x7f]/',$part)) historyFail('Unsafe selection path.');
    return $path;
}
function historyMatches(string $path,string $filter): bool { return $path===$filter || str_starts_with($path,$filter.'/'); }
function historyScan(string $root): array {
    $result=[];
    $walk=function(string $path,string $relative) use (&$walk,&$result): void {
        if(is_link($path)) { $result[$relative]=['type'=>'symlink','target'=>readlink($path)]; return; }
        if(is_dir($path)) {
            $result[$relative]=['type'=>'directory','mode'=>fileperms($path)&0777,'git'=>file_exists($path.'/.git') || is_link($path.'/.git')];
            $entries=scandir($path); if($entries===false) historyFail('Cannot inspect '.$relative);
            foreach($entries as $name) if($name!=='.' && $name!=='..' && $name!=='.git') $walk($path.'/'.$name,$relative.'/'.$name);
        } elseif(is_file($path)) {
            $hash=hash_file('sha256',$path); if($hash===false) historyFail('Cannot read '.$relative);
            $result[$relative]=['type'=>'file','sha256'=>$hash,'mode'=>fileperms($path)&0777,'size'=>filesize($path)];
        } elseif(file_exists($path)) historyFail('Unsupported special file: '.$relative);
    };
    foreach(['plugins','themes','mu-plugins'] as $kind) {
        $path=$root.'/'.$kind;
        if(is_link($path)) historyFail('Linked content root is unsupported: '.$kind);
        if(is_dir($path)) $walk($path,$kind);
    }
    ksort($result); return $result;
}
function historyWP(array $args): mixed {
    global $site;
    $command=[getenv('PLAK_HISTORY_FRANK'),'php-cli',getenv('PLAK_HISTORY_WP')];
    if(getenv('PLAK_HISTORY_ROOT_FLAG')==='--allow-root') $command[]='--allow-root';
    $command=array_merge($command,$args,['--skip-plugins','--skip-themes']);
    $error=tmpfile(); if($error===false) historyFail('Cannot allocate WP-CLI error stream.');
    $proc=proc_open($command,[0=>['pipe','r'],1=>['pipe','w'],2=>$error],$pipes,$site.'/public');
    if(!is_resource($proc)) historyFail('Cannot execute WP-CLI.');
    fclose($pipes[0]); $output=stream_get_contents($pipes[1]); fclose($pipes[1]);
    $code=proc_close($proc); fclose($error);
    if($code!==0) historyFail('WP-CLI metadata query failed (code '.$code.'); history not saved.');
    return json_decode($output,true,512,JSON_THROW_ON_ERROR);
}
function historyMetadata(): array {
    global $content;
    $actual=historyWP(['eval','echo wp_json_encode(WP_CONTENT_DIR);']);
    if(!is_string($actual) || realpath($actual)!==realpath($content)) historyFail('Custom/external WP_CONTENT_DIR is unsupported.');
    $metadata=['plugins'=>historyWP(['plugin','list','--fields=name,status,version','--format=json']),
        'themes'=>historyWP(['theme','list','--fields=name,status,version','--format=json'])];
    foreach($metadata as &$components) usort($components,fn($a,$b)=>strcmp($a['name'],$b['name']));
    return $metadata;
}
function historyRecords(): array {
    global $store;
    $records=[];
    foreach(glob($store.'/records/*/manifest.json') ?: [] as $path) {
        $record=historyRecord(basename(dirname($path)));
        $records[$record['id']]=$record;
    }
    ksort($records); return $records;
}
function historyRecord(string $id): array {
    global $store;
    if(!preg_match('/^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{12}$/D',$id)) historyFail('Invalid history ID.');
    $path=$store.'/records/'.$id.'/manifest.json';
    if(!is_file($path) || is_link($path)) historyFail('History record not found.');
    $record=json_decode(file_get_contents($path),true,512,JSON_THROW_ON_ERROR);
    if(($record['id']??null)!==$id || ($record['schema']??null)!==1 || !is_array($record['files']??null)) historyFail('Invalid history manifest.');
    foreach($record['files'] as $relative=>$entry) {
        if(!in_array($relative,['plugins','themes','mu-plugins'],true)) historyPath($relative);
        if(!in_array($entry['type']??null,['directory','file','symlink'],true)) historyFail('Invalid manifest entry.');
        if($entry['type']!=='symlink' && (!is_int($entry['mode']??null) || $entry['mode']<0 || $entry['mode']>0777)) historyFail('Invalid file mode.');
        if($entry['type']==='file' && !preg_match('/^[a-f0-9]{64}$/D',$entry['sha256']??'')) historyFail('Invalid file hash.');
    }
    return $record;
}
function historyCopyFiles(string $from,string $to,array $files): void {
    foreach($files as $relative=>$entry) {
        $target=$to.'/'.$relative;
        if($entry['type']==='directory') historyMkdir($target);
        if($entry['type']==='file') {
            historyMkdir(dirname($target));
            if(is_link($from.'/'.$relative) || !copy($from.'/'.$relative,$target) || !chmod($target,$entry['mode'])) historyFail('Cannot copy '.$relative);
            if(hash_file('sha256',$target)!==$entry['sha256']) historyFail('File changed or corrupt: '.$relative);
        }
    }
    // Apply directory modes last, so a read-only directory can be populated.
    foreach(array_reverse($files,true) as $relative=>$entry) if($entry['type']==='directory' && !chmod($to.'/'.$relative,$entry['mode'])) historyFail('Cannot set directory permissions.');
}
function historySave(string $note): array {
    global $store,$content;
    $files=historyScan($content); $metadata=historyMetadata(); $records=historyRecords();
    $last=$records ? end($records) : null;
    if($last && $last['files']===$files && $last['components']===$metadata) {
        foreach($files as $path=>$entry) if($entry['type']==='file') {
            $stored=$store.'/records/'.$last['id'].'/files/'.$path;
            if(!is_file($stored) || is_link($stored) || hash_file('sha256',$stored)!==$entry['sha256']) historyFail('Latest history record is corrupt: '.$path);
        }
        return ['changed'=>false,'id'=>$last['id']];
    }
    $id=gmdate('Ymd\THis\Z').'-'.bin2hex(random_bytes(6)); $temporary=$store.'/.pending-'.$id;
    historyMkdir($temporary.'/files');
    try {
        historyCopyFiles($content,$temporary.'/files',$files);
        if(historyScan($content)!==$files || historyMetadata()!==$metadata) historyFail('Site changed during save; retry after updates finish.');
        $record=['schema'=>1,'id'=>$id,'created'=>gmdate('c'),'note'=>$note,'components'=>$metadata,'files'=>$files];
        historyWrite($temporary.'/manifest.json',$record);
        if(!rename($temporary,$store.'/records/'.$id)) historyFail('Cannot publish history record.');
        return ['changed'=>true,'id'=>$id];
    } finally { if(is_dir($temporary)) historyRemove($temporary); }
}
function historyProtected(array $files,string $filter): void {
    foreach($files as $path=>$entry) {
        if((historyMatches($path,$filter) || historyMatches($filter,$path)) && ($entry['type']==='symlink' || ($entry['git']??false))) historyFail('Selection intersects a symlink or Git checkout: '.$path);
    }
}
function historyDiff(array $from,array $to,string $filter=''): array {
    $diff=[]; $paths=array_unique(array_merge(array_keys($from),array_keys($to))); sort($paths);
    foreach($paths as $path) {
        if($filter!=='' && !historyMatches($path,$filter)) continue;
        if(($from[$path]??null)===($to[$path]??null)) continue;
        $diff[]=['path'=>$path,'change'=>!isset($from[$path])?'added':(!isset($to[$path])?'removed':'modified'),'before'=>$from[$path]??null,'after'=>$to[$path]??null];
    }
    return $diff;
}
function historyComponentDiff(array $from,array $to,string $filter): array {
    $index=function(array $metadata) use ($filter): array {
        $components=[];
        foreach($metadata as $kind=>$items) foreach($items as $item) {
            $root=($item['status']??'')==='must-use'?'mu-plugins':$kind;
            $path=$root.'/'.$item['name'];
            if($filter!=='' && !historyMatches($filter,$path) && !historyMatches($path,$filter)
                && !historyMatches($filter,$path.'.php')) continue;
            $components[$path]=$item;
        }
        ksort($components); return $components;
    };
    return historyDiff($index($from),$index($to));
}
function historySafeDestination(string $filter): string {
    global $content;
    $path=$content;
    if(is_link($path)) historyFail('Linked wp-content is unsupported.');
    foreach(explode('/',$filter) as $part) { $path.='/'.$part; if(is_link($path)) historyFail('Linked destination is unsupported.'); }
    // Avoid modifying any checkout owning wp-content, including .git files
    // used by worktrees. Metadata/history never uses that repository.
    $parent=$content;
    while(true) {
        if(file_exists($parent.'/.git') || is_link($parent.'/.git')) historyFail('Rollback into a Git checkout is unsupported; restore through Git explicitly.');
        $next=dirname($parent); if($next===$parent) break; $parent=$next;
    }
    return $path;
}
function historyRecover(): array {
    global $store;
    $journal=$store.'/restore.json';
    if(!is_file($journal)) return ['recovered'=>false];
    $state=json_decode(file_get_contents($journal),true,512,JSON_THROW_ON_ERROR);
    $destination=historySafeDestination(historyPath($state['selection']));
    if(!preg_match('/^[a-f0-9]{12}$/D',$state['transaction'])) historyFail('Invalid recovery transaction.');
    $transaction=$store.'/.restore-'.$state['transaction'];
    if(file_exists($transaction.'/old')) {
        historyRemove($destination);
        if(!rename($transaction.'/old',$destination)) historyFail('Cannot restore pre-rollback files; retained at '.$transaction.'/old');
    } elseif(!$state['existed'] && !file_exists($transaction.'/new')) historyRemove($destination);
    if(!unlink($journal)) historyFail('Cannot clear recovery journal.');
    historyRemove($transaction);
    return ['recovered'=>true,'selection'=>$state['selection'],'safety_id'=>$state['safety_id']];
}
function historyRestore(string $id,string $filter): array {
    global $store,$content;
    $record=historyRecord($id); $current=historyScan($content);
    $destination=historySafeDestination($filter);
    historyProtected($current,$filter); historyProtected($record['files'],$filter);
    if(!is_dir(dirname($destination))) historyFail('Selection parent directory must already exist.');
    $selected=array_filter($record['files'],fn($entry,$path)=>historyMatches($path,$filter),ARRAY_FILTER_USE_BOTH);
    if(!$selected && !isset($current[$filter])) historyFail('Selection absent in both current and historical state.');
    if(!historyDiff($current,$record['files'],$filter)) return ['changed'=>false];
    $safety=historySave('Before rollback '.$id.' '.$filter);
    if(historyScan($content)!==$current) historyFail('Site changed while preparing rollback.');
    $token=bin2hex(random_bytes(6)); $transaction=$store.'/.restore-'.$token;
    historyMkdir($transaction.'/stage');
    try {
        historyCopyFiles($store.'/records/'.$id.'/files',$transaction.'/stage',$selected);
        $staged=$transaction.'/stage/'.$filter;
        if(file_exists($staged) && !rename($staged,$transaction.'/new')) historyFail('Cannot stage selection.');
        $journal=['selection'=>$filter,'transaction'=>$token,'existed'=>file_exists($destination),'safety_id'=>$safety['id']];
        historyWrite($store.'/restore.json',$journal);
    } catch(Throwable $error) { historyRemove($transaction); throw $error; }
    try {
        if($journal['existed'] && !rename($destination,$transaction.'/old')) historyFail('Cannot move current selection to recovery.');
        if(file_exists($transaction.'/new') && !rename($transaction.'/new',$destination)) historyFail('Cannot install historical selection.');
        if(!unlink($store.'/restore.json')) historyFail('Cannot commit rollback.');
    } catch(Throwable $error) { historyRecover(); throw $error; }
    historyRemove($transaction);
    return ['changed'=>true,'selection'=>$filter,'restored_id'=>$id,'safety_id'=>$safety['id'],'database_changed'=>false];
}
try {
    $site=getenv('PLAK_HISTORY_SITE'); $content=$site.'/public/wp-content'; $store=$site.'/private/history';
    if(is_link($site) || is_link($site.'/public') || is_link($content) || is_link($site.'/private') || is_link($store) || is_link($store.'/records')) historyFail('Linked history/content roots are unsupported.');
    historyMkdir($store.'/records');
    $args=json_decode(getenv('PLAK_HISTORY_ARGS') ?: '[]',true,512,JSON_THROW_ON_ERROR);
    if(!is_array($args) || !array_is_list($args)) historyFail('Invalid command arguments.');
    $action=array_shift($args) ?? 'list';
    if($action!=='jobs') {
        $lock=fopen($store.'/lock','c');
        if(!$lock || !flock($lock,LOCK_EX|LOCK_NB)) historyFail('Another history operation is running for this site.');
    }
    if(is_file($store.'/restore.json') && !in_array($action,['recover','jobs'],true)) historyFail('Interrupted rollback: run history <site> recover --yes first.');
    switch($action) {
        case 'save':
            $note='';
            if(count($args)===2 && $args[0]==='--note') $note=$args[1]; elseif($args) historyFail('Usage: save [--note <text>]');
            $result=historySave($note); break;
        case 'list':
            if($args) historyFail('Usage: list');
            $result=array_values(array_map(fn($record)=>array_diff_key($record,['files'=>true]),historyRecords())); break;
        case 'show':
            if(count($args)<1 || count($args)>2) historyFail('Usage: show <id> [<path>]');
            $result=historyRecord($args[0]);
            if(isset($args[1])) { $filter=historyPath($args[1]); $result['files']=array_filter($result['files'],fn($entry,$path)=>historyMatches($path,$filter),ARRAY_FILTER_USE_BOTH); } break;
        case 'diff':
            if(count($args)<2 || count($args)>3) historyFail('Usage: diff <from> <to|current> [<path>]');
            $from=historyRecord($args[0]); $to=$args[1]==='current'?['files'=>historyScan($content),'components'=>historyMetadata()]:historyRecord($args[1]);
            $filter=isset($args[2])?historyPath($args[2]):'';
            $result=['files'=>historyDiff($from['files'],$to['files'],$filter),'components'=>historyComponentDiff($from['components'],$to['components'],$filter)]; break;
        case 'restore':
            if(count($args)!==3 || $args[2]!=='--yes') historyFail('Usage: restore <id> <path> --yes');
            $result=historyRestore($args[0],historyPath($args[1])); break;
        case 'recover':
            if($args!==['--yes']) historyFail('Usage: recover --yes');
            $result=historyRecover(); break;
        case 'jobs':
            if($args) historyFail('Usage: jobs');
            $result=[];
            foreach(glob($store.'/jobs/job.*',GLOB_ONLYDIR) ?: [] as $job) {
                $exit=is_file($job.'/exit')?(int)file_get_contents($job.'/exit'):null;
                $pid=is_file($job.'/pid')?(int)file_get_contents($job.'/pid'):null;
                $status=$exit!==null?($exit===0?'done':'failed'):'running';
                if($exit===null && $pid && function_exists('posix_kill') && !posix_kill($pid,0)) $status='interrupted';
                $log=is_file($job.'/log')?file_get_contents($job.'/log'):'';
                $result[]=['job'=>basename($job),'status'=>$status,'exit_code'=>$exit,'log'=>substr($log,-8192)];
            }
            break;
        default: historyFail('Unknown history action.');
    }
    echo historyJson($result)."\n";
} catch(Throwable $error) { fwrite(STDERR,'Error: '.$error->getMessage()."\n"); exit(1); }
PHP
}

# Source: shared/site/multisite
# shellcheck disable=SC2016 # Single-quoted eval programs are PHP, not shell.
# Authoritative network queries use WordPress, never a marker file alone.
plak_multisite_wp() (
    local public="$1" wp_cmd
    shift
    wp_cmd=$(get_wp_cmd) || return 1
    [ -n "$wp_cmd" ] || return 1
    cd "$public" || return 1
    "$wp_cmd" "$@"
)

plak_multisite_mode() {
    local mode
    mode=$(plak_multisite_wp "$1" eval 'echo is_multisite() ? (is_subdomain_install() ? "subdomains" : "subdirectories") : "single";' --skip-plugins --skip-themes) || return 1
    case "$mode" in single|subdomains|subdirectories) printf '%s\n' "$mode" ;; *) plak_ui_error 'Cannot determine WordPress network mode.'; return 1 ;; esac
}

plak_multisite_require_single() {
    local public="$1" action="$2" mode
    [ -f "$public/wp-config.php" ] || return 0
    # Ordinary configs avoid an extra bootstrap; a marker or a MULTISITE
    # declaration requires an authoritative check, failing closed on errors.
    if [ ! -f "$public/../.multisite-mode" ] && ! grep -q MULTISITE "$public/wp-config.php"; then return 0; fi
    mode=$(plak_multisite_mode "$public") || return 1
    [ "$mode" = single ] || { plak_ui_error "$action does not support multisite; no data was modified."; return 1; }
}

plak_multisite_rename() (
    local old="$1" new="$2" source="$SITES_DIR/$1.localhost" recovery binding
    # Reuse the independently-created clone transaction. Failed provisioning
    # cannot affect the source; retain the source DB/files as recovery on rename.
    (plak_site_clone "$old" "$new" --yes --no-reload) || return 1
    recovery=$(mktemp -d "$PLAK_SITE_DIR/cache/rename-recovery.XXXXXX") || return 1
    for binding in .remote mappings; do
        if [ -f "$source/$binding" ]; then cp "$source/$binding" "$SITES_DIR/$new.localhost/$binding" || return 1; fi
    done
    mv "$source" "$recovery/$old.localhost" || return 1
    if [ -f "$CUSTOM_CADDY_DIR/$old.localhost" ]; then
        mv "$CUSTOM_CADDY_DIR/$old.localhost" "$recovery/directives" || return 1
    fi
    printf '%s\n' "$recovery" > "$SITES_DIR/$new.localhost/rename-recovery" || return 1
    regenerate_caddyfile || return 1
    echo "Network renamed to $new.localhost; original database retained for recovery in $recovery."
)

# Reject mapped domains/multiple networks before any resource is modified.
plak_multisite_validate_local() {
    PLAK_MS_HOST="$2.localhost" plak_multisite_wp "$1" eval '
        global $wpdb;
        if (!is_multisite()) WP_CLI::error("Expected a multisite network.");
        $host=getenv("PLAK_MS_HOST"); $network=get_network();
        if ((int)$wpdb->get_var("SELECT COUNT(*) FROM {$wpdb->site}") !== 1) WP_CLI::error("Multiple networks are not supported.");
        if (explode(":", $network->domain)[0] !== $host || $network->path !== "/") WP_CLI::error("Only a local root network is supported.");
        foreach (get_sites(["number"=>0,"network_id"=>$network->id]) as $site) {
            $domain=explode(":",$site->domain)[0];
            if ($domain !== $host && !str_ends_with($domain,".".$host)) WP_CLI::error("External/domain-mapped subsites are unsupported.");
        }
    ' --skip-plugins --skip-themes
}

plak_multisite_rewrite() {
    local public="$1" old="$2" new="$3" domain value key
    domain=$(plak_multisite_wp "$public" config get DOMAIN_CURRENT_SITE) || return 1
    [[ "$domain" = "$old.localhost" || "$domain" = "$old.localhost:"* ]] || { plak_ui_error 'Unexpected network domain constant.'; return 1; }
    plak_multisite_wp "$public" search-replace "(?<![A-Za-z0-9-])${old}\\.localhost(?![A-Za-z0-9.-])" "$new.localhost" \
        --regex --regex-flags=i --network --all-tables-with-prefix --precise --skip-plugins --skip-themes || return 1
    plak_multisite_wp "$public" config set DOMAIN_CURRENT_SITE "${domain/$old.localhost/$new.localhost}" --quiet || return 1
    for key in WP_HOME WP_SITEURL; do
        if plak_multisite_wp "$public" config has "$key" >/dev/null 2>&1; then
            value=$(plak_multisite_wp "$public" config get "$key") || return 1
            plak_multisite_wp "$public" config set "$key" "${value//$old.localhost/$new.localhost}" --quiet || return 1
        fi
    done
    plak_multisite_validate_local "$public" "$new" || return 1
}

# Source: shared/site/remote-transfer
# Self-contained remote transfer for pull/push.
#
# Plak ships the Go runtime to the remote over SSH and runs it there, so the
# remote never needs a public URL or internet access to plak.sh during the
# operation. The same engine file is used locally and remotely for a single
# operation, keeping both ends on one version.

PLAK_GO_RUNTIME_URL="${PLAK_GO_RUNTIME_URL:-https://plak.sh/go}"

# Copy the Go runtime engine to <output>. Prefers an explicit PLAK_GO_RUNTIME,
# then an engine shipped next to the CLI (development checkouts), then the
# published endpoint.
plak_fetch_go_runtime() {
    local output="$1"

    if [ -n "${PLAK_GO_RUNTIME:-}" ]; then
        if [ -r "$PLAK_GO_RUNTIME" ]; then
            cp "$PLAK_GO_RUNTIME" "$output"
            return 0
        fi
        echo "Error: PLAK_GO_RUNTIME is set but not readable: $PLAK_GO_RUNTIME" >&2
        return 1
    fi

    local self="${BASH_SOURCE[0]:-}"
    if [ -n "$self" ]; then
        local dir=""
        dir=$(cd "$(dirname "$self")" 2>/dev/null && pwd -P) || dir=""
        if [ -n "$dir" ] && [ -r "$dir/go/go.sh" ]; then
            cp "$dir/go/go.sh" "$output"
            return 0
        fi
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: curl is required to fetch the Plak Go runtime from $PLAK_GO_RUNTIME_URL." >&2
        return 1
    fi
    if ! curl -fsSL "$PLAK_GO_RUNTIME_URL" -o "$output" || [ ! -s "$output" ]; then
        echo "Error: could not fetch the Plak Go runtime from $PLAK_GO_RUNTIME_URL." >&2
        return 1
    fi
}

# A unique, space-free path for the helper on the remote. mktemp templates
# differ across platforms, so build the name here instead.
plak_remote_helper_path() {
    printf '/tmp/plak-go-%s-%s.sh\n' "$(date +%s)" "${RANDOM}${RANDOM}"
}

# --- Remote cleanup bookkeeping ---
# pull/push assign these globals as soon as remote paths exist; the EXIT trap
# removes them and reports the location when removal is impossible.
PLAK_RT_SSH_OPTS=""
PLAK_RT_REMOTE=""
PLAK_RT_REMOTE_FILES=""

plak_remote_track_file() {
    local quoted="$1"
    if [ -n "$PLAK_RT_REMOTE_FILES" ]; then
        PLAK_RT_REMOTE_FILES="$PLAK_RT_REMOTE_FILES $quoted"
    else
        PLAK_RT_REMOTE_FILES="$quoted"
    fi
}

plak_remote_transfer_cleanup() {
    [ -n "${PLAK_RT_REMOTE_FILES:-}" ] || return 0
    [ -n "${PLAK_RT_REMOTE:-}" ] || return 0
    # shellcheck disable=SC2086 # ssh options are intentionally word-split
    if ! ssh $PLAK_RT_SSH_OPTS "$PLAK_RT_REMOTE" "rm -f $PLAK_RT_REMOTE_FILES" 2>/dev/null; then
        echo "Warning: could not remove remote temporary files on $PLAK_RT_REMOTE. Remove them manually: $PLAK_RT_REMOTE_FILES" >&2
    fi
}

# Source: shared/site/runtime
#!/bin/bash

# ====================================================
#  Plak - Main Script
#  Contains global configurations, helper functions,
#  and the main command routing logic.
# ====================================================

# Ensure Homebrew/user bin dirs are on PATH. Callers like launchd and
# systemd hand down a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin), which
# means the dashboard's shell_exec of plak fails to find gum/wp/frankenphp.
# /home/linuxbrew/.linuxbrew/bin and ~/.linuxbrew/bin cover Homebrew on Linux.
# Append (don't prepend) so an explicit PATH keeps its priority; we only supply
# entries that are missing, and only for dirs that actually exist.
# PLAK_NO_PATH_PRELUDE=1 disables the addition for hermetic tests.
if [ "${PLAK_NO_PATH_PRELUDE:-0}" != "1" ]; then
    for _plak_site_bin in /opt/homebrew/bin /home/linuxbrew/.linuxbrew/bin "$HOME/.linuxbrew/bin" /usr/local/bin /usr/local/sbin "$HOME/.local/bin"; do
        if [ -d "$_plak_site_bin" ] && [[ ":$PATH:" != *":$_plak_site_bin:"* ]]; then
            PATH="$PATH:$_plak_site_bin"
        fi
    done
fi
unset _plak_site_bin
export PATH

# --- OS & Package Manager Detection ---
OS=""
PKG_MANAGER=""
SUDO_CMD="sudo"
IS_WSL=false
BIN_DIR="/usr/local/bin"

setup_environment() {
    local os_name
    os_name=$(uname -s)

    # --- Check for MacOS ---
    if [ "$os_name" = "Darwin" ]; then
        OS="macos"
        PKG_MANAGER="brew"
        SUDO_CMD=""

        # Architecture detection for MacOS Homebrew paths
        if [ "$(uname -m)" = "arm64" ]; then
            BIN_DIR="/opt/homebrew/bin"
        else
            BIN_DIR="/usr/local/bin"
        fi

        return 0 # Success, exit function
    fi

    # --- Check for Linux ---
    if [ "$os_name" = "Linux" ]; then
        OS="linux"
        BIN_DIR="/usr/local/bin" # Standard for Linux

        # Check if running in WSL
        if grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null; then
            IS_WSL=true
        fi

        if [ ! -f /etc/os-release ]; then
            echo "❌ ERROR: Cannot detect Linux distribution." >&2
            exit 1
        fi
        # shellcheck source=/dev/null
        . /etc/os-release
        if [[ "$ID" == "ubuntu" || "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]; then
            PKG_MANAGER="apt"
        elif [[ "$ID" == "fedora" || "$ID" == "centos" || "$ID" == "rhel" || "$ID_LIKE" == *"fedora"* || "$ID_LIKE" == *"rhel"* ]]; then
            PKG_MANAGER="dnf"
        else
            echo "❌ ERROR: Unsupported Linux distribution: $ID." >&2
            echo "Supported: Ubuntu, Debian, Fedora, CentOS, RHEL and derivatives." >&2
            exit 1
        fi

        if [ "$(id -u)" -eq 0 ]; then
            SUDO_CMD=""
        fi
        return 0 # Success, exit function
    fi

    # --- If neither of the above, it's an unsupported OS ---
    echo "❌ ERROR: Unsupported OS: $os_name" >&2
    exit 1
}

setup_environment
# --- End OS Detection ---

# --- Configuration ---
PLAK_SITE_DIR="$HOME/Plak"
CONFIG_FILE="$PLAK_SITE_DIR/config"
CADDYFILE_PATH="$PLAK_SITE_DIR/Caddyfile"
PHP_INI_FILE="$PLAK_SITE_DIR/php.ini"

APP_DIR="$PLAK_SITE_DIR/App"
SITES_DIR="$PLAK_SITE_DIR/Sites"
LOGS_DIR="$PLAK_SITE_DIR/Logs"

# App Sub-directories
GUI_DIR="$APP_DIR/gui"
ADMINER_DIR="$APP_DIR/adminer"
CUSTOM_CADDY_DIR="$APP_DIR/directives"

PROTECTED_NAMES="plak"
CADDY_CMD="frankenphp"

# Note: BIN_DIR is set in setup_environment() based on OS and architecture

# Export PHPRC so every PHP invocation (frankenphp php-cli, frankenphp -r, and
# any nested wp-cli call) picks up our memory_limit / display_errors / error
# reporting overrides from $PHP_INI_FILE. The file is written by plak install;
# until then PHPRC points at a non-existent path, which PHP silently ignores.
export PHPRC="$PHP_INI_FILE"

# --- Port Configuration ---
# Defaults; overridden by HTTP_PORT/HTTPS_PORT/DB_PORT entries in $CONFIG_FILE if present.
HTTP_PORT=80
HTTPS_PORT=443
DB_HOST=127.0.0.1
DB_PORT=3306
if [ -f "$CONFIG_FILE" ]; then
    _plak_site_saved_http=$(grep '^HTTP_PORT=' "$CONFIG_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "'\"" || true)
    _plak_site_saved_https=$(grep '^HTTPS_PORT=' "$CONFIG_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "'\"" || true)
    _plak_site_saved_db_host=$(grep '^DB_HOST=' "$CONFIG_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "'\"" || true)
    _plak_site_saved_db_port=$(grep '^DB_PORT=' "$CONFIG_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "'\"" || true)
    [ -n "$_plak_site_saved_http" ] && HTTP_PORT="$_plak_site_saved_http"
    [ -n "$_plak_site_saved_https" ] && HTTPS_PORT="$_plak_site_saved_https"
    [ -n "$_plak_site_saved_db_host" ] && DB_HOST="$_plak_site_saved_db_host"
    [ -n "$_plak_site_saved_db_port" ] && DB_PORT="$_plak_site_saved_db_port"
    unset _plak_site_saved_http _plak_site_saved_https _plak_site_saved_db_host _plak_site_saved_db_port
fi

# Returns ":8453" when HTTPS_PORT is non-default, otherwise empty.
https_port_suffix() {
    if [ "$HTTPS_PORT" = "443" ]; then
        echo ""
    else
        echo ":$HTTPS_PORT"
    fi
}

# Builds https URL with port suffix when non-default (e.g. "https://foo.localhost:8453").
url_for() {
    echo "https://${1}$(https_port_suffix)"
}

# Wraps a displayed URL with an OSC 8 hyperlink. The visible text remains the
# plain URL, so unsupported terminals still show a usable URL. Set
# PLAK_TERMINAL_LINKS=0 to force plain text only.
plak_terminal_link() {
    local url="$1" label="${2:-$1}"
    if [ "${PLAK_TERMINAL_LINKS:-1}" != "0" ]; then
        printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$url" "$label"
    else
        printf '%s' "$label"
    fi
}

# Display-only URL helper. Keep url_for plain because scripts use it for curl,
# wp-cli, config files, and other non-terminal contexts.
display_url_for() {
    local url
    url=$(url_for "$1")
    plak_terminal_link "$url"
}

# Idempotent config writer: replaces any existing KEY= line before appending.
config_set() {
    local key="$1" val="$2"
    mkdir -p "$(dirname "$CONFIG_FILE")"
    local tmp
    tmp=$(mktemp)
    if [ -f "$CONFIG_FILE" ]; then
        grep -v "^${key}=" "$CONFIG_FILE" > "$tmp" 2>/dev/null || true
    fi
    echo "${key}='${val}'" >> "$tmp"
    mv "$tmp" "$CONFIG_FILE"
}

# Emit a base64-encoded random password. Uses openssl when present, falls
# back to /dev/urandom otherwise — Fedora Workstation doesn't ship openssl
# in its base install, and a missing openssl used to yield an empty $db_pass
# that then became a MariaDB user with *no* password.
plak_site_random_password() {
    local bytes="${1:-16}"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 "$bytes"
    else
        head -c "$bytes" /dev/urandom | base64 | tr -d '\n'
    fi
}

# Reads a directive from ~/Plak/php.ini (last-wins, ini-style), trims
# surrounding whitespace/quotes, and returns the fallback if the key is
# missing or the ini file doesn't exist yet. Used by regenerate_caddyfile
# so plak memory set only needs to edit one source of truth.
plak_site_ini_get() {
    local key="$1" fallback="$2" val=""
    if [ -f "$PHP_INI_FILE" ]; then
        val=$(awk -F= -v key="$key" '
            { k=$1; gsub(/^[ \t]+|[ \t]+$/, "", k)
              if(k==key) value=substr($0,index($0,"=")+1) }
            END {gsub(/"/, "", value); gsub(/^[ \t]+|[ \t]+$/, "", value); print value}
        ' "$PHP_INI_FILE")
    fi
    echo "${val:-$fallback}"
}

# Reads KEY from ~/Plak/config (last-wins, quotes trimmed) and returns the
# fallback when missing. Avoids sourcing the file so callers can read one
# setting without clobbering their own environment.
plak_config_get() {
    local key="$1" fallback="${2:-}" val=""
    if [ -f "$CONFIG_FILE" ]; then
        val=$(grep -E "^${key}=" "$CONFIG_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "'\"")
    fi
    echo "${val:-$fallback}"
}

# Returns the process name(s) listening on $1 for display purposes, or empty
# if the process isn't visible (e.g. owned by another uid on macOS). Do NOT
# use this for availability checks — use port_is_free for that.
port_listening_app() {
    local port="$1"
    if command -v lsof &>/dev/null; then
        lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null \
            | awk 'NR>1 {print $1}' | sort -u | paste -sd, -
    elif command -v ss &>/dev/null; then
        ss -tlnH "sport = :$port" 2>/dev/null \
            | grep -oE 'users:\(\("[^"]+"' | sed 's/.*"\(.*\)"$/\1/' \
            | sort -u | paste -sd, -
    fi
}

# True when nothing is accepting connections on $1. Uses bash /dev/tcp so it
# works regardless of who owns the listener (lsof is uid-scoped on macOS and
# cannot see root-owned sockets from a regular user). Probes both IPv4 and
# IPv6 loopback because some servers (e.g. Python's http.server) bind v6-only
# by default and the v4 probe alone would miss them.
port_is_free() {
    local port="$1"
    if (exec 3<>/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then
        return 1
    fi
    if (exec 3<>/dev/tcp/::1/"$port") 2>/dev/null; then
        return 1
    fi
    return 0
}

# True if the process listening on $1 is one of our own services (Caddy /
# FrankenPHP). Used so reinstalls don't flag their own services as conflicts.
port_is_own() {
    local app
    app=$(port_listening_app "$1")
    [ -n "$app" ] && { [[ "$app" == *"$CADDY_CMD"* ]] || [[ "$app" == *frankenph* ]]; }
}

# True when a MariaDB/MySQL server answers on $1. Connect rather than inspect
# the process: without root, lsof/ss cannot see a server owned by another uid
# (the apt MariaDB runs as the `mysql` user), so a process-name check would
# misread our own database as a foreign conflict. `mysqladmin ping` works for
# any reachable server and is the same probe the install readiness loop uses.
db_port_is_mariadb() {
    local port="$1"
    command -v mysqladmin >/dev/null 2>&1 || return 1
    mysqladmin -h 127.0.0.1 -P "$port" ping --silent >/dev/null 2>&1
}

# True if $1 is occupied by something that isn't one of our own services.
port_has_conflict() {
    port_is_free "$1" && return 1
    port_is_own "$1" && return 1
    return 0
}

next_free_port() {
    local candidate="${1:-1024}"
    while [ "$candidate" -le 65535 ]; do
        if ! port_has_conflict "$candidate"; then
            echo "$candidate"
            return 0
        fi
        candidate=$((candidate + 1))
    done
    return 1
}

db_port_has_conflict() {
    local port="$1" app=""
    port_is_free "$port" && return 1

    # The configured port answering as MariaDB is our own database, regardless
    # of whether we can name its process without root (apt MariaDB runs as the
    # `mysql` user, invisible to lsof/ss for a non-root caller).
    if [ "$port" = "${DB_PORT:-3306}" ] && db_port_is_mariadb "$port"; then
        return 1
    fi

    app=$(port_listening_app "$port")
    if [ -n "$app" ]; then
        [[ "$app" == *mariadbd* || "$app" == *mysqld* || "$app" == *mariadb* ]] && return 1
    fi

    return 0
}

# Interactive prompt that asks for HTTP and HTTPS ports, validates each, and
# re-prompts until both are free. Sets HTTP_PORT / HTTPS_PORT globals on
# success. Called by the install and plak ports flows.
prompt_custom_ports() {
    local suggest_http="${1:-8090}" suggest_https="${2:-8453}"
    local candidate
    while true; do
        candidate=$(gum input --value "$suggest_http" --prompt "HTTP port: ")
        if [[ ! "$candidate" =~ ^[0-9]+$ ]] || [ "$candidate" -lt 1 ] || [ "$candidate" -gt 65535 ]; then
            gum style --foreground red "   ❌ Invalid port number."
            continue
        fi
        if port_has_conflict "$candidate"; then
            gum style --foreground red "   ❌ Port $candidate is in use by: $(port_listening_app "$candidate")"
            suggest_http=$(next_free_port "$((candidate + 1))" || echo "$suggest_http")
            continue
        fi
        HTTP_PORT="$candidate"
        break
    done
    while true; do
        candidate=$(gum input --value "$suggest_https" --prompt "HTTPS port: ")
        if [[ ! "$candidate" =~ ^[0-9]+$ ]] || [ "$candidate" -lt 1 ] || [ "$candidate" -gt 65535 ]; then
            gum style --foreground red "   ❌ Invalid port number."
            continue
        fi
        if [ "$candidate" = "$HTTP_PORT" ]; then
            gum style --foreground red "   ❌ HTTPS port must differ from HTTP port."
            continue
        fi
        if port_has_conflict "$candidate"; then
            gum style --foreground red "   ❌ Port $candidate is in use by: $(port_listening_app "$candidate")"
            suggest_https=$(next_free_port "$((candidate + 1))" || echo "$suggest_https")
            continue
        fi
        HTTPS_PORT="$candidate"
        break
    done
}

# Reconfigure an existing MariaDB server to listen on DB_PORT. Not called by
# `plak install` (it would rewrite a system/Homebrew-managed config); kept as
# the basis for an explicit port-change command. See the CLI ticket for it.
plak_site_configure_mariadb_port() {
    DB_HOST="${DB_HOST:-127.0.0.1}"
    DB_PORT="${DB_PORT:-3306}"
    config_set DB_HOST "$DB_HOST"
    config_set DB_PORT "$DB_PORT"

    if [ "$OS" = "macos" ] && command -v brew >/dev/null 2>&1; then
        local brew_prefix mariadb_conf_dir mariadb_conf_file mariadb_socket
        brew_prefix=$(brew --prefix)
        mariadb_conf_dir="$brew_prefix/etc/my.cnf.d"
        mariadb_conf_file="$mariadb_conf_dir/plak.cnf"
        mariadb_socket="$PLAK_SITE_DIR/mariadb.sock"
        mkdir -p "$mariadb_conf_dir"
        if [ ! -f "$brew_prefix/etc/my.cnf" ]; then
            printf '!includedir %s\n' "$mariadb_conf_dir" > "$brew_prefix/etc/my.cnf"
        elif ! grep -q "^!includedir $mariadb_conf_dir" "$brew_prefix/etc/my.cnf"; then
            printf '\n!includedir %s\n' "$mariadb_conf_dir" >> "$brew_prefix/etc/my.cnf"
        fi
        cat > "$mariadb_conf_file" <<EOF
[client]
host=$DB_HOST
port=$DB_PORT
socket=$mariadb_socket

[mariadb]
bind-address=$DB_HOST
port=$DB_PORT
socket=$mariadb_socket

[mysqld]
bind-address=$DB_HOST
port=$DB_PORT
socket=$mariadb_socket
EOF
        echo "   - MariaDB configured for $DB_HOST:$DB_PORT ($mariadb_conf_file)"
    elif [ "$OS" = "linux" ]; then
        local mariadb_conf_file="/etc/mysql/mariadb.conf.d/99-plak.cnf"
        if [ ! -d "$(dirname "$mariadb_conf_file")" ]; then
            mariadb_conf_file="/etc/my.cnf.d/plak.cnf"
        fi
        $SUDO_CMD mkdir -p "$(dirname "$mariadb_conf_file")"
        printf '[client]\nhost=%s\nport=%s\n\n[mariadb]\nbind-address=%s\nport=%s\n\n[mysqld]\nbind-address=%s\nport=%s\n' \
            "$DB_HOST" "$DB_PORT" "$DB_HOST" "$DB_PORT" "$DB_HOST" "$DB_PORT" \
            | $SUDO_CMD tee "$mariadb_conf_file" >/dev/null
        echo "   - MariaDB configured for $DB_HOST:$DB_PORT ($mariadb_conf_file)"
    fi
}

# Build the https:// URL for a hostname given an HTTPS port. Omits the port
# suffix when $2 equals 443 so stored URLs match the "no suffix" form.
port_url_for() {
    local host="$1" port="$2"
    if [ "$port" = "443" ]; then
        echo "https://$host"
    else
        echo "https://$host:$port"
    fi
}

# Walk every WordPress site under $SITES_DIR and run wp search-replace to
# migrate stored URLs from OLD_HTTPS port to NEW_HTTPS port. Updates each
# hostname the site answers on (base + entries in site/mappings) so custom
# mappings don't get left stale. Pass "--dry-run" as the third argument to
# preview replacement counts without committing.
#
# No-op if OLD_HTTPS == NEW_HTTPS or if $SITES_DIR has no WordPress sites.
# Returns non-zero if any hostname migration fails. Per-host errors include
# the original WP-CLI output and are summarised at the end.
update_wp_site_urls_for_port_change() {
    local old_https="$1" new_https="$2" dry_run_flag="${3:-}"
    local dry_run=false
    [ "$dry_run_flag" = "--dry-run" ] && dry_run=true

    [ "$old_https" = "$new_https" ] && return 0
    [ -d "$SITES_DIR" ] || return 0

    local wp_cmd
    wp_cmd=$(get_wp_cmd)

    local total_sites=0 updated_sites=0 failed_hosts=0
    local site_path site_name hostname mapping old_url new_url
    local -a hostnames

    for site_path in "$SITES_DIR"/*; do
        [ -d "$site_path" ] || continue
        [ -f "$site_path/public/wp-config.php" ] || continue
        total_sites=$((total_sites + 1))
        site_name=$(basename "$site_path")

        hostnames=("$site_name")
        if [ -f "$site_path/mappings" ]; then
            while IFS= read -r mapping || [ -n "$mapping" ]; do
                [ -n "$mapping" ] && hostnames+=("$mapping")
            done < "$site_path/mappings"
        fi

        local any_updated=false
        for hostname in "${hostnames[@]}"; do
            old_url=$(port_url_for "$hostname" "$old_https")
            new_url=$(port_url_for "$hostname" "$new_https")
            [ "$old_url" = "$new_url" ] && continue

            local -a sr_args
            sr_args=(--all-tables --skip-plugins --skip-themes --format=count)
            $dry_run && sr_args+=(--dry-run)

            local output rc count
            output=$( (cd "$site_path/public" && $wp_cmd search-replace "$old_url" "$new_url" "${sr_args[@]}") 2>&1 )
            rc=$?
            if [ $rc -eq 0 ]; then
                count=$(echo "$output" | tr -d '[:space:]')
                [[ "$count" =~ ^[0-9]+$ ]] || count=0
                if $dry_run; then
                    echo "   • ${hostname}: would replace ${count} occurrence(s)"
                else
                    echo "   • ${hostname}: replaced ${count} occurrence(s)"
                fi
                any_updated=true
            else
                gum style --foreground red "   ❌ ${hostname}: search-replace failed"
                if [ -n "$output" ]; then
                    while IFS= read -r error_line || [ -n "$error_line" ]; do
                        printf '      %s\n' "$error_line" >&2
                    done <<< "$output"
                fi
                failed_hosts=$((failed_hosts + 1))
            fi
        done
        $any_updated && updated_sites=$((updated_sites + 1))
    done

    echo ""
    if $dry_run; then
        echo "🔍 Dry run: $updated_sites of $total_sites WordPress site(s) would be updated."
    else
        echo "📊 $updated_sites of $total_sites WordPress site(s) updated."
    fi
    if [ $failed_hosts -gt 0 ]; then
        gum style --foreground yellow "⚠️  $failed_hosts hostname replacement(s) failed."
        return 1
    fi
    return 0
}

# --- Whoops Bootstrap Generation ---
create_whoops_bootstrap() {
    echo "📜 Creating Whoops bootstrap file..."
    cat > "$APP_DIR/whoops_bootstrap.php" << 'EOM'
<?php
// This script is automatically included before any other PHP script.
// It registers a simple PSR-4 autoloader for the Whoops library.

spl_autoload_register(function ($class) {
    $prefix = 'Whoops\\';
    $base_dir = __DIR__ . '/whoops/src/Whoops/';

    $len = strlen($prefix);
    if (strncmp($prefix, $class, $len) !== 0) {
        return;
    }

    $relative_class = substr($class, $len);
    $file = $base_dir . str_replace('\\', '/', $relative_class) . '.php';

    if (file_exists($file)) {
        require $file;
    }
});

$whoops = new \Whoops\Run;

// We want to see all errors *except* for the noisy Deprecated and Notice warnings,
// which are common with older plugins on modern PHP.
// E_USER_NOTICE is used by WordPress's _doing_it_wrong() function.
// E_USER_WARNING is triggered by WP_HTTP (wp_version_check, update checks, API
// calls) whenever a request to api.wordpress.org or a plugin update endpoint
// fails — e.g. on first wp-admin load before background crons settle, or on a
// fresh install without system CA certs. That's a transient runtime condition,
// not a bug to page on; leave it in the error log and let WordPress replakr.
$whoops->silenceErrorsInPaths(
    '/.*/', // A regex that matches all file paths
    E_DEPRECATED | E_USER_DEPRECATED | E_NOTICE | E_USER_NOTICE | E_USER_WARNING
);

// The PrettyPageHandler will now only be triggered for fatal errors.
$whoops->pushHandler(new \Whoops\Handler\PrettyPageHandler);
$whoops->register();
EOM
}

# --- Helper Functions ---

# Inject the mu-plugin for one-time logins
inject_mu_plugin() {
    local public_dir="$1"
    if [ -z "$public_dir" ] || [ ! -d "$public_dir" ]; then
        return 1 # Exit if no valid directory is provided
    fi

    # Heredoc containing the mu-plugin code
read -r -d '' build_mu_plugin << 'heredoc'
<?php
/**
 * Plugin Name: Plak CLI Helper
 * Plugin URI: https://github.com/plakio/plak-cli
 * Description: Collection of helper functions for Plak CLI (one-time logins, dynamic siteurl, auto-update email silencing).
 * Version: 0.5.0
 * Author: Plak
 * Author URI: https://github.com/plakio/plak-cli
 * Text Domain: plak-cli-helper
 */

/**
 * Lifetime of a one-time login link, in seconds. Links are local-development
 * credentials, so they stay short-lived even though they are single-use.
 */
if ( ! defined( 'PLAK_LOGIN_TOKEN_TTL' ) ) {
	define( 'PLAK_LOGIN_TOKEN_TTL', 900 );
}

/**
 * Store a fresh one-time login token for a user. The stored value carries its
 * own expiry so a link cannot outlive PLAK_LOGIN_TOKEN_TTL even if it is never
 * consumed.
 */
function plak_cli_store_login_token( $user_id, $token ) {
	update_user_meta( $user_id, 'plak_site_login_token', ( time() + PLAK_LOGIN_TOKEN_TTL ) . '|' . $token );
}

/**
 * Read a stored one-time login token. Returns [ token, expires ] or null.
 * Tokens written by older Plak versions had no expiry; they are rejected so a
 * link minted before the upgrade cannot be replayed indefinitely.
 */
function plak_cli_read_login_token( $user_id ) {
	$raw = (string) get_user_meta( $user_id, 'plak_site_login_token', true );
	if ( $raw === '' || strpos( $raw, '|' ) === false ) {
		return null;
	}
	[ $exp, $token ] = explode( '|', $raw, 2 );
	if ( ! ctype_digit( $exp ) || $token === '' ) {
		return null;
	}
	return [ $token, (int) $exp ];
}

/**
 * Build a one-time login URL for a user, storing a fresh token.
 */
function plak_cli_build_login_url( $user ) {
	// Short token: sha1 is 40 hex chars; 7 is still 16^7 ≈ 268M combinations,
	// plenty for a one-time-use local-dev login link, and short enough to fit
	// a narrow terminal without wrapping.
	$token = substr( sha1( wp_generate_password() ), 0, 7 );
	plak_cli_store_login_token( $user->ID, $token );
	return add_query_arg(
		[
			'user_id'               => $user->ID,
			'plak_site_login_token' => $token,
		],
		wp_login_url()
	);
}

/**
 * Registers AJAX callback for quick logins
 */
function plak_cli_quick_login_action_callback() {

	$post = json_decode( file_get_contents( 'php://input' ) );
	// Error if token not valid
	if ( ! isset( $post->token ) || $post->token != md5( AUTH_KEY ) ) {
		return new WP_Error( 'token_invalid', 'Invalid Token', [ 'status' => 404 ] );
		wp_die();
	}

	$post->user_login = str_replace( "%20", " ", $post->user_login );
	$user     = get_user_by( 'login', $post->user_login );

	$one_time_url = plak_cli_build_login_url( $user );

	echo $one_time_url;
	wp_die();

}

add_action( 'wp_ajax_nopriv_plak_cli_quick_login', 'plak_cli_quick_login_action_callback' );
/**
 * Login a request in as a user if the token is valid.
 */
function plak_cli_login_handle_token() {

	global $pagenow;
	if ( 'wp-login.php' !== $pagenow || empty( $_GET['user_id'] ) || empty( $_GET['plak_site_login_token'] ) ) {
		return;
	}

	if ( is_user_logged_in() ) {
		$error = sprintf( __( 'Invalid one-time login token, but you are logged in as \'%1$s\'. <a href="%2$s">Go to the dashboard instead</a>?', 'plak-cli-helper' ), wp_get_current_user()->user_login, admin_url() );
	} else {
		$error = sprintf( __( 'Invalid one-time login token. <a href="%s">Try signing in instead</a>?', 'plak-cli-helper' ), wp_login_url() );
	}

	// Use a generic error message to ensure user ids can't be sniffed
	$user = get_user_by( 'id', (int) $_GET['user_id'] );
	if ( ! $user ) {
		wp_die( $error );
	}

	$stored   = plak_cli_read_login_token( $user->ID );
	$is_valid = false;
	if ( $stored && time() <= $stored[1] && hash_equals( $stored[0], $_GET['plak_site_login_token'] ) ) {
		$is_valid = true;
	}

	if ( ! $is_valid ) {
		wp_die( $error );
	}

	delete_user_meta( $user->ID, 'plak_site_login_token' );
	wp_set_auth_cookie( $user->ID, 1 );
	wp_safe_redirect( admin_url() );
	exit;
}

add_action( 'init', 'plak_cli_login_handle_token' );

if (defined('WP_CLI') && WP_CLI) {

    /**
     * Generates a one-time login link for a user based on user ID, email, or login.
     *
     * ## OPTIONS
     *
     * <user_identifier>
     * : The user ID, email, or login of the user to generate the login link for.
     *
     * ## EXAMPLES
     *
     * wp user login 123
     * wp user login user@example.com
     * wp user login myusername
     *
     * @param array $args The command arguments.
     */
    function plak_cli_generate_login_link( $args ) {

        $user_identifier = $args[0];
        // Determine if the identifier is a user ID, email, or login
        if (is_numeric($user_identifier)) {
            $user = get_user_by('ID', $user_identifier);
        } elseif (is_email($user_identifier)) {
            $user = get_user_by('email', $user_identifier);
        } else {
            $user = get_user_by('login', $user_identifier);
        }

        // Check if the user exists
        if (!$user) {
            WP_CLI::error("User not found: $user_identifier");
            return;
        }

        // Output the one-time URL to the CLI. The token carries its own expiry.
        WP_CLI::log( plak_cli_build_login_url( $user ) );
    }

    WP_CLI::add_command( 'user login', 'plak_cli_generate_login_link' );
}

/**
 * Disable auto-update email notifications for plugins.
 */
add_filter( 'auto_plugin_update_send_email', '__return_false' );

/**
 * Disable auto-update email notifications for themes.
 */
add_filter( 'auto_theme_update_send_email', '__return_false' );

/**
 * Dynamic URL override for Tailscale/LAN/Share access.
 * When accessed via a non-localhost domain, override home and siteurl
 * to use the current host so CSS/JS/images load correctly.
 */
if ( ! function_exists( 'plak_cli_maybe_override_site_url' ) ) {
function plak_cli_maybe_override_site_url( $value ) {
    if ( is_multisite() ) {
        return $value; // Never collapse a network to a LAN/share host.
    }
    // Only run in front-end context with a valid HTTP_HOST
    if ( defined( 'WP_CLI' ) && WP_CLI ) {
        return $value;
    }

    $host = isset( $_SERVER['HTTP_HOST'] ) ? $_SERVER['HTTP_HOST'] : '';

    // Skip if no host or if it ends with .localhost (normal local access)
    if ( empty( $host ) || preg_match( '/\.localhost(:\d+)?$/', $host ) ) {
        return $value;
    }

    // Override to current host for Tailscale, LAN, or public share access
    $scheme = ( ! empty( $_SERVER['HTTPS'] ) && $_SERVER['HTTPS'] !== 'off' ) ? 'https' : 'http';
    return $scheme . '://' . $host;
}
}
add_filter( 'option_home', 'plak_cli_maybe_override_site_url' );
add_filter( 'option_siteurl', 'plak_cli_maybe_override_site_url' );
heredoc

    local mu_plugins_dir="$public_dir/wp-content/mu-plugins"
    mkdir -p "$mu_plugins_dir" || return 1
    printf '%s\n' "$build_mu_plugin" > "$mu_plugins_dir/plak-cli-helper.php" || return 1
    echo "   - ✅ Injected one-time login MU-plugin."
}

# Write a Plak-branded landing index.php into a plain site's public dir.
# The heredoc below is the user's PHP — it reads $_SERVER['HTTP_HOST'] and
# __FILE__ at request time, so it self-identifies wherever it's served from.
write_plain_site_landing() {
    local public_dir="$1"
    if [ -z "$public_dir" ] || [ ! -d "$public_dir" ]; then
        return 1
    fi

read -r -d '' build_landing << 'LANDING_EOF'
<?php
$host = $_SERVER['HTTP_HOST'] ?? 'localhost';
$file = __FILE__;
$dir  = dirname(__FILE__);
$home = getenv('HOME') ?: '';
$display_dir = ($home && str_starts_with($dir, $home)) ? '~' . substr($dir, strlen($home)) : $dir;
?><!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark light">
<title>Plak CLI</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'><rect width='64' height='64' rx='12' fill='%232f36fa'/><text x='32' y='46' text-anchor='middle' font-family='Arial,sans-serif' font-size='42' font-weight='700' fill='white'>P</text></svg>">
<link href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,400..600;1,9..144,400..600&family=Geist:wght@400;500;600&family=Geist+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
:root {
  --bg: #fbfaf7; --bg-elev: #ffffff; --bg-sunk: #f4f2ec;
  --border: #e8e4da; --text: #1a1c1b; --text-soft: #3a3d3a;
  --muted: #6b6f6a; --dim: #9a9d97;
  /* sRGB fallback first; the oklch override on the next line is ignored by
     browsers without oklch() support (Firefox <113, Chrome <111, Safari <16.4)
     so the hex value wins — otherwise the whole declaration would be invalid
     and --accent would fall back to its initial value (unset). */
  --accent: #2f36fa;       --accent-ink: #1c4c58;
  --accent: oklch(55% 0.18 255); --accent-ink: oklch(35% 0.08 190);
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0f1210; --bg-elev: #161a17; --bg-sunk: #0b0e0c;
    --border: #252925; --text: #edeee9; --text-soft: #c6c9c1;
    --muted: #8a8e85; --dim: #5d615a;
    --accent: #2f36fa;       --accent-ink: #83d2e0;
    --accent: oklch(70% 0.15 255); --accent-ink: oklch(82% 0.10 190);
  }
}
html { background: var(--bg); }
body {
  font-family: 'Geist', -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
  color: var(--text); background: var(--bg);
  min-height: 100vh; display: grid; place-items: center;
  padding: 2rem; -webkit-font-smoothing: antialiased;
  font-feature-settings: "ss01", "cv11";
}
main { max-width: 560px; text-align: center; }
.mark { width: 56px; height: 56px; margin: 0 auto 1.75rem; display: block; }
h1 {
  font-family: 'Fraunces', 'Times New Roman', serif;
  font-style: italic; font-weight: 500;
  font-size: clamp(2.25rem, 5vw, 3.25rem);
  letter-spacing: -0.025em; line-height: 1.02;
  margin-bottom: 0.55rem;
}
.host {
  font-family: 'Geist Mono', ui-monospace, 'SF Mono', Menlo, monospace;
  font-size: 0.9rem; color: var(--muted); margin-bottom: 1.75rem;
}
p { color: var(--text-soft); line-height: 1.55; font-size: 1.02rem; margin-bottom: 1rem; }
.path {
  display: inline-block;
  font-family: 'Geist Mono', ui-monospace, 'SF Mono', Menlo, monospace;
  font-size: 0.82rem;
  padding: 0.45rem 0.8rem;
  background: var(--bg-sunk); border: 1px solid var(--border);
  border-radius: 7px; color: var(--text-soft);
  margin: 0.25rem 0 2rem; word-break: break-all;
}
.actions { display: inline-flex; gap: 0.5rem; flex-wrap: wrap; justify-content: center; }
.pill {
  display: inline-flex; align-items: center; gap: 0.45em;
  padding: 0.55rem 1.05rem; border-radius: 999px;
  border: 1px solid var(--border);
  background: var(--bg-elev); color: var(--text-soft);
  font-family: 'Geist Mono', ui-monospace, 'SF Mono', Menlo, monospace;
  font-size: 0.85rem; text-decoration: none;
  transition: border-color 120ms, color 120ms, background 120ms;
}
.pill:hover { border-color: var(--accent); color: var(--accent-ink); background: var(--bg-sunk); }
.pill.primary { background: var(--accent); border-color: var(--accent); color: #0a1a1c; }
.pill.primary:hover { filter: brightness(1.08); background: var(--accent); color: #0a1a1c; }
footer {
  margin-top: 3rem;
  font-family: 'Geist Mono', ui-monospace, 'SF Mono', Menlo, monospace;
  font-size: 0.72rem; color: var(--dim); letter-spacing: 0.05em;
}
footer a { color: var(--muted); text-decoration: none; border-bottom: 1px solid var(--border); }
footer a:hover { color: var(--text); }
</style>
</head>
<body>
<main>
  <svg class="mark" viewBox="0 0 64 64" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <defs><clipPath id="c"><circle cx="32" cy="32" r="28"/></clipPath></defs>
    <g clip-path="url(#c)">
      <rect width="64" height="64" fill="#f6f1e8"/>
      <rect y="32" width="64" height="32" fill="#2f36fa"/>
      <path d="M 4 32 C 4 22, 12 12, 22 12 C 30 12, 34 18, 42 16 C 50 14, 58 18, 60 24 L 60 32 Z" fill="#8bb382"/>
      <line x1="2" y1="32" x2="62" y2="32" stroke="#1c4c58" stroke-width="2.5" fill="none"/>
      <g stroke="#1c4c58" stroke-width="2.6" fill="none">
        <path d="M 10 42 Q 18 38, 26 42 T 42 42 T 56 42"/>
        <path d="M 14 50 Q 22 46, 30 50 T 46 50 T 56 50"/>
      </g>
    </g>
    <circle cx="32" cy="32" r="28" stroke="#1c4c58" stroke-width="3" fill="none"/>
  </svg>
  <h1>Hello.</h1>
  <div class="host"><?= htmlspecialchars($host) ?></div>
  <p>Your site is ready. Start building by editing files in:</p>
  <div class="path"><?= htmlspecialchars($display_dir) ?></div>
  <div class="actions">
    <a class="pill primary" href="https://plak.localhost/">Plak dashboard</a>
    <a class="pill" href="https://plak.sh/" target="_blank" rel="noopener">plak.sh ↗</a>
  </div>
  <footer>Served by <a href="https://plak.sh" target="_blank" rel="noopener">Plak</a></footer>
</main>
</body>
</html>
LANDING_EOF

    printf '%s\n' "$build_landing" > "$public_dir/index.php" || return 1
    echo "   - ✅ Wrote Plak landing page."
}

# Load configuration from ~/Plak/config
source_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        DB_HOST="${DB_HOST:-127.0.0.1}"
        DB_PORT="${DB_PORT:-3306}"
    else
        echo "❌ Error: Plak config file not found. Please run 'plak install'."
        exit 1
    fi
}

# Function to check for required dependencies
check_dependencies() {
    # Check for Caddy/FrankenPHP
    if ! command -v "$CADDY_CMD" &> /dev/null && ! [ -x "$CADDY_CMD" ]; then
        gum style --foreground red "❌ Caddy/FrankenPHP not found. Please run 'plak install'."
        exit 1
    fi

    # Check for other dependencies
    for pkg_cmd in mariadb mailpit "wp:wp-cli" gum; do
        local pkg=${pkg_cmd##*:}
        local cmd=${pkg_cmd%%:*}
        if ! command -v $cmd &> /dev/null; then
            gum style --foreground red "❌ Dependency '$cmd' not found. Please run 'plak install'."
            exit 1
        fi
    done
}

# --- Helper Functions ---

# Compatibility for existing shell callers that expand the result as a
# command. Return a function name, never a space-delimited executable path:
# the function resolves/executes an argv array and preserves paths with spaces.
get_wp_cmd() {
    echo plak_wp_cli
}

# Safely single-quote a value for interpolation into a remote shell command.
# Interior single quotes become the standard '\'' escape sequence, so the
# result can be dropped into ssh "... $(shell_quote "$v") ..." without injection.
shell_quote() {
    printf "'%s'" "${1//\'/\'\\\'\'}"
}

# Helper function to get the correct MariaDB service name on Linux
# Different distros may use 'mariadb', 'mysql', or 'mysqld' as the service name
get_mariadb_service_name() {
    if [ "$OS" == "macos" ]; then
        echo "mariadb"
        return
    fi
    # Check which service name exists on this system
    if systemctl list-unit-files mariadb.service 2>/dev/null | grep -q mariadb; then
        echo "mariadb"
    elif systemctl list-unit-files mysql.service 2>/dev/null | grep -q mysql; then
        echo "mysql"
    elif systemctl list-unit-files mysqld.service 2>/dev/null | grep -q mysqld; then
        echo "mysqld"
    else
        # Default to mariadb
        echo "mariadb"
    fi
}

# Manage /etc/hosts file for local domains
update_etc_hosts() {
    echo "🔎 Checking /etc/hosts for required entries..."

    # An array of all hostnames Plak will manage
    local required_hosts=("plak.localhost" "db.plak.localhost" "mail.plak.localhost")

    # Also find all site-specific hostnames
    if [ -d "$SITES_DIR" ]; then
        for site_path in "$SITES_DIR"/*; do
            if [ -d "$site_path" ]; then
                required_hosts+=("$(basename "$site_path")")

                # Check for additional mappings
                if [ -f "$site_path/mappings" ]; then
                    while IFS= read -r mapping || [ -n "$mapping" ]; do
                        # Skip empty lines
                        if [ -n "$mapping" ]; then
                            required_hosts+=("$mapping")
                        fi
                    done < "$site_path/mappings"
                fi
            fi
        done
    fi

    local missing_hosts=()
    for host in "${required_hosts[@]}"; do
        # Use grep -q to quietly check if the entry exists
        if ! grep -q "127.0.0.1[[:space:]]\+$host" /etc/hosts; then
            missing_hosts+=("$host")
        fi
    done

    if [ ${#missing_hosts[@]} -gt 0 ]; then
        echo "   - Adding missing entries to /etc/hosts (requires sudo)..."
        local entries_to_add=""
        for host in "${missing_hosts[@]}"; do
            entries_to_add+="127.0.0.1 $host\n"
        done

        # Use sudo tee to append all missing entries at once
        echo -e "$entries_to_add" | sudo tee -a /etc/hosts > /dev/null
        echo "   - ✅ Done."
    else
        echo "   - ✅ All entries are present."
    fi
}

# Probe Caddy's admin API to see if the server is running.
# Uses bash's built-in /dev/tcp so we don't depend on nc/curl being installed.
is_caddy_running() {
    (echo > /dev/tcp/127.0.0.1/2019) &>/dev/null && return 0
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:2019 -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 { found = 1 } END { exit found ? 0 : 1 }'
        return $?
    fi
    if command -v ss >/dev/null 2>&1; then
        ss -tlnH "sport = :2019" 2>/dev/null | grep -q .
        return $?
    fi
    return 1
}

# Write the Plak-themed Adminer entry point (index.php with the head() hook
# that injects the theme toggle, plus autologin) and refresh the theme
# assets (adminer.css, adminer.js). Shared by plak_site_install (initial
# deploy) and plak_site_upgrade (so upgraders pick up theme changes without a
# reinstall). Idempotent — overwrites existing files.
deploy_adminer_theme() {
    local adminer_dir="${1:-$ADMINER_DIR}"
    mkdir -p "$adminer_dir"

    echo "⚙️ Writing Adminer entry point..."
    cat > "$adminer_dir/index.php" << 'ADMINER_INDEX_EOF'
<?php
// This is the custom entry point for Adminer with autologin.
function adminer_object() {
    // Adminer 5.x uses the Adminer namespace
    class AdminerPlakLogin extends Adminer\Adminer {
        function name() { return 'Plak CLI DB Manager'; }
        function permanentLogin($i = false) { return "plak-local-development-key"; }
        function credentials() {
            $configFile = getenv('HOME') . '/Plak/config';
            if (file_exists($configFile)) {
                $config = parse_ini_file($configFile);
                $db_user = $config['DB_USER'] ?? null;
                $db_pass = $config['DB_PASSWORD'] ?? null;
                $db_host = $config['DB_HOST'] ?? '127.0.0.1';
                $db_port = $config['DB_PORT'] ?? '3306';
                return [$db_host . ':' . $db_port, $db_user, $db_pass];
            }
            return ['127.0.0.1:3306', null, null];
        }
        function login($login, $password) { return true; }
        function head($title = null) {
            // Inject the Plak theme toggle. Inline init runs before adminer.css
            // applies so the saved choice (or system preference) is honored
            // without a theme flash on load.
            $nonce = \Adminer\nonce();
            $init = "(function(){try{var s=localStorage.getItem('plak-adminer-theme');var t=(s==='dark'||s==='light')?s:(window.matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light');document.documentElement.setAttribute('data-theme',t);}catch(e){}})();";
            echo "<script{$nonce}>{$init}</script>\n";
            $v = @filemtime(__DIR__ . '/adminer.js') ?: 1;
            echo "<script src='adminer.js?v={$v}'{$nonce}></script>\n";
            return true;
        }
    }
    return new AdminerPlakLogin();
}
// Include the original Adminer core file to run the application.
include "./adminer-core.php";
ADMINER_INDEX_EOF

    local script_dir local_theme_dir
    script_dir=$(cd "$(dirname "$0")" && pwd)
    local_theme_dir="$script_dir/adminer-theme"

    if [ -f "$local_theme_dir/adminer.css" ] && [ -f "$local_theme_dir/adminer.js" ]; then
        echo "🎨 Installing local Plak Adminer theme..."
        cp "$local_theme_dir/adminer.css" "$adminer_dir/adminer.css"
        cp "$local_theme_dir/adminer.js" "$adminer_dir/adminer.js"
    else
        echo "🎨 Downloading Plak Adminer theme..."
        curl -sL "https://raw.githubusercontent.com/plakio/plak-cli/main/adminer-theme/adminer.css" -o "$adminer_dir/adminer.css"
        curl -sL "https://raw.githubusercontent.com/plakio/plak-cli/main/adminer-theme/adminer.js"  -o "$adminer_dir/adminer.js"
    fi
}

# Repair ownership of ~/Plak state that a pre-1.10 root-run FrankenPHP may
# have left owned by root. The most user-visible symptom is the size cache
# (~/Plak/cache/site-sizes.json) becoming unwritable — refresh_sizes computes
# correctly, @file_put_contents silently fails, and list_sites returns stale
# nulls. Safe to call repeatedly; only runs chown when the ownership is
# actually wrong. macOS never needs this because launchd runs as the user.
heal_plak_site_state_ownership() {
    [ "$OS" = "linux" ] || return 0
    local uid; uid=$(id -u)
    local gid; gid=$(id -g)
    local target
    for target in "$PLAK_SITE_DIR/cache" "$PLAK_SITE_DIR/.reload.lock" "$PLAK_SITE_DIR/.reload.lock.d" "$PLAK_SITE_DIR/.reload.pending" "$PLAK_SITE_DIR/caddy.pid"; do
        [ -e "$target" ] || continue
        # Cheap short-circuit: only invoke sudo if the top-level is wrong.
        [ "$(stat -c %u "$target" 2>/dev/null)" = "$uid" ] && continue
        $SUDO_CMD -n chown -R "$uid:$gid" "$target" 2>/dev/null || true
    done
}

# (Re)start the Caddy/FrankenPHP service. Safe to call when already running —
# both platforms stop any existing instance first. Called from plak enable
# and from regenerate_caddyfile when Caddy isn't up yet.
start_caddy_service() {
    echo "   - Starting Caddy/FrankenPHP..."
    mkdir -p "$LOGS_DIR"

    if [ "$OS" == "macos" ]; then
        local caddy_plist_path="$PLAK_SITE_DIR/com.plak.caddy.plist"
        local frankenphp_bin
        frankenphp_bin=$(command -v "$CADDY_CMD")

        launchctl unload "$caddy_plist_path" &>/dev/null
        "$CADDY_CMD" stop --config "$CADDYFILE_PATH" &>/dev/null 2>&1

        cat > "$caddy_plist_path" << EOM
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>KeepAlive</key>
        <true/>
        <key>Label</key>
        <string>com.plak.caddy</string>
        <key>ProgramArguments</key>
        <array>
                <string>$frankenphp_bin</string>
                <string>run</string>
                <string>--config</string>
                <string>$CADDYFILE_PATH</string>
                <string>--pidfile</string>
                <string>$PLAK_SITE_DIR/caddy.pid</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>StandardErrorPath</key>
        <string>$LOGS_DIR/caddy-process.log</string>
        <key>StandardOutPath</key>
        <string>$LOGS_DIR/caddy-process.log</string>
</dict>
</plist>
EOM
        launchctl load "$caddy_plist_path"
        launchctl start com.plak.caddy
    fi

    if [ "$OS" == "linux" ]; then
        # v1.10+: Caddy runs as plak.service under systemd (installed by
        # plak_site_enable), so it survives reboots. Prefer systemctl when the
        # unit is present; fall back to an ad-hoc foreground start only if
        # someone invoked this before plak_site_enable wrote the unit.
        if systemctl list-unit-files plak.service &>/dev/null 2>&1 \
            && systemctl cat plak.service &>/dev/null 2>&1; then
            $SUDO_CMD systemctl restart plak.service
        else
            # A pre-1.10 root-owned pidfile would block a user-run start.
            if [ -e "$PLAK_SITE_DIR/caddy.pid" ] && [ ! -w "$PLAK_SITE_DIR/caddy.pid" ]; then
                $SUDO_CMD -n rm -f "$PLAK_SITE_DIR/caddy.pid" 2>/dev/null || true
            fi
            "$CADDY_CMD" stop --config "$CADDYFILE_PATH" &>/dev/null \
                || $SUDO_CMD -n "$CADDY_CMD" stop --config "$CADDYFILE_PATH" &>/dev/null \
                || true
            "$CADDY_CMD" start --config "$CADDYFILE_PATH" --pidfile "$PLAK_SITE_DIR/caddy.pid" >> "$LOGS_DIR/caddy-process.log" 2>&1
        fi
    fi
}

# Function to regenerate the Caddyfile
regenerate_caddyfile() {
    echo "🔄 Regenerating Caddyfile..."
    if ! command -v mailpit &> /dev/null; then
        gum style --foreground red "❌ Mailpit is not installed. Please run 'plak install' successfully first."
        return 1
    fi
    # Ensure the user-owned PHP session dir referenced by the Caddyfile's
    # php_ini session.save_path exists before FrankenPHP tries to use it.
    mkdir -p "$PLAK_SITE_DIR/cache/sessions" 2>/dev/null
    local mailpit_path
    mailpit_path=$(command -v mailpit)

    # Build optional http_port / https_port directives when non-default.
    local port_directives=""
    if [ "$HTTP_PORT" != "80" ]; then
        port_directives+="    http_port $HTTP_PORT"$'\n'
    fi
    if [ "$HTTPS_PORT" != "443" ]; then
        port_directives+="    https_port $HTTPS_PORT"$'\n'
    fi

    # Who may reach the dashboard, Adminer and Mailpit: this machine. Under
    # WSL2's default NAT networking the Windows browser arrives from the virtual
    # adapter's private address, so private ranges are allowed there (mirrored
    # networking arrives as loopback, which is always allowed).
    local local_only='remote_ip 127.0.0.1 ::1'
    [ "$IS_WSL" = true ] && local_only='remote_ip private_ranges'

    # Keep the historical h1 default pending live load evaluation (docs/health.md).
    # HTTP/1.1 always stays enabled if the opt-in setting is used for evaluation.
    local protocols_value="h1"
    if [ "$(plak_config_get HTTP2_ENABLED 0)" = "1" ]; then
        protocols_value="h1 h2"
    fi

    # Write the static header of the Caddyfile
    cat > "$CADDYFILE_PATH" <<- EOM
{
${port_directives}    frankenphp {
        php_ini sendmail_path "$mailpit_path sendmail -t"
        php_ini log_errors On
        php_ini display_errors Off
        php_ini error_log "$LOGS_DIR/errors.log"
        php_ini auto_prepend_file "$APP_DIR/whoops_bootstrap.php"
        php_ini memory_limit $(plak_site_ini_get memory_limit 1G)
        php_ini upload_max_filesize $(plak_site_ini_get upload_max_filesize 1G)
        php_ini post_max_size $(plak_site_ini_get post_max_size 1G)
        # OPcache for the web process only; enable_cli stays 0 so wp-cli is
        # never served a stale cache. Tuned with plak health opcache set.
        php_ini opcache.enable $(plak_site_ini_get opcache.enable 1)
        php_ini opcache.enable_cli $(plak_site_ini_get opcache.enable_cli 0)
        php_ini opcache.memory_consumption $(plak_site_ini_get opcache.memory_consumption 128)
        php_ini opcache.interned_strings_buffer $(plak_site_ini_get opcache.interned_strings_buffer 16)
        php_ini opcache.max_accelerated_files $(plak_site_ini_get opcache.max_accelerated_files 10000)
        php_ini opcache.validate_timestamps $(plak_site_ini_get opcache.validate_timestamps 1)
        php_ini opcache.revalidate_freq $(plak_site_ini_get opcache.revalidate_freq 2)
        # User-owned session dir. Linux apt's php.ini points sessions at
        # /var/lib/php-zts/session (owned by the frankenphp user); since
        # Plak runs FrankenPHP as the invoking user, that path is
        # unwritable and Adminer spams session_start warnings every
        # request.
        php_ini session.save_path "$PLAK_SITE_DIR/cache/sessions"
    }
    order php_server before file_server
    servers {
        protocols $protocols_value
    }
}

# --- Global Services ---
# The dashboard, Adminer and Mailpit are administrative surfaces. Caddy listens
# on every interface, so each rejects requests whose direct peer is not this
# machine's loopback (or a WSL2 private address). The Origin check in api.php is
# a browser courtesy, not authentication; the Host header is never trusted.

mail.plak.localhost {
    @outside not $local_only
    handle @outside {
        respond "This answers only on the machine running Plak." 403
    }
    reverse_proxy 127.0.0.1:8025
    tls internal
}

db.plak.localhost {
    @outside not $local_only
    handle @outside {
        respond "This answers only on the machine running Plak." 403
    }
    root * "$ADMINER_DIR"
    php_server
    tls internal
}

plak.localhost {
    @outside not $local_only
    handle @outside {
        respond "This answers only on the machine running Plak." 403
    }
    root * "$GUI_DIR"
    php_server
    tls internal
}

# --- Plak Managed Sites ---
EOM

    # Check if Tailscale is enabled
    local tailscale_hostname=""
    local tailscale_config="$APP_DIR/tailscale"
    if [ -f "$tailscale_config" ]; then
        tailscale_hostname=$(cat "$tailscale_config")
    fi

    # Append blocks for each site dynamically
    if [ -d "$SITES_DIR" ]; then
        for site_path in "$SITES_DIR"/*; do
            if [ -d "$site_path" ]; then
                local site_name
                site_name=$(basename "$site_path")

                # Build the list of domains
                local site_domains="$site_name"
                local multisite_mode=""
                if [ -f "$site_path/.multisite-mode" ]; then
                    multisite_mode=$(cat "$site_path/.multisite-mode")
                    [ "$multisite_mode" != subdomains ] || site_domains="$site_domains, *.$site_name"
                fi

                if [ -f "$site_path/mappings" ]; then
                    while IFS= read -r mapping || [ -n "$mapping" ]; do
                         if [ -n "$mapping" ]; then
                            site_domains="$site_domains, $mapping"
                         fi
                    done < "$site_path/mappings"
                fi

                echo "$site_domains {" >> "$CADDYFILE_PATH"

                echo "    root * \"$site_path/public\"" >> "$CADDYFILE_PATH"
                echo "    tls internal" >> "$CADDYFILE_PATH"

                echo "    log {" >> "$CADDYFILE_PATH"
                echo "        output file \"$site_path/logs/caddy.log\"" >> "$CADDYFILE_PATH"
                echo "    }" >> "$CADDYFILE_PATH"

                local custom_conf_file="$CUSTOM_CADDY_DIR/$site_name"
                if [ -f "$custom_conf_file" ]; then
                    echo "" >> "$CADDYFILE_PATH"
                    sed 's/^/    /' "$custom_conf_file" >> "$CADDYFILE_PATH"
                    echo "" >> "$CADDYFILE_PATH"
                fi

                if [ "$multisite_mode" = subdirectories ]; then
                    echo '    @ms_assets {' >> "$CADDYFILE_PATH"
                    echo '        path_regexp ms_assets ^/[^/]+/(wp-(?:content|admin|includes).*|[^/]+\.php(?:/.*)?)$' >> "$CADDYFILE_PATH"
                    echo '        not file {path}' >> "$CADDYFILE_PATH"
                    echo '    }' >> "$CADDYFILE_PATH"
                    echo '    rewrite @ms_assets /{re.ms_assets.1}' >> "$CADDYFILE_PATH"
                fi
                echo "    php_server" >> "$CADDYFILE_PATH"

                if [ ! -f "$site_path/public/wp-config.php" ]; then
                    echo "    file_server" >> "$CADDYFILE_PATH"
                fi

                echo "}" >> "$CADDYFILE_PATH"
                echo "" >> "$CADDYFILE_PATH"

                # Check if LAN access is enabled for this site
                local lan_config="$site_path/lan_config"
                if [ -f "$lan_config" ]; then
                    local lan_port
                    lan_port=$(grep "^port=" "$lan_config" | cut -d'=' -f2)

                    if [ -n "$lan_port" ]; then
                        local lan_ip
                        lan_ip=$(get_lan_ip)
                        echo "# LAN access for $site_name on port $lan_port" >> "$CADDYFILE_PATH"
                        echo "https://${lan_ip}:${lan_port} {" >> "$CADDYFILE_PATH"
                        echo "    bind 0.0.0.0" >> "$CADDYFILE_PATH"
                        echo "    root * \"$site_path/public\"" >> "$CADDYFILE_PATH"
                        echo "    tls internal" >> "$CADDYFILE_PATH"

                        echo "    log {" >> "$CADDYFILE_PATH"
                        echo "        output file \"$site_path/logs/caddy-lan.log\"" >> "$CADDYFILE_PATH"
                        echo "    }" >> "$CADDYFILE_PATH"

                        if [ -f "$custom_conf_file" ]; then
                            echo "" >> "$CADDYFILE_PATH"
                            sed 's/^/    /' "$custom_conf_file" >> "$CADDYFILE_PATH"
                            echo "" >> "$CADDYFILE_PATH"
                        fi

                        echo "    php_server" >> "$CADDYFILE_PATH"

                        if [ ! -f "$site_path/public/wp-config.php" ]; then
                            echo "    file_server" >> "$CADDYFILE_PATH"
                        fi

                        echo "}" >> "$CADDYFILE_PATH"
                        echo "" >> "$CADDYFILE_PATH"
                    fi
                fi
            fi
        done
    fi

    # Append custom proxy entries
    local proxy_dir="$APP_DIR/proxies"
    if [ -d "$proxy_dir" ] && [ -n "$(ls -A "$proxy_dir" 2>/dev/null)" ]; then
        echo "# --- Custom Reverse Proxies ---" >> "$CADDYFILE_PATH"
        echo "" >> "$CADDYFILE_PATH"

        for proxy_file in "$proxy_dir"/*; do
            if [ -f "$proxy_file" ]; then
                local proxy_name
                proxy_name=$(basename "$proxy_file")

                local proxy_domain=""
                local proxy_target=""
                local proxy_tls="internal"

                # Read the config file
                while IFS='=' read -r key value; do
                    case "$key" in
                        domain) proxy_domain="$value" ;;
                        target) proxy_target="$value" ;;
                        tls) proxy_tls="$value" ;;
                    esac
                done < "$proxy_file"

                if [ -n "$proxy_domain" ] && [ -n "$proxy_target" ]; then
                    echo "# Proxy: $proxy_name" >> "$CADDYFILE_PATH"
                    echo "$proxy_domain {" >> "$CADDYFILE_PATH"
                    echo "    reverse_proxy $proxy_target" >> "$CADDYFILE_PATH"
                    if [ "$proxy_tls" = "internal" ]; then
                        echo "    tls internal" >> "$CADDYFILE_PATH"
                    fi
                    echo "}" >> "$CADDYFILE_PATH"
                    echo "" >> "$CADDYFILE_PATH"
                fi
            fi
        done
    fi

    # Add Tailscale port-based routing if enabled
    if [ -n "$tailscale_hostname" ]; then
        echo "# --- Tailscale Port-Based Access ---" >> "$CADDYFILE_PATH"
        echo "" >> "$CADDYFILE_PATH"

        local ts_port=9001

        # Add a server block for each site on a unique port
        if [ -d "$SITES_DIR" ]; then
            for site_path in "$SITES_DIR"/*; do
                if [ -d "$site_path" ]; then
                    local site_name
                    site_name=$(basename "$site_path")
                    local site_base_name
                    site_base_name=$(echo "$site_name" | sed 's/\.localhost$//')

                    # Check if this site has a simple reverse_proxy directive
                    local directive_file="$CUSTOM_CADDY_DIR/$site_name"
                    local direct_proxy_target=""
                    if [ -f "$directive_file" ]; then
                        # Extract target if directive is just "reverse_proxy <target>"
                        direct_proxy_target=$(grep -E '^reverse_proxy [0-9a-zA-Z.:]+$' "$directive_file" 2>/dev/null | awk '{print $2}')
                    fi

                    echo "# Tailscale: ${site_base_name} -> port ${ts_port}" >> "$CADDYFILE_PATH"
                    echo "https://${tailscale_hostname}:${ts_port} {" >> "$CADDYFILE_PATH"
                    echo "    tls internal" >> "$CADDYFILE_PATH"

                    if [ -n "$direct_proxy_target" ]; then
                        # Proxy directly to the backend target
                        echo "    reverse_proxy ${direct_proxy_target}" >> "$CADDYFILE_PATH"
                    else
                        # Serve site directly (not via proxy) for better compatibility
                        echo "    root * \"$site_path/public\"" >> "$CADDYFILE_PATH"

                        echo "    log {" >> "$CADDYFILE_PATH"
                        echo "        output file \"$site_path/logs/caddy-tailscale.log\"" >> "$CADDYFILE_PATH"
                        echo "    }" >> "$CADDYFILE_PATH"

                        # Include custom directives if present
                        if [ -f "$directive_file" ]; then
                            echo "" >> "$CADDYFILE_PATH"
                            sed 's/^/    /' "$directive_file" >> "$CADDYFILE_PATH"
                            echo "" >> "$CADDYFILE_PATH"
                        fi

                        echo "    php_server" >> "$CADDYFILE_PATH"

                        if [ ! -f "$site_path/public/wp-config.php" ]; then
                            echo "    file_server" >> "$CADDYFILE_PATH"
                        fi
                    fi
                    echo "}" >> "$CADDYFILE_PATH"
                    echo "" >> "$CADDYFILE_PATH"

                    # Store port mapping for this site
                    echo "${ts_port}" > "$site_path/tailscale_port"

                    ((ts_port++))
                fi
            done
        fi

        # Global administrative services on fixed ports. They keep answering the
        # tailnet, but only from Tailscale's address space (CGNAT 100.64.0.0/10
        # and its IPv6 prefix) plus loopback, so a host on a shared local network
        # still cannot reach them. Mirrors the loopback guard on the local hosts.
        local tailnet_only='remote_ip 100.64.0.0/10 fd7a:115c:a1e0::/48 127.0.0.1 ::1'

        # Mail on port 9901
        echo "# Tailscale: mail -> port 9901" >> "$CADDYFILE_PATH"
        echo "https://${tailscale_hostname}:9901 {" >> "$CADDYFILE_PATH"
        echo "    @outside not $tailnet_only" >> "$CADDYFILE_PATH"
        echo "    handle @outside {" >> "$CADDYFILE_PATH"
        echo "        respond \"This answers only on the Tailscale network.\" 403" >> "$CADDYFILE_PATH"
        echo "    }" >> "$CADDYFILE_PATH"
        echo "    tls internal" >> "$CADDYFILE_PATH"
        echo "    reverse_proxy 127.0.0.1:8025" >> "$CADDYFILE_PATH"
        echo "}" >> "$CADDYFILE_PATH"
        echo "" >> "$CADDYFILE_PATH"

        # DB on port 9902
        echo "# Tailscale: db -> port 9902" >> "$CADDYFILE_PATH"
        echo "https://${tailscale_hostname}:9902 {" >> "$CADDYFILE_PATH"
        echo "    @outside not $tailnet_only" >> "$CADDYFILE_PATH"
        echo "    handle @outside {" >> "$CADDYFILE_PATH"
        echo "        respond \"This answers only on the Tailscale network.\" 403" >> "$CADDYFILE_PATH"
        echo "    }" >> "$CADDYFILE_PATH"
        echo "    tls internal" >> "$CADDYFILE_PATH"
        echo "    root * \"$ADMINER_DIR\"" >> "$CADDYFILE_PATH"
        echo "    php_server" >> "$CADDYFILE_PATH"
        echo "}" >> "$CADDYFILE_PATH"
        echo "" >> "$CADDYFILE_PATH"

        # Dashboard on port 9900
        echo "# Tailscale: plak dashboard -> port 9900" >> "$CADDYFILE_PATH"
        echo "https://${tailscale_hostname}:9900 {" >> "$CADDYFILE_PATH"
        echo "    @outside not $tailnet_only" >> "$CADDYFILE_PATH"
        echo "    handle @outside {" >> "$CADDYFILE_PATH"
        echo "        respond \"This answers only on the Tailscale network.\" 403" >> "$CADDYFILE_PATH"
        echo "    }" >> "$CADDYFILE_PATH"
        echo "    tls internal" >> "$CADDYFILE_PATH"
        echo "    root * \"$GUI_DIR\"" >> "$CADDYFILE_PATH"
        echo "    php_server" >> "$CADDYFILE_PATH"
        echo "}" >> "$CADDYFILE_PATH"
        echo "" >> "$CADDYFILE_PATH"
    fi

    # If Caddy is already running, reload against the new config. If it isn't,
    # start it — the start command reads $CADDYFILE_PATH itself, so no reload
    # is needed. Without this probe, plak add on a stopped stack would
    # silently "succeed" while the site was actually unreachable.
    #
    # The reload runs synchronously so callers only see success after the new
    # config is actually live. The previous implementation backgrounded it to
    # avoid a self-deadlock when the dashboard (running inside FrankenPHP)
    # triggered a reload; that deadlock is now handled at the PHP layer, which
    # already backgrounds plak reload via shell_exec '…&' (see create_gui_file).
    # With hundreds of sites the Caddyfile adapt takes a few seconds — racing
    # the exit against a subsequent curl produced TLS internal errors.
    if is_caddy_running; then
        # Reload talks to the admin API on localhost:2019 and doesn't need
        # root. Dropping sudo here keeps the caller (incl. the dashboard's
        # shell_exec) running as the invoking user.
        if "$CADDY_CMD" reload --config "$CADDYFILE_PATH" --address localhost:2019 &> "$LOGS_DIR/caddy-reload.log"; then
            echo "✅ Caddy configuration reloaded."
        else
            gum style --foreground red "❌ Caddy reload failed. See $LOGS_DIR/caddy-reload.log for details."
            return 1
        fi
    else
        echo "ℹ️  Caddy is not running — starting it now."
        start_caddy_service
    fi
}

# --- GUI Generation ---
create_gui_file() {
    echo "🎨 Creating Plak dashboard files..."
    mkdir -p "$GUI_DIR"

    # Create the API file that handles the logic
    cat > "$GUI_DIR/api.php.tmp" << 'EOM'
<?php
header('Content-Type: application/json');
$sitedir = 'SITES_DIR_PLACEHOLDER';
$plak_site_path = 'PLAK_SITE_EXECUTABLE_PATH_PLACEHOLDER';
$user_home = 'USER_HOME_PLACEHOLDER';

// Read the configured HTTPS port so site links include ":8453" when non-default.
$__plak_site_https_port = 443;
$__plak_site_cfg_path = $user_home . '/Plak/config';
if (file_exists($__plak_site_cfg_path)) {
    $__plak_site_cfg = parse_ini_file($__plak_site_cfg_path);
    if (!empty($__plak_site_cfg['HTTPS_PORT'])) {
        $__plak_site_https_port = (int) $__plak_site_cfg['HTTPS_PORT'];
    }
}
$__plak_site_port_suffix = ($__plak_site_https_port === 443) ? '' : ':' . $__plak_site_https_port;

// --- Administrative access protection ---
// Second line behind the Caddy matcher: only this machine, a WSL2 private
// address, or the tailnet may talk to the API. The CSRF token below then guards
// mutating requests against a page opened elsewhere in the browser. The Host
// header is never treated as authentication.
$__plak_site_ra = $_SERVER['REMOTE_ADDR'] ?? '';
$__plak_site_wsl = 'IS_WSL_PLACEHOLDER' === 'true';
$__plak_site_ok = in_array($__plak_site_ra, ['127.0.0.1', '::1', '::ffff:127.0.0.1', ''], true)
    || preg_match('/^(100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.|fd7a:115c:a1e0:)/i', $__plak_site_ra)
    || ($__plak_site_wsl && preg_match('/^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|fe80:|fd|fc|::ffff:(10\.|192\.168\.))/i', $__plak_site_ra));
if (!$__plak_site_ok) {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'This answers only on the machine running Plak.']);
    exit;
}

$__plak_site_token_file = $user_home . '/Plak/cache/dashboard-token';

function plak_site_dashboard_token($path) {
    if (file_exists($path)) {
        $existing = trim((string) @file_get_contents($path));
        if (strlen($existing) >= 32) return $existing;
    }
    $token = bin2hex(random_bytes(32));
    @mkdir(dirname($path), 0755, true);
    // Create with restrictive permissions atomically, then fall back to write.
    $tmp = $path . '.' . bin2hex(random_bytes(4));
    if (@file_put_contents($tmp, $token) !== false) {
        @chmod($tmp, 0600);
        @rename($tmp, $path);
    } else {
        @file_put_contents($path, $token);
    }
    return $token;
}

$__plak_site_dashboard_token = plak_site_dashboard_token($__plak_site_token_file);

// Per-site disk sizes are cached so list_sites stays fast even on hosts with
// ~100 sites. The cache is refreshed on demand by the dashboard's 'refresh_sizes'
// action; stale entries are tolerable because list_sites filters by what's on
// disk and the UI falls back to '—' when an entry is missing.
$__plak_site_sizes_cache = $user_home . '/Plak/cache/site-sizes.json';

function plak_site_read_size_cache($path) {
    if (!file_exists($path)) return [];
    $data = @json_decode(@file_get_contents($path), true);
    return (is_array($data) && isset($data['sites']) && is_array($data['sites'])) ? $data['sites'] : [];
}

function plak_site_write_size_cache($path, array $sizes) {
    @mkdir(dirname($path), 0755, true);
    @file_put_contents($path, json_encode([
        'sites' => $sizes,
        'updated_at' => time(),
    ], JSON_UNESCAPED_SLASHES));
}

// Handle GET requests for listing sites
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $action = $_GET['action'] ?? '';
    if ($action === 'list_sites') {
        $sites_info = [];
        $size_cache = plak_site_read_size_cache($__plak_site_sizes_cache);
        if (file_exists($sitedir) && is_dir($sitedir)) {
            $items = scandir($sitedir);
            foreach ($items as $item) {
                if ($item === '.' || $item === '..') continue;
                $site_path = $sitedir . '/' . $item;
                if (is_dir($site_path)) {
                    // Prefer the public/ dir's mtime since it gets touched whenever
                    // files are added/removed at the doc root — closer to "when did I
                    // last work on this site" than the site dir itself.
                    $mtime = @filemtime($site_path . '/public');
                    if (!$mtime) $mtime = @filemtime($site_path);

                    $sites_info[] = [
                        'name' => str_replace('.localhost', '', $item),
                        'domain' => 'https://' . $item . $__plak_site_port_suffix,
                        'type' => file_exists($site_path . "/public/wp-config.php") ? 'WordPress' : 'Plain',
                        'display_path' => '~/Plak/Sites/' . $item,
                        'full_path' => $site_path,
                        'size_bytes' => isset($size_cache[$item]) ? (int) $size_cache[$item] : null,
                        'modified_at' => $mtime ?: null,
                        'agent_ready' => file_exists($site_path . '/agent-ready'),
                        'multisite_mode' => is_file($site_path . '/.multisite-mode') ? trim(file_get_contents($site_path . '/.multisite-mode')) : null,
                    ];
                }
            }
            if (!empty($sites_info)) {
                array_multisort(
                    array_column($sites_info, "type"), SORT_ASC,
                    array_column($sites_info, "name"), SORT_ASC,
                    $sites_info
                );
            }
        }
        echo json_encode($sites_info);
        exit;
    }
    if ($action === 'download_snapshot') {
        // Streaming a full backup over GET: read-only, but sensitive, so it
        // still requires the per-install token and validated site/id.
        $query_token = (string) ($_GET['token'] ?? '');
        if (!hash_equals($__plak_site_dashboard_token, $query_token)) {
            http_response_code(403);
            echo json_encode(['success' => false, 'message' => 'Invalid or missing token.']);
            exit;
        }
        $site = (string) ($_GET['site'] ?? '');
        $id = (string) ($_GET['id'] ?? '');
        if (!preg_match('/^[a-zA-Z0-9-]+$/', $site) || !preg_match('/^[A-Za-z0-9._-]{1,64}$/', $id)) {
            http_response_code(400);
            echo json_encode(['success' => false, 'message' => 'Invalid request.']);
            exit;
        }
        $snap_dir = $sitedir . '/' . $site . '.localhost/private/snapshots/' . $id;
        if (!is_dir($snap_dir)) {
            http_response_code(404);
            echo json_encode(['success' => false, 'message' => 'Snapshot not found.']);
            exit;
        }
        $tmp_dir = sys_get_temp_dir() . '/plak-exports';
        @mkdir($tmp_dir, 0700, true);
        $out = $tmp_dir . '/' . $site . '-' . $id . '-' . bin2hex(random_bytes(4)) . '.zip';
        $cmd = sprintf(
            'HOME=%s %s snapshot %s export %s --output %s 2>&1',
            escapeshellarg($user_home),
            escapeshellarg($plak_site_path),
            escapeshellarg($site),
            escapeshellarg($id),
            escapeshellarg($out)
        );
        exec($cmd, $lines, $rc);
        if ($rc !== 0 || !is_file($out)) {
            @unlink($out);
            http_response_code(500);
            echo json_encode(['success' => false, 'message' => 'Could not export the snapshot.', 'output' => implode("\n", $lines)]);
            exit;
        }
        // The export is a temp artifact, not a backup to keep: always remove it.
        register_shutdown_function(function () use ($out) { @unlink($out); });
        header('Content-Type: application/zip');
        header('Content-Disposition: attachment; filename="' . $site . '-' . $id . '.zip"');
        header('Content-Length: ' . filesize($out));
        header('X-Content-Type-Options: nosniff');
        readfile($out);
        exit;
    }
}

// Handle POST requests for adding/deleting/reloading
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // CSRF / cross-origin guard. Every POST action here mutates state (add /
    // delete sites, reload), and the body is read via php://input regardless of
    // Content-Type — so a cross-site page could drive it with a CORS "simple"
    // text/plain POST that skips preflight. Browsers still stamp such a request
    // with an Origin (and always a Referer on same-origin), so require one of
    // them to match this host before doing anything. Compare host only;
    // HTTP_HOST may carry a :port that the Origin/Referer host omits.
    $__plak_site_host_only = preg_replace('/:\d+$/', '', $_SERVER['HTTP_HOST'] ?? '');
    $__plak_site_src = $_SERVER['HTTP_ORIGIN'] ?? ($_SERVER['HTTP_REFERER'] ?? '');
    $__plak_site_src_host = $__plak_site_src !== '' ? parse_url($__plak_site_src, PHP_URL_HOST) : '';
    if (empty($__plak_site_src_host) || empty($__plak_site_host_only) || strcasecmp($__plak_site_src_host, $__plak_site_host_only) !== 0) {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'Cross-origin request blocked.']);
        exit;
    }

    $input = json_decode(file_get_contents('php://input'), true);
    // Multipart uploads (import) arrive as form fields, not as a JSON body.
    if (!is_array($input) || empty($input['action'])) {
        if (!empty($_POST)) $input = $_POST;
    }
    $action = $input['action'] ?? '';
    $response = ['success' => false, 'message' => 'Invalid request.'];
    $command = '';
    $site_name = $input['site_name'] ?? '';

    // Background-job helpers shared by the snapshot and import actions. Long
    // operations detach and record their exit code so the dashboard can poll.
    $__plak_cmd = function (array $args) use ($user_home, $plak_site_path) {
        $cmd = 'HOME=' . escapeshellarg($user_home) . ' ' . escapeshellarg($plak_site_path);
        foreach ($args as $a) $cmd .= ' ' . escapeshellarg((string) $a);
        return $cmd;
    };
    $__jobs_dir = $user_home . '/Plak/cache/jobs';
    $__job_start = function ($label, $command, $cleanup = '') use ($__jobs_dir) {
        @mkdir($__jobs_dir, 0755, true);
        $id = bin2hex(random_bytes(8));
        file_put_contents($__jobs_dir . '/' . $id . '.json', json_encode(['id' => $id, 'label' => $label, 'status' => 'running', 'started' => time()]));
        $log = $__jobs_dir . '/' . $id . '.log';
        $exit = $__jobs_dir . '/' . $id . '.exit';
        $trail = 'echo $? > ' . escapeshellarg($exit) . ';';
        if ($cleanup !== '') $trail .= ' rm -f ' . escapeshellarg($cleanup) . ';';
        // Detached so the request returns right away; the UI polls job_status.
        shell_exec('(' . $command . '; ' . $trail . ') > ' . escapeshellarg($log) . ' 2>&1 &');
        return $id;
    };
    $__job_read = function ($id) use ($__jobs_dir) {
        if (!is_string($id) || !preg_match('/^[a-f0-9]{16}$/', $id)) return null;
        $meta_path = $__jobs_dir . '/' . $id . '.json';
        if (!is_file($meta_path)) return null;
        $meta = json_decode((string) file_get_contents($meta_path), true) ?: [];
        $exit_path = $__jobs_dir . '/' . $id . '.exit';
        if (is_file($exit_path)) {
            $code = (int) trim((string) file_get_contents($exit_path));
            $meta['status'] = $code === 0 ? 'done' : 'failed';
            $meta['exit_code'] = $code;
        }
        $log_path = $__jobs_dir . '/' . $id . '.log';
        if (is_file($log_path)) {
            $lines = preg_split('/\r?\n/', (string) file_get_contents($log_path));
            $meta['log'] = trim(implode("\n", array_slice($lines, -40)));
        }
        return $meta;
    };

    // Per-request CSRF token, embedded in index.php and echoed back by the UI.
    $__plak_site_client_token = $input['csrf'] ?? ($_SERVER['HTTP_X_PLAK_CSRF'] ?? '');
    if (!is_string($__plak_site_client_token) || !hash_equals($__plak_site_dashboard_token, $__plak_site_client_token)) {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'Invalid or missing CSRF token.']);
        exit;
    }

    // These dashboard mutations have only single-site semantics. Fail before
    // executing them against a network (the expert WP-CLI console remains explicit).
    if (in_array($action, ['site_plugin_op', 'site_theme_op', 'site_cron_run'], true)
        && is_string($site_name) && preg_match('/^[a-zA-Z0-9-]+$/', $site_name)) {
        $public = $sitedir . '/' . $site_name . '.localhost/public';
        $config = @file_get_contents($public . '/wp-config.php');
        if (is_file(dirname($public) . '/.multisite-mode') || ($config !== false && str_contains($config, 'MULTISITE'))) {
            $mode_lines = []; $mode_code = 0;
            exec(sprintf('HOME=%s %s wp %s eval %s --skip-plugins --skip-themes 2>/dev/null', escapeshellarg($user_home), escapeshellarg($plak_site_path), escapeshellarg($site_name), escapeshellarg('echo is_multisite() ? "1" : "0";')), $mode_lines, $mode_code);
            if ($mode_code !== 0 || trim(implode("\n", $mode_lines)) !== '0') {
                echo json_encode(['success' => false, 'message' => 'This operation has no network/subsite scope. Use plak wp with explicit --url/--network options. No data was modified.']);
                exit;
            }
        }
    }
    switch ($action) {
        case 'add_site':
            if (!empty($site_name) && preg_match('/^[a-zA-Z0-9-]+$/', $site_name)) {
                $is_plain = (bool) ($input['is_plain'] ?? false);
                $type_flag = $is_plain ? '--plain' : '';
                // Agent readiness is opt-in from the dashboard checkbox; the
                // CLI defaults it on, so the explicit flag is only added when
                // the user unchecked it for a WordPress site.
                $agent_flag = (!$is_plain && isset($input['agent']) && !$input['agent']) ? '--no-agent' : '';
                $command = sprintf('HOME=%s %s add %s %s %s --no-reload 2>&1', escapeshellarg($user_home), escapeshellarg($plak_site_path), escapeshellarg($site_name), $type_flag, $agent_flag);
                // Remember we're adding so the post-exec block below can
                // measure the new site's size and fold it into the cache.
                $add_site_target = $site_name;
            } else { $response['message'] = 'Invalid site name provided.'; }
            break;
        case 'prepare_agent':
            // Run the same idempotent preparation as `plak agent`.
            if (!empty($site_name) && preg_match('/^[a-zA-Z0-9-]+$/', $site_name)) {
                $command = sprintf('HOME=%s %s agent %s 2>&1', escapeshellarg($user_home), escapeshellarg($plak_site_path), escapeshellarg($site_name));
            } else { $response['message'] = 'Invalid site name provided.'; }
            break;
        case 'delete_site':
            if (!empty($site_name)) {
                // --no-reload: plak_site_delete otherwise auto-reloads Caddy after
                // each delete to prevent zombie log-dir skeletons from being
                // recreated. The dashboard batches one reload after the whole
                // delete queue drains, so skip per-item reloads here.
                $command = sprintf('HOME=%s %s delete %s --force --no-reload 2>&1', escapeshellarg($user_home), escapeshellarg($plak_site_path), escapeshellarg($site_name));
            } else { $response['message'] = 'Site name not provided for deletion.'; }
            break;
        case 'site_info':
            // WP-CLI is comparatively slow, so this runs only when the user
            // opens a site's detail view and asks for fresh info — never on the
            // dashboard's initial load.
            $response = ['success' => false, 'message' => 'Invalid site name.'];
            if (!empty($site_name) && preg_match('/^[a-zA-Z0-9-]+$/', $site_name)) {
                $site_public = $sitedir . '/' . $site_name . '.localhost/public';
                if (!is_file($site_public . '/wp-config.php')) {
                    $response = ['success' => false, 'message' => 'Not a WordPress site.'];
                    break;
                }
                $info = ['wp_version' => null, 'plugins' => null, 'network' => null];
                $network_lines = []; $network_code = 0;
                exec(sprintf('HOME=%s %s network %s --json 2>/dev/null', escapeshellarg($user_home), escapeshellarg($plak_site_path), escapeshellarg($site_name)), $network_lines, $network_code);
                if ($network_code === 0) $info['network'] = json_decode(implode("\n", $network_lines), true);
                $vp = []; $vrc = 0;
                exec(sprintf('HOME=%s %s wp %s core version --skip-plugins --skip-themes 2>/dev/null', escapeshellarg($user_home), escapeshellarg($plak_site_path), escapeshellarg($site_name)), $vp, $vrc);
                if ($vrc === 0 && !empty($vp[0])) {
                    $info['wp_version'] = trim($vp[0]);
                }
                $pl = []; $prc = 0;
                exec(sprintf('HOME=%s %s wp %s plugin list --field=name --skip-plugins --skip-themes 2>/dev/null', escapeshellarg($user_home), escapeshellarg($plak_site_path), escapeshellarg($site_name)), $pl, $prc);
                if ($prc === 0) {
                    $names = array_filter(array_map('trim', $pl), fn($v) => $v !== '');
                    $info['plugins'] = count($names);
                }
                $response = ['success' => true, 'info' => $info];
            }
            echo json_encode($response);
            exit;
        case 'site_plugins':
        case 'site_themes':
        case 'site_plugin_op':
        case 'site_theme_op':
            // WP-CLI inside the site, through `plak wp`, so the site's runtime
            // and pinned PHP are honoured. Arguments are built here from
            // validated inputs and passed one per escapeshellarg; nothing the
            // browser sends is interpreted by a shell.
            if (empty($site_name) || !preg_match('/^[a-zA-Z0-9-]+$/', $site_name)) {
                echo json_encode(['success' => false, 'message' => 'Invalid site name.']);
                exit;
            }
            if (!is_file($sitedir . '/' . $site_name . '.localhost/public/wp-config.php')) {
                echo json_encode(['success' => false, 'message' => 'Not a WordPress site.']);
                exit;
            }
            $__wp = function (array $args) use ($user_home, $plak_site_path, $site_name) {
                $cmd = 'HOME=' . escapeshellarg($user_home) . ' ' . escapeshellarg($plak_site_path) . ' wp ' . escapeshellarg($site_name);
                foreach ($args as $a) $cmd .= ' ' . escapeshellarg((string) $a);
                $t0 = microtime(true);
                exec($cmd . ' 2>&1', $lines, $code);
                $out = preg_replace('/\x1b\[[0-9;]*m/', '', implode("\n", $lines));
                return [$out, (int) $code, round((microtime(true) - $t0) * 1000)];
            };
            $__wp_json = function (array $args) use ($__wp) {
                [$out, $code] = $__wp($args);
                $data = json_decode(trim($out), true);
                if ($code !== 0 || !is_array($data)) {
                    foreach (array_reverse(explode("\n", trim($out))) as $line) {
                        $try = json_decode(trim($line), true);
                        if (is_array($try)) { $data = $try; break; }
                    }
                }
                if (!is_array($data)) {
                    echo json_encode(['success' => false, 'message' => trim($out) !== '' ? trim(substr($out, -600)) : 'wp-cli returned nothing.']);
                    exit;
                }
                return $data;
            };
            $__slug_ok = function ($s) { return is_string($s) && $s !== '' && preg_match('/^[A-Za-z0-9._-]+$/', $s); };

            if ($action === 'site_plugins' || $action === 'site_themes') {
                $kind = $action === 'site_plugins' ? 'plugin' : 'theme';
                // Listing skips loading plugins/themes: a heavy plugin can cost
                // twenty seconds to boot and the list needs none of it. `check`
                // asks wp.org for updates (slow, so it is explicit).
                $args = [$kind, 'list', '--fields=name,title,status,version,update,update_version,auto_update', '--format=json', '--skip-plugins', '--skip-themes'];
                if (empty($input['check'])) $args[] = '--skip-update-check';
                $items = $__wp_json($args);
                echo json_encode(['success' => true, 'items' => array_values($items), 'checked' => !empty($input['check'])]);
                exit;
            }

            // Mutation: an allow-listed op on a validated slug. There is no path
            // from a browser value to a shell command.
            $kind = $action === 'site_plugin_op' ? 'plugin' : 'theme';
            $op = (string) ($input['op'] ?? '');
            $slug = $input['slug'] ?? '';
            $allowed = $kind === 'plugin'
                ? ['activate', 'deactivate', 'delete', 'update']
                : ['activate', 'delete', 'update'];
            if (!in_array($op, $allowed, true) || !$__slug_ok($slug)) {
                echo json_encode(['success' => false, 'message' => 'Invalid operation.']);
                exit;
            }
            if ($kind === 'plugin' && $op === 'deactivate' && (string) ($input['status'] ?? '') === 'must-use') {
                echo json_encode(['success' => false, 'message' => 'Must-use plugins cannot be deactivated.']);
                exit;
            }
            [$out, $code] = $__wp([$kind, $op, $slug]);
            echo json_encode([
                'success' => $code === 0,
                'message' => trim($out) !== '' ? trim($out) : ($code === 0 ? 'Done.' : 'wp-cli failed (' . $code . ').'),
            ]);
            exit;
        case 'site_users':
        case 'site_user_login':
        case 'site_cron':
        case 'site_cron_run':
        case 'site_wpcli':
            // Site tools backed by WP-CLI. Arguments are built here from
            // validated inputs and passed one per escapeshellarg through
            // `plak wp`, so nothing the browser sends reaches a shell.
            if (empty($site_name) || !preg_match('/^[a-zA-Z0-9-]+$/', $site_name)) {
                echo json_encode(['success' => false, 'message' => 'Invalid site name.']);
                exit;
            }
            if (!is_file($sitedir . '/' . $site_name . '.localhost/public/wp-config.php')) {
                echo json_encode(['success' => false, 'message' => 'Not a WordPress site.']);
                exit;
            }
            $__wp = function (array $args) use ($user_home, $plak_site_path, $site_name) {
                $cmd = 'HOME=' . escapeshellarg($user_home) . ' ' . escapeshellarg($plak_site_path) . ' wp ' . escapeshellarg($site_name);
                foreach ($args as $a) $cmd .= ' ' . escapeshellarg((string) $a);
                $t0 = microtime(true);
                exec($cmd . ' 2>&1', $lines, $code);
                $out = preg_replace('/\x1b\[[0-9;]*m/', '', implode("\n", $lines));
                return [$out, (int) $code, round((microtime(true) - $t0) * 1000)];
            };

            if ($action === 'site_users') {
                [$out, $code] = $__wp(['user', 'list', '--fields=ID,user_login,display_name,user_email,roles', '--format=json', '--skip-plugins', '--skip-themes']);
                $users = json_decode(trim($out), true);
                if (!is_array($users)) {
                    echo json_encode(['success' => false, 'message' => trim($out) !== '' ? trim(substr($out, -600)) : 'wp-cli returned nothing.']);
                    exit;
                }
                echo json_encode(['success' => true, 'items' => array_values($users)]);
                exit;
            }

            if ($action === 'site_user_login') {
                $login = (string) ($input['user_login'] ?? '');
                if ($login === '' || !preg_match('/^[A-Za-z0-9._@-]+$/', $login)) {
                    echo json_encode(['success' => false, 'message' => 'Invalid user.']);
                    exit;
                }
                // `plak login` re-injects the helper and mints a token that
                // expires and is single-use; --raw keeps the output parseable.
                $command = sprintf(
                    'HOME=%s %s login %s %s --raw 2>&1',
                    escapeshellarg($user_home),
                    escapeshellarg($plak_site_path),
                    escapeshellarg($site_name),
                    escapeshellarg($login)
                );
                exec($command, $lines, $rc);
                $url = '';
                foreach ($lines as $line) {
                    if (strpos($line, 'https://') !== false && strpos($line, '/wp-login.php') !== false) {
                        $url = trim(preg_replace('/[│└┌]/u', '', $line));
                        break;
                    }
                }
                if ($url !== '') {
                    echo json_encode(['success' => true, 'url' => $url, 'user' => $login]);
                } else {
                    echo json_encode(['success' => false, 'message' => 'Could not generate a login link.', 'output' => implode("\n", $lines)]);
                }
                exit;
            }

            if ($action === 'site_cron') {
                [$out, $code] = $__wp(['cron', 'event', 'list', '--fields=hook,next_run_gmt,recurrence,interval', '--format=json', '--skip-plugins', '--skip-themes']);
                $events = json_decode(trim($out), true);
                if (!is_array($events)) {
                    echo json_encode(['success' => false, 'message' => trim($out) !== '' ? trim(substr($out, -600)) : 'wp-cli returned nothing.']);
                    exit;
                }
                echo json_encode(['success' => true, 'items' => array_values($events)]);
                exit;
            }

            if ($action === 'site_cron_run') {
                // An allow-listed hook, or the literal --due-now sentinel.
                $hook = (string) ($input['hook'] ?? '');
                if ($hook === '--due-now') {
                    $wp_args = ['cron', 'event', 'run', '--due-now', '--skip-plugins', '--skip-themes'];
                } elseif ($hook !== '' && preg_match('/^[A-Za-z0-9._:\/-]+$/', $hook)) {
                    $wp_args = ['cron', 'event', 'run', $hook, '--skip-plugins', '--skip-themes'];
                } else {
                    echo json_encode(['success' => false, 'message' => 'Invalid cron hook.']);
                    exit;
                }
                [$out, $code, $ms] = $__wp($wp_args);
                echo json_encode([
                    'success' => $code === 0,
                    'output' => trim($out),
                    'exit_code' => $code,
                    'duration_ms' => $ms,
                    'message' => $code === 0 ? 'Cron event run.' : 'wp-cli failed (' . $code . ').',
                ]);
                exit;
            }

            // WP-CLI console: the browser sends an argv array, each element is
            // quoted and appended to `plak wp <site>`. There is no shell string
            // to inject into, so arguments are WP-CLI input, never shell input.
            $raw_args = $input['args'] ?? [];
            if (is_string($raw_args)) {
                $raw_args = preg_split('/\s+/', trim($raw_args));
            }
            if (!is_array($raw_args) || count($raw_args) > 64) {
                echo json_encode(['success' => false, 'message' => 'Invalid arguments.']);
                exit;
            }
            $wp_args = [];
            foreach ($raw_args as $a) {
                if (!is_scalar($a)) {
                    echo json_encode(['success' => false, 'message' => 'Invalid arguments.']);
                    exit;
                }
                $a = (string) $a;
                if (strlen($a) > 2000) {
                    echo json_encode(['success' => false, 'message' => 'Argument too long.']);
                    exit;
                }
                $wp_args[] = $a;
            }
            if (empty($wp_args)) {
                echo json_encode(['success' => false, 'message' => 'No command provided.']);
                exit;
            }
            [$out, $code, $ms] = $__wp($wp_args);
            echo json_encode([
                'success' => $code === 0,
                'output' => $out,
                'exit_code' => $code,
                'duration_ms' => $ms,
            ]);
            exit;
        case 'site_logs':
        case 'site_traffic':
            // Logs and traffic are read from the same per-site files. Reading
            // is bounded to the last chunk of each file so a multi-hundred-MB
            // access log never has to be loaded to answer a request.
            if (empty($site_name) || !preg_match('/^[a-zA-Z0-9-]+$/', $site_name)) {
                echo json_encode(['success' => false, 'message' => 'Invalid site name.']);
                exit;
            }
            $__site_dir = $sitedir . '/' . $site_name . '.localhost';
            if (!is_dir($__site_dir)) {
                echo json_encode(['success' => false, 'message' => 'Site not found.']);
                exit;
            }
            $__tail = function ($path, $max_bytes) {
                if (!is_file($path)) return null;
                $size = filesize($path);
                $fh = @fopen($path, 'rb');
                if (!$fh) return null;
                $start = max(0, $size - $max_bytes);
                if ($start > 0) fseek($fh, $start);
                $data = stream_get_contents($fh);
                fclose($fh);
                return [$data, $start > 0, $size];
            };

            if ($action === 'site_logs') {
                $source = (string) ($input['source'] ?? 'php');
                $q = trim((string) ($input['q'] ?? ''));
                $limit = (int) ($input['limit'] ?? 200);
                if ($limit < 1) $limit = 200;
                if ($limit > 500) $limit = 500;
                $min_level = strtolower((string) ($input['level'] ?? 'all'));

                $log_sources = [
                    'php'    => $user_home . '/Plak/Logs/errors.log',
                    'debug'  => $__site_dir . '/public/wp-content/debug.log',
                    'access' => $__site_dir . '/logs/caddy.log',
                ];
                if (!array_key_exists($source, $log_sources)) {
                    echo json_encode(['success' => false, 'message' => 'Unknown log source.']);
                    exit;
                }
                $available = [];
                foreach ($log_sources as $k => $p) { $available[$k] = is_file($p); }

                $tail = $__tail($log_sources[$source], 1048576);
                if ($tail === null) {
                    echo json_encode(['success' => true, 'source' => $source, 'available' => $available, 'items' => [], 'truncated' => false, 'missing' => true]);
                    exit;
                }
                [$data, $truncated, $file_size] = $tail;
                $lines = preg_split('/\r?\n/', $data);
                if ($truncated && count($lines) > 0) array_shift($lines);

                $severity = [
                    'deprecated' => 1, 'notice' => 1, 'strict standards' => 1,
                    'warning' => 2,
                    'parse error' => 3, 'fatal error' => 3, 'recoverable fatal error' => 3,
                ];
                $min_sev = ($min_level === 'all') ? 0 : ($severity[$min_level] ?? 0);
                $items = [];

                if ($source === 'access') {
                    foreach ($lines as $line) {
                        $line = trim($line);
                        if ($line === '' || $line[0] !== '{') continue;
                        $row = json_decode($line, true);
                        if (!is_array($row) || !isset($row['request']['uri'])) continue;
                        $status = (int) ($row['status'] ?? 0);
                        $level = $status >= 500 ? 'error' : ($status >= 400 ? 'warn' : 'info');
                        $uri = $row['request']['uri'] ?? '';
                        $method = $row['request']['method'] ?? '';
                        if ($min_sev > 0 && $level === 'info') continue;
                        if ($q !== '' && stripos($uri . ' ' . $method . ' ' . $status, $q) === false) continue;
                        $item = [
                            'level' => $level,
                            'ts' => isset($row['ts']) ? (float) $row['ts'] : null,
                            'time' => isset($row['ts']) ? gmdate('c', (int) $row['ts']) : null,
                            'method' => $method,
                            'uri' => $uri,
                            'status' => $status,
                            'duration_ms' => isset($row['duration']) ? round(((float) $row['duration']) * 1000, 1) : null,
                            'size' => (int) ($row['size'] ?? 0),
                            'remote_ip' => $row['request']['remote_ip'] ?? '',
                        ];
                        $last = $items ? $items[count($items) - 1] : null;
                        if ($last && $last['uri'] === $item['uri'] && $last['method'] === $item['method'] && $last['status'] === $item['status']) {
                            $items[count($items) - 1]['count'] = ($last['count'] ?? 1) + 1;
                            $items[count($items) - 1]['time'] = $item['time'];
                            $items[count($items) - 1]['ts'] = $item['ts'];
                            continue;
                        }
                        $item['count'] = 1;
                        $items[] = $item;
                    }
                } else {
                    // PHP error log / debug.log share one line format; stack
                    // traces are continuation lines attached to the entry above.
                    $current = null;
                    $push = function () use (&$items, &$current) {
                        if ($current === null) return;
                        $last = $items ? $items[count($items) - 1] : null;
                        if ($last && $last['level'] === $current['level'] && $last['message'] === $current['message'] && $last['location'] === $current['location']) {
                            $items[count($items) - 1]['count'] = ($last['count'] ?? 1) + 1;
                            $items[count($items) - 1]['time'] = $current['time'];
                            return;
                        }
                        $items[] = $current;
                    };
                    foreach ($lines as $line) {
                        if (!preg_match('/^\[([^\]]+)\]\s*(.*)$/', $line, $m)) {
                            if ($current !== null && trim($line) !== '') $current['trace'][] = rtrim($line);
                            continue;
                        }
                        if (!preg_match('/^PHP ([a-zA-Z ]+?):\s*(.*)$/', $m[2], $mm)) {
                            if ($current !== null && trim($line) !== '') $current['trace'][] = rtrim($line);
                            continue;
                        }
                        $push();
                        $rest = $mm[2];
                        $location = '';
                        if (preg_match('/^(.*?) in (.+?) on line (\d+)$/s', $rest, $lm)) {
                            $rest = $lm[1];
                            $location = $lm[2] . ':' . $lm[3];
                        }
                        $current = [
                            'level' => strtolower(trim($mm[1])),
                            'time' => $m[1],
                            'message' => $rest,
                            'location' => $location,
                            'trace' => [],
                            'count' => 1,
                        ];
                    }
                    $push();

                    if ($source === 'php') {
                        // The PHP error log is shared by every site; keep only
                        // entries whose location/trace points at this site.
                        $needle = $__site_dir . '/';
                        $items = array_values(array_filter($items, function ($it) use ($needle) {
                            if ($it['location'] !== '' && strpos($it['location'], $needle) !== false) return true;
                            if (strpos($it['message'], $needle) !== false) return true;
                            foreach ($it['trace'] as $t) {
                                if (strpos($t, $needle) !== false) return true;
                            }
                            return false;
                        }));
                    }
                    if ($q !== '') {
                        $items = array_values(array_filter($items, function ($it) use ($q) {
                            return stripos($it['message'] . ' ' . $it['location'] . ' ' . implode(' ', $it['trace']), $q) !== false;
                        }));
                    }
                    if ($min_sev > 0) {
                        $items = array_values(array_filter($items, function ($it) use ($severity, $min_sev) {
                            return ($severity[$it['level']] ?? 0) >= $min_sev;
                        }));
                    }
                }

                $items = array_values(array_reverse($items));
                $total = count($items);
                if ($total > $limit) $items = array_slice($items, 0, $limit);
                echo json_encode([
                    'success' => true,
                    'source' => $source,
                    'available' => $available,
                    'items' => $items,
                    'truncated' => $truncated,
                    'file_bytes' => $file_size,
                    'total' => $total,
                ]);
                exit;
            }

            // site_traffic: aggregate the site access log over a time window.
            $period = (string) ($input['period'] ?? '24h');
            $windows = ['1h' => 3600, '24h' => 86400, '7d' => 604800];
            $cutoff = isset($windows[$period]) ? time() - $windows[$period] : 0;
            $log = $__site_dir . '/logs/caddy.log';
            if (!is_file($log)) {
                echo json_encode([
                    'success' => true, 'period' => $period, 'available' => false,
                    'summary' => ['requests' => 0, 'errors' => 0, 'server_errors' => 0, 'bytes' => 0, 'avg_ms' => 0, 'p95_ms' => 0, 'max_ms' => 0],
                    'classes' => ['pages' => 0, 'assets' => 0, 'admin' => 0, 'ajax_rest' => 0, 'cron' => 0, 'other' => 0],
                    'top_paths' => [], 'slow' => [],
                ]);
                exit;
            }
            $tail = $__tail($log, 8 * 1024 * 1024);
            [$data, $truncated, $file_size] = $tail;
            $lines = preg_split('/\r?\n/', $data);
            if ($truncated && count($lines) > 0) array_shift($lines);

            $classify = function ($path) {
                if (strpos($path, '/wp-cron.php') !== false) return 'cron';
                if (strpos($path, '/wp-json') === 0 || strpos($path, 'admin-ajax.php') !== false) return 'ajax_rest';
                if (strpos($path, '/wp-admin') === 0 || strpos($path, '/wp-login.php') !== false) return 'admin';
                $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
                if (in_array($ext, ['css', 'js', 'png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'avif', 'ico', 'woff', 'woff2', 'ttf', 'otf', 'map', 'mp4', 'webm', 'pdf'], true)) return 'assets';
                if (strpos($path, '/wp-content/') === 0 || strpos($path, '/wp-includes/') === 0) return 'assets';
                if ($path === '/' || $ext === '' || in_array($ext, ['php', 'html', 'htm'], true)) return 'pages';
                return 'other';
            };

            $requests = 0; $errors = 0; $server_errors = 0; $bytes = 0;
            $classes = ['pages' => 0, 'assets' => 0, 'admin' => 0, 'ajax_rest' => 0, 'cron' => 0, 'other' => 0];
            $paths = []; $slow = []; $durations = [];
            foreach ($lines as $line) {
                $line = trim($line);
                if ($line === '' || $line[0] !== '{') continue;
                $row = json_decode($line, true);
                if (!is_array($row) || !isset($row['request']['uri'])) continue;
                $ts = isset($row['ts']) ? (float) $row['ts'] : 0;
                if ($cutoff && $ts < $cutoff) continue;
                $status = (int) ($row['status'] ?? 0);
                $uri = (string) $row['request']['uri'];
                $path = explode('?', $uri, 2)[0];
                $duration = isset($row['duration']) ? (float) $row['duration'] : 0.0;
                $requests++;
                if ($status >= 400) $errors++;
                if ($status >= 500) $server_errors++;
                $bytes += (int) ($row['size'] ?? 0);
                $durations[] = $duration;
                $paths[$path] = ($paths[$path] ?? 0) + 1;
                $classes[$classify($path)]++;
                $slow[] = ['uri' => $uri, 'duration_ms' => round($duration * 1000, 1), 'status' => $status, 'time' => gmdate('c', (int) $ts)];
            }
            arsort($paths);
            $top_paths = [];
            foreach (array_slice($paths, 0, 10, true) as $p => $c) {
                $top_paths[] = ['path' => $p, 'count' => $c];
            }
            usort($slow, function ($a, $b) { return $b['duration_ms'] <=> $a['duration_ms']; });
            $slow_top = array_slice($slow, 0, 10);
            sort($durations);
            $avg = count($durations) ? round(array_sum($durations) / count($durations) * 1000, 1) : 0;
            $p95 = 0; $max = 0;
            if (count($durations)) {
                $p95 = round($durations[(int) floor((count($durations) - 1) * 0.95)] * 1000, 1);
                $max = round($durations[count($durations) - 1] * 1000, 1);
            }
            echo json_encode([
                'success' => true,
                'period' => $period,
                'available' => true,
                'truncated' => $truncated,
                'file_bytes' => $file_size,
                'summary' => [
                    'requests' => $requests,
                    'errors' => $errors,
                    'server_errors' => $server_errors,
                    'bytes' => $bytes,
                    'avg_ms' => $avg,
                    'p95_ms' => $p95,
                    'max_ms' => $max,
                ],
                'classes' => $classes,
                'top_paths' => $top_paths,
                'slow' => $slow_top,
                'note' => 'Local request metrics from the site access log — not unique visitors or production analytics.',
            ]);
            exit;
        case 'mail_messages':
        case 'mail_message':
        case 'mail_seen':
        case 'mail_delete':
            // Mailpit is reached over its local API. PLAK_MAILPIT_URL lets a
            // non-default port (or a test double) be used.
            $__mail_base = getenv('PLAK_MAILPIT_URL') ?: 'http://127.0.0.1:8025';
            $__mail = function ($method, $path, $body = null) use ($__mail_base) {
                $opts = ['http' => [
                    'method' => $method,
                    'timeout' => 5,
                    'ignore_errors' => true,
                    'header' => "Content-Type: application/json\r\n",
                ]];
                if ($body !== null) $opts['http']['content'] = json_encode($body);
                $data = @file_get_contents(rtrim($__mail_base, '/') . $path, false, stream_context_create($opts));
                if ($data === false) return [null, 0];
                $status = 0;
                foreach (($http_response_header ?? []) as $h) {
                    if (preg_match('#^HTTP/\S+\s+(\d+)#', $h, $m)) $status = (int) $m[1];
                }
                return [$data, $status];
            };
            $__addr = function ($a) {
                if (!is_array($a)) return '';
                $email = (string) ($a['Address'] ?? '');
                $name = (string) ($a['Name'] ?? '');
                return $name !== '' ? $name . ' <' . $email . '>' : $email;
            };

            // A message belongs to a site when any of its addresses, subject or
            // snippet carries one of the site's domains. WordPress's default
            // From is wordpress@<host>, so this catches ordinary site mail;
            // anything unattributable stays in the global view.
            $__site_domains = [];
            if (is_dir($sitedir)) {
                foreach (scandir($sitedir) as $item) {
                    if ($item === '.' || $item === '..') continue;
                    $sp = $sitedir . '/' . $item;
                    if (!is_dir($sp)) continue;
                    $base = preg_replace('/\.localhost$/', '', $item);
                    if (!preg_match('/^[a-zA-Z0-9-]+$/', $base)) continue;
                    if ($site_name !== '' && $base !== $site_name) continue; // per-site scope
                    $doms = [strtolower($item)];
                    $map_file = $sp . '/mappings';
                    if (is_file($map_file)) {
                        foreach (file($map_file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $d) {
                            $d = strtolower(trim($d));
                            if ($d !== '') $doms[] = $d;
                        }
                    }
                    $__site_domains[$base . '.localhost'] = $doms;
                }
            }
            $__mail_site_of = function (array $m) use ($__site_domains) {
                if (!$__site_domains) return null;
                $hay = strtolower(json_encode($m));
                foreach ($__site_domains as $host => $doms) {
                    foreach ($doms as $d) {
                        if (strpos($hay, $d) !== false) return $host;
                    }
                }
                return null;
            };

            if ($action === 'mail_messages') {
                $limit = (int) ($input['limit'] ?? 50);
                if ($limit < 1 || $limit > 200) $limit = 50;
                $start = max(0, (int) ($input['start'] ?? 0));
                $search = trim((string) ($input['search'] ?? ''));
                $scope = (string) ($input['scope'] ?? 'all'); // all | site
                $query = 'limit=' . $limit . '&start=' . $start;
                if ($search !== '') $query .= '&search=' . rawurlencode($search);
                [$data, $status] = $__mail('GET', '/api/v1/messages?' . $query);
                if ($data === null || $status >= 400) {
                    echo json_encode(['success' => false, 'offline' => true, 'message' => 'Mailpit is not reachable.']);
                    exit;
                }
                $payload = json_decode($data, true) ?: [];
                $out = [];
                foreach (($payload['messages'] ?? []) as $m) {
                    $site = $__mail_site_of($m);
                    if ($scope === 'site' && $site === null) continue;
                    $to = [];
                    foreach ((array) ($m['To'] ?? []) as $t) { $to[] = $__addr($t); }
                    $out[] = [
                        'id' => (string) ($m['ID'] ?? ''),
                        'from' => $__addr($m['From'] ?? null),
                        'to' => array_values(array_filter($to)),
                        'subject' => (string) ($m['Subject'] ?? '(no subject)'),
                        'created' => $m['Created'] ?? ($m['Date'] ?? null),
                        'read' => (bool) ($m['Read'] ?? false),
                        'size' => (int) ($m['Size'] ?? 0),
                        'attachments' => (int) ($m['Attachments'] ?? 0),
                        'snippet' => (string) ($m['Snippet'] ?? ''),
                        'site' => $site,
                    ];
                }
                echo json_encode([
                    'success' => true,
                    'offline' => false,
                    'scope' => $scope,
                    'total' => (int) ($payload['total'] ?? 0),
                    'unread' => (int) ($payload['unread'] ?? 0),
                    'messages' => $out,
                    // Make the retention policy explicit instead of implying a
                    // complete history: Mailpit caps what it keeps.
                    'note' => 'Mailpit keeps up to its configured maximum (default 500 messages).',
                ]);
                exit;
            }

            if ($action === 'mail_message') {
                $id = (string) ($input['id'] ?? '');
                if ($id === '' || !preg_match('/^[A-Za-z0-9._-]+$/', $id)) {
                    echo json_encode(['success' => false, 'message' => 'Invalid message id.']);
                    exit;
                }
                [$data, $status] = $__mail('GET', '/api/v1/message/' . rawurlencode($id));
                if ($data === null || $status >= 400) {
                    echo json_encode(['success' => false, 'offline' => true, 'message' => 'Mailpit is not reachable.']);
                    exit;
                }
                $m = json_decode($data, true) ?: [];
                $html = (string) ($m['HTML'] ?? '');
                $text = (string) ($m['Text'] ?? '');

                // Resolve cid: inline images to data: URIs server-side, so the
                // sandboxed frame shows them without loading anything remote.
                foreach ((array) ($m['Inline'] ?? []) as $part) {
                    if (!isset($part['ContentID'], $part['PartID'])) continue;
                    $cid = (string) $part['ContentID'];
                    if ($cid === '' || strpos($html, 'cid:' . $cid) === false) continue;
                    [$bytes, $pstatus] = $__mail('GET', '/api/v1/message/' . rawurlencode($id) . '/part/' . rawurlencode((string) $part['PartID']));
                    if ($bytes !== null && $pstatus < 400 && strlen($bytes) < 2097152) {
                        $ct = (string) ($part['ContentType'] ?? 'application/octet-stream');
                        $html = str_replace('cid:' . $cid, 'data:' . $ct . ';base64,' . base64_encode($bytes), $html);
                    }
                }
                // Strip anything executable before the HTML reaches the browser.
                $html = preg_replace('#<script\b[^>]*>.*?</script>#is', '', $html);
                $html = preg_replace('/\son\w+\s*=\s*("[^"]*"|\'[^\']*\'|[^\s>]+)/i', '', $html);
                $html = preg_replace('/\b(href|src)\s*=\s*(["\']?)\s*javascript:[^"\'>\s]*/i', '$1=$2#', $html);

                $links = [];
                if (preg_match_all('#https?://[^\s"\'<>]+#i', $html . ' ' . $text, $lm)) {
                    foreach ($lm[0] as $u) {
                        $u = html_entity_decode($u, ENT_QUOTES);
                        if (!in_array($u, $links, true)) $links[] = $u;
                    }
                }
                $to = [];
                foreach ((array) ($m['To'] ?? []) as $t) { $to[] = $__addr($t); }

                // Opening a message marks it read; failures are non-fatal.
                $__mail('PUT', '/api/v1/messages', ['IDs' => [$id], 'Read' => true]);

                echo json_encode([
                    'success' => true,
                    'id' => $id,
                    'subject' => (string) ($m['Subject'] ?? '(no subject)'),
                    'from' => $__addr($m['From'] ?? null),
                    'to' => array_values(array_filter($to)),
                    'date' => $m['Date'] ?? ($m['Created'] ?? null),
                    'html' => $html,
                    'text' => $text,
                    'headers' => $m['Headers'] ?? null,
                    'attachments' => $m['Attachments'] ?? [],
                    'links' => array_slice(array_values(array_unique($links)), 0, 50),
                    'site' => $__mail_site_of($m),
                ]);
                exit;
            }

            if ($action === 'mail_seen' || $action === 'mail_delete') {
                $ids = $input['ids'] ?? [];
                if (is_string($ids)) $ids = [$ids];
                if (!is_array($ids) || !count($ids)) {
                    echo json_encode(['success' => false, 'message' => 'No messages selected.']);
                    exit;
                }
                $clean = [];
                foreach ($ids as $i) {
                    if (is_string($i) && preg_match('/^[A-Za-z0-9._-]+$/', $i)) $clean[] = $i;
                }
                if (!$clean) {
                    echo json_encode(['success' => false, 'message' => 'Invalid message id.']);
                    exit;
                }
                if ($action === 'mail_seen') {
                    [$data, $status] = $__mail('PUT', '/api/v1/messages', ['IDs' => $clean, 'Read' => (bool) ($input['read'] ?? true)]);
                } else {
                    [$data, $status] = $__mail('DELETE', '/api/v1/messages', ['IDs' => $clean]);
                }
                if ($data === null || $status >= 400) {
                    echo json_encode(['success' => false, 'offline' => true, 'message' => 'Mailpit is not reachable.']);
                    exit;
                }
                echo json_encode(['success' => true, 'ids' => $clean]);
                exit;
            }
        case 'job_status':
            $job = $__job_read((string) ($input['id'] ?? ''));
            if ($job === null) {
                echo json_encode(['success' => false, 'message' => 'Unknown job.']);
                exit;
            }
            echo json_encode(['success' => true, 'job' => $job]);
            exit;
        case 'snapshots':
        case 'snapshot_create':
        case 'snapshot_restore':
        case 'snapshot_delete':
            if (empty($site_name) || !preg_match('/^[a-zA-Z0-9-]+$/', $site_name)) {
                echo json_encode(['success' => false, 'message' => 'Invalid site name.']);
                exit;
            }
            if (!is_dir($sitedir . '/' . $site_name . '.localhost')) {
                echo json_encode(['success' => false, 'message' => 'Site not found.']);
                exit;
            }

            if ($action === 'snapshots') {
                exec($__plak_cmd(['snapshot', $site_name, 'list', '--json']) . ' 2>&1', $lines, $rc);
                $data = json_decode(trim(implode("\n", $lines)), true);
                if (!is_array($data)) {
                    foreach (array_reverse($lines) as $l) {
                        $try = json_decode(trim($l), true);
                        if (is_array($try)) { $data = $try; break; }
                    }
                }
                if (!is_array($data)) {
                    echo json_encode(['success' => false, 'message' => trim(implode("\n", $lines)) ?: 'Could not list snapshots.']);
                    exit;
                }
                echo json_encode(['success' => true, 'items' => array_values($data)]);
                exit;
            }

            if ($action === 'snapshot_delete') {
                $id = (string) ($input['id'] ?? '');
                if (!preg_match('/^[A-Za-z0-9._-]{1,64}$/', $id)) {
                    echo json_encode(['success' => false, 'message' => 'Invalid snapshot id.']);
                    exit;
                }
                exec($__plak_cmd(['snapshot', $site_name, 'delete', $id, '--yes']) . ' 2>&1', $lines, $rc);
                echo json_encode([
                    'success' => $rc === 0,
                    'message' => $rc === 0 ? 'Snapshot deleted.' : (trim(implode("\n", $lines)) ?: 'Could not delete the snapshot.'),
                ]);
                exit;
            }

            if ($action === 'snapshot_create') {
                $note = (string) ($input['note'] ?? '');
                if (strlen($note) > 200) $note = substr($note, 0, 200);
                $job = $__job_start('Snapshot of ' . $site_name, $__plak_cmd(['snapshot', $site_name, 'create', '--note', $note, '--json']));
                echo json_encode(['success' => true, 'job' => $job]);
                exit;
            }

            // snapshot_restore: the CLI keeps a safety snapshot first and only
            // reports success once the database step has finished.
            $id = (string) ($input['id'] ?? '');
            if (!preg_match('/^[A-Za-z0-9._-]{1,64}$/', $id)) {
                echo json_encode(['success' => false, 'message' => 'Invalid snapshot id.']);
                exit;
            }
            $job = $__job_start('Restore ' . $site_name, $__plak_cmd(['snapshot', $site_name, 'restore', $id, '--yes']));
            echo json_encode(['success' => true, 'job' => $job]);
            exit;
        case 'import_site':
            if (empty($site_name) || !preg_match('/^[a-zA-Z0-9-]+$/', $site_name)) {
                echo json_encode(['success' => false, 'message' => 'Invalid site name.']);
                exit;
            }
            $file = $_FILES['backup'] ?? null;
            if (!is_array($file) || !isset($file['error'])) {
                echo json_encode(['success' => false, 'message' => 'No backup file uploaded.']);
                exit;
            }
            if ((int) $file['error'] !== UPLOAD_ERR_OK) {
                $messages = [
                    UPLOAD_ERR_INI_SIZE => 'The backup exceeds the server upload limit.',
                    UPLOAD_ERR_FORM_SIZE => 'The backup is too large.',
                    UPLOAD_ERR_PARTIAL => 'The upload was interrupted. Try again.',
                    UPLOAD_ERR_NO_FILE => 'No backup file uploaded.',
                ];
                echo json_encode(['success' => false, 'message' => $messages[(int) $file['error']] ?? 'Upload failed (code ' . (int) $file['error'] . ').']);
                exit;
            }
            $orig = (string) ($file['name'] ?? '');
            $ext = '';
            if (preg_match('/\.(zip|tar\.gz|tgz|tar)$/i', $orig, $m)) $ext = strtolower($m[1]);
            if ($ext === '') {
                echo json_encode(['success' => false, 'message' => 'Unsupported archive. Use zip, tar.gz, tgz or tar.']);
                exit;
            }
            if (!is_uploaded_file($file['tmp_name'])) {
                echo json_encode(['success' => false, 'message' => 'Invalid upload.']);
                exit;
            }
            // The archive is a temp file: always removed by the job, never kept.
            $tmp_dir = sys_get_temp_dir() . '/plak-uploads';
            @mkdir($tmp_dir, 0700, true);
            $tmp = $tmp_dir . '/import-' . bin2hex(random_bytes(6)) . '.' . $ext;
            if (!move_uploaded_file($file['tmp_name'], $tmp)) {
                echo json_encode(['success' => false, 'message' => 'Could not store the upload.']);
                exit;
            }
            $job = $__job_start('Import ' . $site_name, $__plak_cmd(['import', $site_name, $tmp, '--yes']), $tmp);
            echo json_encode(['success' => true, 'job' => $job]);
            exit;
        case 'get_login_link':
            $response = ['success' => false, 'message' => 'An unknown error occurred.'];
            if (!empty($site_name)) {
                // Delegate to the 'plak login' command which has the self-healing logic.
                $command = sprintf(
                    'HOME=%s %s login %s 2>&1',
                    escapeshellarg($user_home),
                    escapeshellarg($plak_site_path),
                    escapeshellarg($site_name)
                );

                exec($command, $output_lines, $return_code);
                $full_output = implode("\n", $output_lines);
                $login_url = '';

                // Parse the command's output to find the URL.
                foreach ($output_lines as $line) {
                    if (strpos($line, 'https://') !== false && strpos($line, '/wp-login.php') !== false) {
                        // Clean the line from any "gum" box characters.
                        $login_url = trim(preg_replace('/[│└┌]/u', '', $line));
                        break;
                    }
                }

                if (!empty($login_url)) {
                    $response = ['success' => true, 'url' => $login_url];
                } else {
                    $response = ['success' => false, 'message' => 'Failed to generate login link.', 'output' => $full_output];
                }

            } else {
                $response['message'] = 'Site name not provided for login link.';
            }
            echo json_encode($response);
            exit; // Exit immediately
        case 'reload_server':
            // This command is run in the background to prevent deadlocking the server.
            // Output is redirected to /dev/null and the '&' backgrounds the process.
            $reload_command = sprintf('HOME=%s %s reload > /dev/null 2>&1 &', escapeshellarg($user_home), escapeshellarg($plak_site_path));
            shell_exec($reload_command);
            $response = ['success' => true, 'message' => 'Server reload initiated.'];
            echo json_encode($response);
            exit; // Exit immediately
        case 'refresh_sizes':
            // Walk every site directory with `du -sk` (portable on macOS + Linux — -k
            // forces 1024-byte blocks) and cache the result as bytes. Runs sequentially
            // so 80+ sites take a few seconds; acceptable because this is user-triggered.
            $sizes = [];
            if (file_exists($sitedir) && is_dir($sitedir)) {
                foreach (scandir($sitedir) as $item) {
                    if ($item === '.' || $item === '..') continue;
                    $p = $sitedir . '/' . $item;
                    if (!is_dir($p)) continue;
                    $out = []; $rc = 0;
                    exec('du -sk ' . escapeshellarg($p) . ' 2>/dev/null', $out, $rc);
                    if ($rc === 0 && !empty($out[0])) {
                        $parts = preg_split('/\s+/', trim($out[0]));
                        if (ctype_digit($parts[0] ?? '')) {
                            $sizes[$item] = ((int) $parts[0]) * 1024;
                        }
                    }
                }
            }
            plak_site_write_size_cache($__plak_site_sizes_cache, $sizes);
            echo json_encode(['success' => true, 'sites' => $sizes, 'updated_at' => time()]);
            exit;
    }

    if (!empty($command)) {
        exec($command, $output, $return_code);
        if ($return_code === 0) {
            $response = ['success' => true, 'message' => 'Operation completed successfully.'];
            // For add_site: measure the new site's footprint inline and fold
            // it into the size cache so the UI shows "4.0 KB" (or whatever)
            // immediately instead of "—" until the next refresh_sizes pass.
            if (isset($add_site_target)) {
                $new_path = $sitedir . '/' . $add_site_target . '.localhost';
                if (is_dir($new_path)) {
                    $size_out = []; $size_rc = 0;
                    exec('du -sk ' . escapeshellarg($new_path) . ' 2>/dev/null', $size_out, $size_rc);
                    if ($size_rc === 0 && !empty($size_out[0])) {
                        $parts = preg_split('/\s+/', trim($size_out[0]));
                        if (ctype_digit($parts[0] ?? '')) {
                            $bytes = ((int) $parts[0]) * 1024;
                            $response['size_bytes'] = $bytes;
                            $cache = plak_site_read_size_cache($__plak_site_sizes_cache);
                            $cache[$add_site_target . '.localhost'] = $bytes;
                            plak_site_write_size_cache($__plak_site_sizes_cache, $cache);
                        }
                    }
                }
            }
        } else {
            // Translate known failure signatures into user-friendly messages.
            // Generic "An error occurred" isn't actionable, but "Site name is
            // taken" tells the user exactly what to do next.
            $err_text = implode("\n", $output);
            $msg = 'An error occurred.';
            if (isset($add_site_target)) {
                $msg = 'Could not create site.';
                if (stripos($err_text, 'already exists') !== false) {
                    $msg = 'Site name is taken.';
                } elseif (stripos($err_text, 'reserved name') !== false) {
                    $msg = 'That name is reserved. Pick another.';
                } elseif (stripos($err_text, 'invalid site name') !== false) {
                    $msg = 'Invalid site name.';
                } elseif (stripos($err_text, 'WordPress installation failed') !== false) {
                    $msg = 'WordPress installation failed — check the logs.';
                }
            }
            $response = ['success' => false, 'message' => $msg, 'output' => $err_text];
        }
    }
    echo json_encode($response);
    exit;
}

http_response_code(405);
echo json_encode(['success' => false, 'message' => 'Method Not Allowed']);
EOM

    # Create the main dashboard file (the UI)
    cat > "$GUI_DIR/index.php.tmp" << 'EOM'
<?php
$config_file = getenv('HOME') . '/Plak/config';
$config_data = file_exists($config_file) ? parse_ini_file($config_file) : [];
$__plak_site_https_port = isset($config_data['HTTPS_PORT']) ? (int) $config_data['HTTPS_PORT'] : 443;
$__plak_site_port_suffix = ($__plak_site_https_port === 443) ? '' : ':' . $__plak_site_https_port;

// The same CSRF token api.php verifies, surfaced to the UI so each mutating
// request can echo it back. Read (never generated) here: api.php owns creation.
$__plak_site_token_file = getenv('HOME') . '/Plak/cache/dashboard-token';
$__plak_site_csrf = file_exists($__plak_site_token_file) ? trim((string) file_get_contents($__plak_site_token_file)) : '';
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="color-scheme" content="dark light">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Plak CLI — sites</title>
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'><rect width='64' height='64' rx='12' fill='%232f36fa'/><text x='32' y='46' text-anchor='middle' font-family='Arial,sans-serif' font-size='42' font-weight='700' fill='white'>P</text></svg>">
    <script>
        // Set data-theme synchronously before any CSS paints, so the correct
        // theme's background is used from the very first frame (no FOUC).
        // Alpine re-reads the same localStorage key in init() — values stay
        // in sync with no extra flip.
        (function () {
            try {
                var s = localStorage.getItem('theme');
                var t = (s === 'dark' || s === 'light')
                    ? s
                    : (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark');
                document.documentElement.setAttribute('data-theme', t);
            } catch (e) {}
        })();
    </script>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,400..600;1,9..144,400..600&family=Geist:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
    <script src="//unpkg.com/alpinejs" defer></script>
    <style>
        *, *::before, *::after { box-sizing: border-box; }
        html, body { margin: 0; padding: 0; }
        html { background: #0f1210; }
        html[data-theme="light"] { background: #fbfaf7; }

        :root {
            --font-sans: 'Geist', -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
            --font-serif: 'Fraunces', Georgia, serif;
            --font-mono: 'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, Consolas, monospace;
            /* sRGB fallback first; browsers without oklch() support silently
               drop the override on the next line and keep the hex value.
               Without the fallback, the whole declaration would be invalid on
               Firefox <113 / Chrome <111 / Safari <16.4 and --accent would be
               unset — which reads as "transparent" for backgrounds and
               "black" for SVG fills (hence the invisible add button and the
               solid-black logo disc on older browsers). */
            --accent: #2f36fa;
            --accent: oklch(55% 0.18 255);
            --accent-fg: #0a1a1c;
            --radius-lg: 20px;
            --radius-md: 10px;
            --radius-pill: 999px;
        }

        html[data-theme="dark"], html:not([data-theme]) {
            --bg: #0f1210;
            --bg-sunk: #0b0e0c;
            --panel: #181c19;
            --panel-hover: #1e2320;
            --panel-border: #252925;
            --text: #edeee9;
            --text-dim: #8a8e85;
            --text-faint: #5d615a;
            /* Dark-mode teal is brighter so it reads cleanly against the
               warmer panel — matches the landing page palette. */
            --accent: #2f36fa;
            --accent: oklch(70% 0.15 255);
            --pill-bg: #1e2320;
            --pill-wp-bg: rgba(77, 176, 194, 0.18);
            --pill-wp-bg: color-mix(in oklch, var(--accent) 18%, transparent);
            --pill-wp-fg: #71c0ce;
            --pill-wp-fg: color-mix(in oklch, var(--accent) 80%, white);
            --pill-static-bg: #1e2320;
            --pill-static-fg: #9a9d94;
            --input-bg: #0b0e0c;
            --danger: #d66a6a;
            --shadow-lg: 0 28px 60px -24px rgba(0,0,0,0.7), 0 6px 16px -6px rgba(0,0,0,0.4);
            color-scheme: dark;
        }

        html[data-theme="light"] {
            --bg: #fbfaf7;
            --bg-sunk: #f4f2ec;
            --panel: #ffffff;
            --panel-hover: #f6f4ee;
            --panel-border: #e8e4da;
            --text: #1a1c1b;
            --text-dim: #6b6f6a;
            --text-faint: #9a9d97;
            /* White on teal reads stronger than the dark accent-fg does on
               the lighter background — override just for light mode. */
            --accent-fg: #ffffff;
            --pill-bg: #f1ede5;
            --pill-wp-bg: rgba(58, 151, 169, 0.14);
            --pill-wp-bg: color-mix(in oklch, var(--accent) 14%, transparent);
            --pill-wp-fg: #20535d;
            --pill-wp-fg: color-mix(in oklch, var(--accent) 55%, black);
            --pill-static-bg: #f1ede5;
            --pill-static-fg: #8a8781;
            --input-bg: #fbfaf7;
            --danger: #b44848;
            --shadow-lg: 0 24px 50px -24px rgba(20,28,30,0.18), 0 6px 16px -6px rgba(20,28,30,0.06);
            color-scheme: light;
        }

        body {
            background: var(--bg);
            color: var(--text);
            font-family: var(--font-sans);
            font-size: 15px;
            line-height: 1.5;
            min-height: 100vh;
            padding: 2.5rem 1.25rem 4rem;
            -webkit-font-smoothing: antialiased;
            font-feature-settings: "ss01", "cv11";
        }

        .wrap { max-width: 820px; margin: 0 auto; }

        /* Top nav */
        .nav { display: flex; align-items: center; justify-content: space-between; margin-bottom: 2rem; }
        .logo { display: inline-flex; align-items: center; gap: 12px; color: var(--text); text-decoration: none; font-weight: 600; font-size: 1.05rem; letter-spacing: -0.01em; }
        /* Brand mark: plak/bay silhouette in a circle. Classes are scoped to
           .logo-mark so they don't collide with unrelated elements. Colors
           are driven by CSS variables with sensible defaults, so each theme
           can override individual layers without touching the inline SVG. */
        /* Each layer gets a pair of declarations — the sRGB hex applies
           everywhere, then the oklch override kicks in on browsers that
           understand it. Without the fallback, unsupported oklch() in a
           var() default makes the whole `fill`/`stroke` declaration invalid
           and SVG falls back to fill:black (which is what produces the
           solid-black disc + missing layers on Firefox <113). */
        .logo-mark { width: 34px; height: 34px; display: block; flex-shrink: 0; }
        .logo-mark .disc    { fill: var(--mark-disc, #f6f1e8); fill: var(--mark-disc, oklch(96% 0.015 85)); }
        .logo-mark .water   { fill: var(--mark-water, #2f36fa); fill: var(--mark-water, oklch(55% 0.18 255)); }
        .logo-mark .land    { fill: var(--mark-land, #8bb382); fill: var(--mark-land, oklch(72% 0.10 150)); }
        .logo-mark .horizon { stroke: var(--mark-horizon, #1c4c58); stroke: var(--mark-horizon, oklch(35% 0.08 190)); fill: none; }
        .logo-mark .wave    { stroke: var(--mark-wave, #1c4c58); stroke: var(--mark-wave, oklch(35% 0.08 190)); fill: none; }
        .logo-mark .ring    { stroke: var(--mark-ring, #1c4c58); stroke: var(--mark-ring, oklch(35% 0.08 190)); fill: none; stroke-width: 3; }
        html[data-theme="dark"] .logo-mark {
            --mark-disc:    #2b2925;
            --mark-disc:    oklch(22% 0.01 85);
            --mark-land:    #6a9d70;
            --mark-land:    oklch(64% 0.09 150);
            --mark-ring:    rgba(237, 238, 233, 0.72);
            --mark-ring:    color-mix(in oklab, var(--text) 72%, transparent);
            --mark-horizon: rgba(237, 238, 233, 0.72);
            --mark-horizon: color-mix(in oklab, var(--text) 72%, transparent);
            --mark-wave:    rgba(237, 238, 233, 0.65);
            --mark-wave:    color-mix(in oklab, var(--text) 65%, transparent);
        }
        /* Square icon button that cross-fades a moon (light mode) with a sun
           (dark mode). Both SVGs are stacked absolutely so the button size
           stays constant during the transition. */
        .theme-btn { display: inline-flex; align-items: center; justify-content: center; width: 32px; height: 32px; border-radius: 7px; border: 1px solid var(--panel-border); color: var(--text-dim); background: var(--panel); cursor: pointer; padding: 0; position: relative; flex: none; transition: border-color 120ms, background 120ms, color 120ms; }
        .theme-btn:hover { color: var(--text); background: var(--bg-sunk); }
        .theme-btn svg { width: 15px; height: 15px; position: absolute; transition: opacity 200ms ease, transform 300ms ease; }
        .theme-btn .icon-sun  { opacity: 0; transform: rotate(-40deg) scale(0.7); }
        .theme-btn .icon-moon { opacity: 1; transform: rotate(0) scale(1); }
        html[data-theme="dark"] .theme-btn .icon-sun  { opacity: 1; transform: rotate(0) scale(1); }
        html[data-theme="dark"] .theme-btn .icon-moon { opacity: 0; transform: rotate(40deg) scale(0.7); }

        /* Card */
        .card { background: var(--panel); border: 1px solid var(--panel-border); border-radius: var(--radius-lg); overflow: hidden; box-shadow: var(--shadow-lg); }
        .card-head { display: flex; align-items: center; justify-content: space-between; padding: 1.1rem 1.5rem; border-bottom: 1px solid var(--panel-border); gap: 1rem; }
        .card-title { font-family: var(--font-serif); font-style: italic; font-weight: 500; font-size: 1.45rem; margin: 0; letter-spacing: -0.01em; }
        .card-actions { display: flex; align-items: center; gap: 0.45rem; }

        /* Pills */
        .pill { display: inline-flex; align-items: center; gap: 0.4em; padding: 0.38rem 0.8rem; border-radius: var(--radius-pill); font-family: var(--font-mono); font-size: 0.8rem; font-weight: 400; border: 1px solid var(--panel-border); background: transparent; color: var(--text-dim); text-decoration: none; cursor: pointer; transition: color 120ms, border-color 120ms, background 120ms; white-space: nowrap; }
        .pill:hover { color: var(--text); border-color: var(--text-faint); }
        .pill.primary { background: var(--accent); border-color: var(--accent); color: var(--accent-fg); font-weight: 500; }
        .pill.primary:hover { filter: brightness(1.08); color: var(--accent-fg); border-color: var(--accent); }
        .pill:disabled { opacity: 0.5; cursor: not-allowed; }
        .pill-icon { width: 13px; height: 13px; flex: none; opacity: 0.85; }
        .pill:hover .pill-icon { opacity: 1; }

        /* Filter row */
        .filter-row { display: flex; align-items: center; gap: 0.5rem; padding: 0.6rem 1.5rem; border-bottom: 1px solid var(--panel-border); }
        .filter-input { flex: 1; min-width: 0; background: transparent; border: 0; color: var(--text); font-family: var(--font-mono); font-size: 0.88rem; padding: 0.15rem 0; outline: 0; }
        .filter-input::placeholder { color: var(--text-faint); }
        .filter-kbd { font-family: var(--font-mono); font-size: 0.68rem; color: var(--text-faint); border: 1px solid var(--panel-border); border-radius: 4px; padding: 0.1rem 0.35rem; }
        .filter-clear { background: transparent; border: 0; color: var(--text-dim); cursor: pointer; font-size: 1.05rem; line-height: 1; padding: 0 0.35rem; border-radius: 5px; }
        .filter-clear:hover { color: var(--text); background: var(--panel-hover); }
        /* Chip showing an active type-only filter (set by clicking a row pill).
           Separate state from the free-text filter so users can't hand-edit the
           "type:xxx" tokens and get into a weird parse state. */
        .filter-chip { display: inline-flex; align-items: center; gap: 0.1rem; padding: 0.18rem 0.22rem 0.18rem 0.65rem; background: var(--pill-wp-bg); color: var(--pill-wp-fg); border-radius: var(--radius-pill); font-family: var(--font-mono); font-size: 0.76rem; font-weight: 500; letter-spacing: 0.02em; white-space: nowrap; }
        .filter-chip-x { display: inline-flex; align-items: center; justify-content: center; width: 18px; height: 18px; background: transparent; border: 0; color: inherit; cursor: pointer; border-radius: 50%; font-size: 0.95rem; line-height: 1; padding: 0; }
        .filter-chip-x:hover { background: rgba(58, 151, 169, 0.28); background: color-mix(in oklch, var(--accent) 28%, transparent); }

        /* Add row */
        /* New-site alert: appears after creating a WP site so the one-time
           login is one click away, without hunting for the new row. */
        .new-site-alert { display: flex; align-items: center; gap: 0.75rem; padding: 0.75rem 1.25rem; border-bottom: 1px solid var(--panel-border); background: var(--bg-sunk); background: color-mix(in oklab, var(--accent) 12%, var(--panel)); color: var(--text); font-size: 0.92rem; }
        .new-site-alert-icon { display: inline-grid; place-items: center; width: 22px; height: 22px; border-radius: 50%; background: var(--accent); color: var(--accent-fg); flex: none; }
        .new-site-alert-text { flex: 1; min-width: 0; }
        .new-site-alert-text strong { font-family: var(--font-mono); font-weight: 500; }
        .new-site-alert-close { background: transparent; border: 0; color: var(--text-dim); cursor: pointer; font-size: 1.15rem; line-height: 1; padding: 0.25rem 0.55rem; border-radius: 5px; flex: none; }
        .new-site-alert-close:hover { color: var(--text); background: var(--panel-hover); }

        .add-row { position: relative; padding: 0.9rem 1.5rem; border-bottom: 1px solid var(--panel-border); background: var(--bg-sunk); }
        .add-row.is-creating { overflow: hidden; }
        /* Indeterminate progress stripe across the top while plak add is
           running — site creation takes 5-10s so we need a clear "working"
           cue beyond just the button text swap. Solid accent block slides
           across; a gradient-fade version blended with the row background
           and looked the wrong green. */
        .add-row.is-creating::before {
            content: '';
            position: absolute; top: 0; height: 3px; width: 30%;
            /* A thin 2px stripe of var(--accent) perceptually muted to olive
               against the cream bg-sunk; a brighter, more saturated teal at
               3px reads unambiguously as teal (same hue as the brand, just
               higher chroma so it survives the narrow band). */
            background: #3fb6cf;
            background: oklch(72% 0.15 190);
            animation: add-row-slide 1.3s linear infinite;
        }
        @keyframes add-row-slide {
            from { left: -30%; }
            to   { left: 100%; }
        }
        /* Inline spinner for the create button (reuses the .site-action-btn
           .btn-spinner pattern but scoped so pill button layout isn't altered). */
        .pill .btn-spinner { display: inline-block; width: 11px; height: 11px; border: 1.5px solid currentColor; border-top-color: transparent; border-radius: 50%; animation: spin 0.6s linear infinite; flex: none; }
        .add-row form { display: flex; align-items: center; gap: 0.75rem; flex-wrap: wrap; }
        .add-row input[type="text"] { background: var(--input-bg); border: 1px solid var(--panel-border); color: var(--text); font-family: var(--font-mono); font-size: 0.9rem; padding: 0.5rem 0.8rem; border-radius: var(--radius-md); min-width: 200px; flex: 1; }
        .add-row input[type="text"]:focus { outline: 0; border-color: var(--accent); }
        .add-row .plain-toggle { display: inline-flex; align-items: center; gap: 0.4rem; color: var(--text-dim); font-size: 0.85rem; cursor: pointer; }
        .add-row .plain-toggle input { accent-color: var(--accent); }

        /* Site list — one grid on the <ul>, rows inherit its columns via
           subgrid so type/modified/size/actions align vertically across rows
           instead of each row sizing independently. */
        .site-list { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: 1fr auto auto auto auto; column-gap: 0.9rem; }
        .site-row { display: grid; grid-column: 1 / -1; grid-template-columns: subgrid; align-items: center; padding: 0.8rem 1.5rem; border-bottom: 1px solid var(--panel-border); transition: background 100ms; cursor: pointer; }
        .site-row:last-child { border-bottom: 0; }
        .site-row:hover { background: var(--panel-hover); }
        .site-domain { font-family: var(--font-mono); font-size: 0.88rem; color: var(--text-dim); text-decoration: none; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .site-domain .host-accent { color: var(--accent); }
        .site-domain:hover { color: var(--accent); }
        .site-domain mark { background: rgba(58, 151, 169, 0.28); background: color-mix(in oklch, var(--accent) 28%, transparent); color: inherit; padding: 0 1px; border-radius: 3px; }
        .site-type { display: inline-flex; justify-content: center; min-width: 64px; padding: 0.2rem 0.55rem; border-radius: var(--radius-pill); font-family: var(--font-mono); font-size: 0.68rem; font-weight: 500; letter-spacing: 0.08em; text-transform: uppercase; cursor: pointer; user-select: none; transition: filter 120ms; }
        .site-type:hover { filter: brightness(1.15); }
        .site-type.wp { background: var(--pill-wp-bg); color: var(--pill-wp-fg); }
        .site-type.static { background: var(--pill-static-bg); color: var(--pill-static-fg); }
        .site-modified { font-family: var(--font-mono); font-size: 0.8rem; color: var(--text-faint); min-width: 44px; text-align: right; }
        .site-size { font-family: var(--font-mono); font-size: 0.82rem; color: var(--text-dim); min-width: 64px; text-align: right; }
        .site-actions { display: flex; gap: 0.15rem; opacity: 0; transition: opacity 100ms; }
        .site-row:hover .site-actions, .site-row:focus-within .site-actions { opacity: 1; }
        /* Fixed button size + both children stacked in one grid cell. Since
           grid-area "stack" collocates them at the same position and size is
           locked by width/height, toggling opacity on .loading can't shift
           any neighbour. */
        .site-action-btn { display: inline-grid; grid-template-areas: "stack"; place-items: center; box-sizing: border-box; width: 3.5em; height: 1.75em; padding: 0; background: transparent; border: 0; color: var(--text-dim); cursor: pointer; border-radius: 7px; font-family: var(--font-mono); font-size: 0.78rem; line-height: 1; }
        .site-action-btn > * { grid-area: stack; }
        .site-action-btn:hover { background: var(--panel-border); color: var(--text); }
        .site-action-btn.danger:hover { color: var(--danger); }
        .site-action-btn:disabled { cursor: wait; }
        .site-action-btn .btn-spinner { width: 10px; height: 10px; border: 1.5px solid currentColor; border-top-color: transparent; border-radius: 50%; animation: spin 0.6s linear infinite; opacity: 0; pointer-events: none; }
        .site-action-btn.loading .btn-label { opacity: 0; }
        .site-action-btn.loading .btn-spinner { opacity: 1; }

        /* Empty + loading states — scoped to direct children of .site-list so
           the global .loading class doesn't leak into unrelated elements
           (notably .site-action-btn.loading, which uses its own state class). */
        .site-list > .empty, .site-list > .loading { grid-column: 1 / -1; padding: 3rem 1.5rem; text-align: center; color: var(--text-dim); }
        .empty-hint { margin-top: 0.35rem; font-family: var(--font-mono); font-size: 0.82rem; color: var(--text-faint); }
        .empty-hint code { background: var(--panel-hover); padding: 0.1rem 0.4rem; border-radius: 5px; }

        /* Footer */
        .card-foot { display: flex; align-items: center; justify-content: space-between; padding: 0.75rem 1.5rem; border-top: 1px solid var(--panel-border); color: var(--text-dim); font-family: var(--font-mono); font-size: 0.78rem; gap: 1rem; flex-wrap: wrap; }
        .services { display: flex; gap: 1.1rem; flex-wrap: wrap; }
        .dot { display: inline-flex; align-items: center; gap: 0.45rem; color: var(--text-dim); text-decoration: none; background: transparent; border: 0; padding: 0; font-family: inherit; font-size: inherit; cursor: default; }
        .dot.link, .dot[role="button"] { cursor: pointer; }
        .dot.link:hover, .dot[role="button"]:hover { color: var(--text); }
        .dot::before { content: ''; width: 6px; height: 6px; border-radius: 50%; background: var(--accent); box-shadow: 0 0 6px rgba(58, 151, 169, 0.6); box-shadow: 0 0 6px color-mix(in oklch, var(--accent) 60%, transparent); }
        .totals { display: inline-flex; align-items: center; gap: 0.5rem; }
        .refresh-btn { background: transparent; border: 0; color: var(--text-dim); cursor: pointer; padding: 0.15rem 0.35rem; font-size: 0.95rem; border-radius: 5px; }
        .refresh-btn:hover { color: var(--text); background: var(--panel-hover); }
        .refresh-btn.spinning { animation: spin 1s linear infinite; pointer-events: none; }
        @keyframes spin { to { transform: rotate(360deg); } }

        /* Modal */
        .modal-backdrop { position: fixed; inset: 0; background: rgba(0,0,0,0.55); display: grid; place-items: center; z-index: 80; padding: 1rem; }
        html[data-theme="light"] .modal-backdrop { background: rgba(20,20,18,0.35); }
        .modal { background: var(--panel); border: 1px solid var(--panel-border); border-radius: var(--radius-lg); padding: 1.5rem; min-width: min(420px, 90vw); max-width: 540px; }
        .modal h3 { font-family: var(--font-serif); font-style: italic; font-weight: 500; font-size: 1.25rem; margin: 0 0 0.3rem; }
        .modal .modal-sub { color: var(--text-dim); font-size: 0.85rem; margin: 0 0 1rem; }
        .modal pre { background: var(--input-bg); border: 1px solid var(--panel-border); border-radius: var(--radius-md); padding: 0.85rem 1rem; margin: 0; font-family: var(--font-mono); font-size: 0.82rem; color: var(--text); overflow-x: auto; }
        .db-creds { background: var(--input-bg); border: 1px solid var(--panel-border); border-radius: var(--radius-md); padding: 0.9rem 1rem; display: flex; flex-direction: column; gap: 0.7rem; }
        .db-cred-row { display: grid; grid-template-columns: 85px 1fr; align-items: baseline; gap: 0.75rem; font-family: var(--font-mono); font-size: 0.82rem; }
        .db-cred-label { color: var(--text-dim); font-weight: 500; }
        .db-cred-value { color: var(--text); word-break: break-all; background: transparent; padding: 0; }
        .modal .modal-foot { margin-top: 1rem; display: flex; justify-content: space-between; align-items: center; color: var(--text-faint); font-family: var(--font-mono); font-size: 0.75rem; }

        /* Snackbar */
        /* Centered via auto margins + fit-content width, NOT transform — Alpine
           writes transform inline during x-transition, which would wipe out a
           translateX(-50%) centering and slide the snackbar in from the edge. */
        .snackbar { position: fixed; bottom: 1.5rem; left: 0; right: 0; margin-inline: auto; width: max-content; max-width: 90vw; background: var(--text); color: var(--bg); padding: 0.7rem 1.15rem; border-radius: 10px; font-size: 0.88rem; z-index: 200; box-shadow: 0 10px 30px rgba(0,0,0,0.25); }
        .snackbar.error { background: var(--danger); color: white; }

        /* Responsive */
        @media (max-width: 620px) {
            body { padding: 1.25rem 0.75rem 3rem; }
            .card-head { padding: 0.9rem 1rem; flex-wrap: wrap; }
            .card-actions { width: 100%; justify-content: flex-end; }
            .site-list { grid-template-columns: 1fr auto auto; column-gap: 0.6rem; }
            .site-row { padding: 0.7rem 1rem; }
            .site-size, .site-modified { display: none; }
            .site-actions { opacity: 1; }
            .add-row { padding: 0.8rem 1rem; }
            .card-foot { padding: 0.75rem 1rem; }
        }

        [x-cloak] { display: none !important; }
        .site-detail { margin-top: 1rem; padding: 1.1rem 1.25rem; }
        .detail-head { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.75rem; }
        .detail-title { margin: 0; font-family: var(--font-serif); font-size: 1.3rem; }
        .detail-grid { display: grid; grid-template-columns: auto 1fr; gap: 0.4rem 1rem; margin: 0 0 1rem; }
        .detail-grid dt { color: var(--text-dim); font-size: 0.85rem; }
        .detail-grid dd { margin: 0; word-break: break-word; }
        .detail-grid dd code { font-family: var(--font-mono); font-size: 0.82rem; }
        .detail-actions { display: flex; flex-wrap: wrap; gap: 0.5rem; }
        .detail-actions .site-action-btn { text-decoration: none; }
        .components { margin-top: 1.25rem; border-top: 1px solid var(--panel-border); padding-top: 1rem; }
        .components-head { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.6rem; }
        .components-tabs { display: flex; gap: 0.35rem; }
        .comp-tab { background: var(--pill-bg); color: var(--text-dim); border: 0; border-radius: var(--radius-pill); padding: 0.3rem 0.8rem; cursor: pointer; font: inherit; }
        .comp-tab.active { background: var(--accent); color: var(--accent-fg); }
        .comp-hint { color: var(--text-dim); font-size: 0.8rem; margin: 0 0 0.5rem; }
        .comp-error { color: var(--danger); font-size: 0.85rem; margin: 0 0 0.5rem; }
        .comp-loading { color: var(--text-dim); font-size: 0.85rem; }
        .comp-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 0.4rem; }
        .comp-row { display: grid; grid-template-columns: 1fr auto auto; align-items: center; gap: 0.6rem; padding: 0.5rem 0; border-bottom: 1px solid var(--panel-border); }
        .comp-main { display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; min-width: 0; }
        .comp-title { font-weight: 500; }
        .comp-slug { color: var(--text-faint); font-family: var(--font-mono); font-size: 0.75rem; }
        .comp-version { color: var(--text-dim); font-family: var(--font-mono); font-size: 0.78rem; }
        .comp-actions { display: flex; gap: 0.35rem; flex-wrap: wrap; justify-content: flex-end; }
        .comp-badge { font-size: 0.7rem; border-radius: var(--radius-pill); padding: 0.1rem 0.5rem; background: var(--pill-bg); color: var(--text-dim); }
        .comp-badge.active { background: var(--pill-wp-bg); color: var(--pill-wp-fg); }
        .comp-badge.mu { background: var(--pill-static-bg); color: var(--pill-static-fg); }
        .comp-badge.update { background: var(--accent); color: var(--accent-fg); }
        .agent-badge { font-size: 0.7rem; border-radius: var(--radius-pill); padding: 0.15rem 0.55rem; background: var(--pill-wp-bg); color: var(--pill-wp-fg); white-space: nowrap; }

        /* WP-CLI console inside a site's tools panel. */
        .console-form { display: flex; align-items: center; gap: 0.5rem; margin: 0.25rem 0 0.6rem; }
        .console-input { background: var(--input-bg); border: 1px solid var(--panel-border); border-radius: var(--radius-md); padding: 0.5rem 0.7rem; }
        .console-input:focus { border-color: var(--accent); }
        .console-out { background: var(--input-bg); border: 1px solid var(--panel-border); border-radius: var(--radius-md); padding: 0.8rem 0.9rem; margin: 0 0 0.7rem; font-family: var(--font-mono); font-size: 0.8rem; color: var(--text); white-space: pre-wrap; word-break: break-word; max-height: 22rem; overflow: auto; }
        .console-history { display: flex; flex-wrap: wrap; gap: 0.35rem; }
        .console-hist-btn { background: var(--pill-bg); color: var(--text-dim); border: 0; border-radius: var(--radius-pill); padding: 0.2rem 0.6rem; cursor: pointer; font-family: var(--font-mono); font-size: 0.72rem; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .console-hist-btn:hover { color: var(--text); background: var(--panel-hover); }

        /* Logs and traffic inside a site's diagnostics panel. */
        .log-controls { display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; margin-bottom: 0.6rem; }
        .log-select { background: var(--input-bg); border: 1px solid var(--panel-border); color: var(--text); font-family: var(--font-mono); font-size: 0.76rem; border-radius: var(--radius-md); padding: 0.3rem 0.5rem; }
        .log-search { background: var(--input-bg); border: 1px solid var(--panel-border); border-radius: var(--radius-md); padding: 0.35rem 0.6rem; flex: 1; min-width: 120px; }
        .log-search:focus { border-color: var(--accent); outline: 0; }
        .log-list { list-style: none; margin: 0; padding: 0; max-height: 26rem; overflow: auto; }
        .log-entry { padding: 0.45rem 0; border-bottom: 1px solid var(--panel-border); font-family: var(--font-mono); font-size: 0.78rem; }
        .log-line { display: flex; align-items: baseline; gap: 0.55rem; flex-wrap: wrap; }
        .log-level { text-transform: uppercase; font-size: 0.65rem; letter-spacing: 0.06em; padding: 0.05rem 0.4rem; border-radius: var(--radius-pill); background: var(--pill-bg); color: var(--text-dim); flex: none; }
        .log-entry.lvl-error .log-level { background: var(--danger); color: #fff; }
        .log-entry.lvl-warn .log-level { background: var(--pill-wp-bg); color: var(--pill-wp-fg); }
        .log-time { color: var(--text-faint); flex: none; }
        .log-count { color: var(--accent); flex: none; }
        .log-msg { color: var(--text); word-break: break-word; }
        .log-trace { margin: 0.3rem 0 0; }
        .log-trace summary { color: var(--text-dim); cursor: pointer; font-size: 0.72rem; }
        .log-trace pre { margin: 0.3rem 0 0; padding: 0.5rem 0.7rem; background: var(--input-bg); border-radius: var(--radius-md); overflow-x: auto; font-size: 0.72rem; color: var(--text-dim); }
        .traffic-cards { display: flex; flex-wrap: wrap; gap: 0.6rem; margin-bottom: 0.8rem; }
        .traffic-card { background: var(--input-bg); border: 1px solid var(--panel-border); border-radius: var(--radius-md); padding: 0.55rem 0.8rem; min-width: 88px; display: flex; flex-direction: column; gap: 0.1rem; }
        .traffic-num { font-family: var(--font-mono); font-size: 1.05rem; color: var(--text); }
        .traffic-label { font-size: 0.7rem; color: var(--text-dim); text-transform: uppercase; letter-spacing: 0.05em; }
        .traffic-classes { display: flex; flex-wrap: wrap; gap: 0.35rem; margin-bottom: 0.5rem; }
        .traffic-cols { display: grid; grid-template-columns: 1fr 1fr; gap: 1.2rem; }
        @media (max-width: 620px) { .traffic-cols { grid-template-columns: 1fr; } }
        .traffic-h { font-size: 0.8rem; font-family: var(--font-sans); font-weight: 600; color: var(--text-dim); margin: 0 0 0.35rem; text-transform: uppercase; letter-spacing: 0.04em; }
        .traffic-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 0.25rem; }
        .traffic-list li { display: flex; justify-content: space-between; gap: 0.6rem; font-size: 0.78rem; }
        .traffic-list code { color: var(--text-dim); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .traffic-list span { color: var(--text-faint); font-family: var(--font-mono); flex: none; }

        /* Mail inbox. */
        .mail-modal { min-width: min(720px, 94vw); max-width: 860px; max-height: 86vh; display: flex; flex-direction: column; }
        .mail-head { display: flex; align-items: center; justify-content: space-between; gap: 0.75rem; margin-bottom: 0.6rem; }
        .mail-head h3 { margin: 0; }
        .mail-scope { color: var(--text-dim); font-family: var(--font-mono); font-size: 0.8rem; font-style: normal; }
        .mail-head-actions { display: flex; align-items: center; gap: 0.4rem; }
        .mail-controls { margin-bottom: 0.5rem; }
        .mail-list { list-style: none; margin: 0; padding: 0; overflow: auto; max-height: 60vh; }
        .mail-row { display: grid; grid-template-columns: 1fr auto; gap: 0.6rem; align-items: center; padding: 0.55rem 0; border-bottom: 1px solid var(--panel-border); }
        .mail-row.unread .mail-subject { font-weight: 600; color: var(--text); }
        .mail-open { display: flex; flex-direction: column; gap: 0.1rem; text-align: left; background: transparent; border: 0; color: inherit; cursor: pointer; padding: 0; min-width: 0; font: inherit; }
        .mail-from { font-family: var(--font-mono); font-size: 0.76rem; color: var(--text-dim); }
        .mail-subject { font-size: 0.9rem; color: var(--text-dim); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .mail-snippet { font-size: 0.78rem; color: var(--text-faint); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .mail-row-meta { display: flex; align-items: center; gap: 0.4rem; flex: none; }
        .mail-date { font-family: var(--font-mono); font-size: 0.72rem; color: var(--text-faint); white-space: nowrap; }
        .mail-detail-head { display: flex; align-items: center; gap: 0.6rem; margin-bottom: 0.4rem; }
        .mail-detail-subject { font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .mail-detail-meta { font-family: var(--font-mono); font-size: 0.76rem; color: var(--text-dim); margin: 0 0 0.5rem; word-break: break-word; }
        .mail-links { display: flex; flex-wrap: wrap; gap: 0.35rem; margin-bottom: 0.5rem; max-height: 5.5rem; overflow: auto; }
        .mail-imgtoggle { margin-bottom: 0.5rem; }
        .mail-frame { width: 100%; height: 55vh; border: 1px solid var(--panel-border); border-radius: var(--radius-md); background: #fff; }

        /* Backups, jobs and the import form. */
        .job-status { display: flex; align-items: center; gap: 0.5rem; margin-top: 0.6rem; font-family: var(--font-mono); font-size: 0.8rem; color: var(--text-dim); }
        .job-status .btn-spinner { width: 11px; height: 11px; border: 1.5px solid currentColor; border-top-color: transparent; border-radius: 50%; animation: spin 0.6s linear infinite; display: inline-block; opacity: 1; flex: none; }
        .import-form { display: flex; flex-direction: column; gap: 0.7rem; }
        .import-file { color: var(--text-dim); font-family: var(--font-mono); font-size: 0.8rem; }
        .import-form .modal-foot { margin-top: 0.2rem; }
    </style>
</head>
<body x-data="dashboard" x-init="init()">
    <div class="wrap">
        <nav class="nav">
            <a class="logo" href="/">Plak CLI</a>
            <button class="theme-btn" @click="toggleTheme()" :title="theme === 'light' ? 'Switch to dark mode' : 'Switch to light mode'" aria-label="Toggle theme">
                <svg class="icon-moon" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13.5 9.2A5.5 5.5 0 0 1 6.8 2.5a5.75 5.75 0 1 0 6.7 6.7Z"/></svg>
                <svg class="icon-sun" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="8" cy="8" r="3"/><path d="M8 1.5v1.8M8 12.7v1.8M2.6 2.6l1.3 1.3M12.1 12.1l1.3 1.3M1.5 8h1.8M12.7 8h1.8M2.6 13.4l1.3-1.3M12.1 3.9l1.3-1.3"/></svg>
            </button>
        </nav>

        <section class="card">
            <header class="card-head">
                <h1 class="card-title">Sites</h1>
                <div class="card-actions">
                    <button class="pill" @click="cycleSort()" :title="'Sort by — click to cycle'" x-text="'sort: ' + sort"></button>
                    <a class="pill" href="https://db.plak.localhost<?= $__plak_site_port_suffix ?>" target="_blank" rel="noopener" title="Open Adminer">
                        <svg class="pill-icon" width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><ellipse cx="8" cy="3.5" rx="5" ry="1.5"/><path d="M3 3.5v9c0 .83 2.24 1.5 5 1.5s5-.67 5-1.5v-9"/><path d="M3 8c0 .83 2.24 1.5 5 1.5s5-.67 5-1.5"/></svg>
                        db
                    </a>
                    <a class="pill" href="https://mail.plak.localhost<?= $__plak_site_port_suffix ?>" target="_blank" rel="noopener" title="Open Mailpit">
                        <svg class="pill-icon" width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="2" y="4" width="12" height="9" rx="1.5"/><path d="M2.5 5 8 9l5.5-4"/></svg>
                        mail
                    </a>
                    <button class="pill" @click="openMail('all')" title="Read captured mail in the dashboard">inbox</button>
                    <button class="pill" @click="openImport()" title="Create a site from a backup archive">import</button>
                    <button class="pill primary" @click="toggleAdd()" x-text="adding ? 'cancel' : '+ add site'"></button>
                </div>
            </header>

            <template x-for="alert in alerts" :key="alert.id">
                <div class="new-site-alert" x-transition.opacity>
                    <span class="new-site-alert-icon" aria-hidden="true">
                        <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8.2l3 3 7-7"/></svg>
                    </span>
                    <div class="new-site-alert-text">
                        <strong x-text="alert.name + '.localhost'"></strong> is ready.
                    </div>
                    <template x-if="!alert.isPlain">
                        <button class="pill primary" :disabled="alert.isLoggingIn" @click="loginToNewSite(alert)" x-text="alert.isLoggingIn ? 'opening…' : 'log in to admin'"></button>
                    </template>
                    <template x-if="alert.isPlain">
                        <a class="pill primary" :href="'https://' + alert.name + '.localhost' + PORT_SUFFIX" target="_blank" rel="noopener" @click="dismissAlert(alert.id)">open site</a>
                    </template>
                    <button class="new-site-alert-close" @click="dismissAlert(alert.id)" aria-label="Dismiss" title="Dismiss">×</button>
                </div>
            </template>

            <div class="filter-row">
                <span class="filter-chip" x-show="typeFilter" x-transition.opacity aria-label="Active type filter" style="display: none;">
                    <span x-text="typeFilterLabel"></span>
                    <button type="button" class="filter-chip-x" @click="typeFilter = null; $refs.filterInput.focus()" aria-label="Remove type filter" title="Remove">×</button>
                </span>
                <input
                    class="filter-input"
                    type="text"
                    x-model="filter"
                    x-ref="filterInput"
                    placeholder="filter sites by name or type…"
                    spellcheck="false"
                    autocomplete="off"
                    autocapitalize="off"
                    autocorrect="off"
                    @keydown.escape.prevent="filter = ''; $event.target.blur()"
                    aria-label="Filter sites"
                >
                <span class="filter-kbd" x-show="!filter && !typeFilter" aria-hidden="true">/</span>
                <button class="filter-clear" x-show="filter || typeFilter" @click="clearAllFilters(); $refs.filterInput.focus()" aria-label="Clear filter" title="Clear all (Esc)">×</button>
            </div>

            <div x-show="adding" x-transition.opacity class="add-row" :class="{ 'is-creating': newSite.isLoading }" style="display: none;">
                <form @submit.prevent="addSite()">
                    <input type="text" x-model="newSite.name" @input="newSite.name = newSite.name.toLowerCase().replace(/[^a-z0-9-]/g, '')" placeholder="site-name" required :disabled="newSite.isLoading" x-ref="newSiteInput">
                    <label class="plain-toggle">
                        <input type="checkbox" x-model="newSite.isPlain" :disabled="newSite.isLoading">
                        plain (no WordPress)
                    </label>
                    <label class="plain-toggle" x-show="!newSite.isPlain" x-cloak title="Install WP-MCP and register the site with wp-mcp-cli">
                        <input type="checkbox" x-model="newSite.agent" :disabled="newSite.isLoading">
                        agent-ready (WP-MCP)
                    </label>
                    <button class="pill primary" type="submit" :disabled="!newSite.name || newSite.isLoading">
                        <span class="btn-spinner" x-show="newSite.isLoading" aria-hidden="true" style="display: none;"></span>
                        <span x-text="newSite.isLoading ? 'creating…' : 'create'"></span>
                    </button>
                </form>
            </div>

            <ul class="site-list">
                <template x-for="site in filteredSites" :key="site.name">
                    <li class="site-row" @click="openSite(site)">
                        <a class="site-domain" :href="site.domain" target="_blank" rel="noopener" @click.stop x-html="highlightedDomain(site.domain, filter)"></a>
                        <span class="site-type" :class="site.type === 'WordPress' ? 'wp' : 'static'" @click.stop="typeFilter = site.type" :title="'Filter to ' + (site.type === 'WordPress' ? 'WordPress' : 'static') + ' sites'" x-text="site.multisite_mode ? 'NETWORK' : (site.type === 'WordPress' ? 'WP' : 'STATIC')"></span>
                        <span class="site-modified" x-text="formatRelative(site.modified_at)" :title="site.modified_at ? new Date(site.modified_at * 1000).toLocaleString() : ''"></span>
                        <span class="site-size" x-text="formatSize(site.size_bytes)"></span>
                        <div class="site-actions">
                            <template x-if="site.type === 'WordPress' && !site.agent_ready">
                                <button class="site-action-btn" :class="{ loading: site.isPreparingAgent }" @click.stop="prepareAgent(site)" :disabled="site.isPreparingAgent" :title="'Make ' + site.name + ' agent-ready (WP-MCP)'">
                                    <span class="btn-label" x-text="site.isPreparingAgent ? 'preparing…' : 'agent'"></span>
                                    <span class="btn-spinner" aria-hidden="true"></span>
                                </button>
                            </template>
                            <template x-if="site.type === 'WordPress' && site.agent_ready">
                                <span class="agent-badge" title="Agent-ready (WP-MCP)">agent ✓</span>
                            </template>
                            <template x-if="site.type === 'WordPress'">
                                <button class="site-action-btn" :class="{ loading: site.isLoggingIn }" @click.stop="getLoginLink(site.name)" :disabled="site.isLoggingIn" :title="'One-time admin login for ' + site.name">
                                    <span class="btn-label">login</span>
                                    <span class="btn-spinner" aria-hidden="true"></span>
                                </button>
                            </template>
                            <button class="site-action-btn" @click.stop="copyPath(site.full_path)" title="Copy site path to clipboard">path</button>
                            <button class="site-action-btn danger" @click.stop="deleteSite(site.name)" :title="'Delete ' + site.name">delete</button>
                        </div>
                    </li>
                </template>
                <template x-if="isLoading">
                    <li class="loading">Loading sites…</li>
                </template>
                <template x-if="!isLoading && sites.length === 0">
                    <li class="empty">
                        <div>No sites yet.</div>
                        <div class="empty-hint">Click <em>+ add site</em>, or run <code>plak add myblog</code>.</div>
                    </li>
                </template>
                <template x-if="!isLoading && sites.length > 0 && filteredSites.length === 0">
                    <li class="empty">
                        <div>No matches for <code x-text="filter"></code>.</div>
                        <div class="empty-hint">Press Esc to clear.</div>
                    </li>
                </template>
            </ul>

            <footer class="card-foot">
                <div class="services">
                    <span class="dot" title="Caddy is serving this page — it's running">caddy</span>
                    <button type="button" class="dot link" @click="showDbModal = true" title="Database credentials">mariadb</button>
                    <a class="dot link" :href="mailpitUrl" target="_blank" rel="noopener" title="Open Mailpit">mailpit</a>
                </div>
                <div class="totals">
                    <span x-text="siteCountLabel"></span>
                    <span x-show="totalBytes > 0" x-text="'· ' + formatSize(totalBytes)"></span>
                    <button type="button" class="refresh-btn" :class="{ spinning: isRefreshingSizes }" @click="refreshSizes()" :disabled="isRefreshingSizes" :title="isRefreshingSizes ? 'Refreshing…' : 'Refresh disk sizes'">↻</button>
                </div>
            </footer>
        </section>
    </div>

    <section class="card site-detail" x-show="detailSite" x-cloak>
        <template x-if="detailSite">
            <div>
                <div class="detail-head">
                    <button type="button" class="site-action-btn" @click="closeSiteDetail()" title="Back to sites">← back</button>
                    <h2 class="detail-title" x-text="detailSite.name"></h2>
                    <span class="site-type" :class="detailSite.type === 'WordPress' ? 'wp' : 'static'"
                        x-text="detailSite.type === 'WordPress' ? 'WP' : 'STATIC'"></span>
                </div>
                <dl class="detail-grid">
                    <dt>URL</dt>
                    <dd><a :href="detailSite.domain" target="_blank" rel="noopener" x-text="detailSite.domain"></a></dd>
                    <dt>Path</dt>
                    <dd><button type="button" class="site-action-btn" @click="copyPath(detailSite.full_path)" title="Copy path">copy</button>
                        <code x-text="detailSite.full_path"></code></dd>
                    <dt>Size</dt>
                    <dd x-text="formatSize(detailSite.size_bytes)"></dd>
                    <dt>Modified</dt>
                    <dd x-text="detailSite.modified_at ? new Date(detailSite.modified_at * 1000).toLocaleString() : '—'"></dd>
                    <template x-if="detailSite.type === 'WordPress'">
                        <template x-if="detailInfo">
                            <template>
                                <dt>WordPress</dt>
                                <dd x-text="detailInfo.wp_version || '—'"></dd>
                                <dt>Plugins</dt>
                                <dd x-text="detailInfo.plugins !== null ? detailInfo.plugins + ' installed' : '—'"></dd>
                            </template>
                        </template>
                    </template>
                </dl>
                <template x-if="detailInfo && detailInfo.network">
                    <section>
                        <h3 x-text="'Multisite · ' + detailInfo.network.mode"></h3>
                        <template x-for="subsite in detailInfo.network.sites" :key="subsite.id">
                            <p><span x-text="'#' + subsite.id + ' '"></span><a :href="subsite.url" target="_blank" rel="noopener" x-text="subsite.url"></a>
                                <code x-text="'plak login ' + detailSite.name + ' --subsite ' + subsite.id"></code></p>
                        </template>
                    </section>
                </template>
                <div class="detail-actions">
                    <a class="site-action-btn" :href="detailSite.domain" target="_blank" rel="noopener">open site</a>
                    <template x-if="detailSite.type === 'WordPress'">
                        <button class="site-action-btn" @click="getLoginLink(detailSite.name)">login</button>
                    </template>
                    <a class="site-action-btn" :href="adminerUrl" target="_blank" rel="noopener">database</a>
                    <a class="site-action-btn" :href="mailpitUrl" target="_blank" rel="noopener">mail</a>
                    <button class="site-action-btn" @click="openMail('site', detailSite.name)">inbox</button>
                    <template x-if="detailSite.type === 'WordPress'">
                        <button class="site-action-btn" :class="{ loading: detailLoading }" @click="loadSiteInfo(detailSite.name)" :disabled="detailLoading">
                            <span class="btn-label" x-text="detailLoading ? 'loading…' : 'refresh info'"></span>
                        </button>
                    </template>
                </div>

                <template x-if="detailSite.type === 'WordPress'">
                    <div class="components">
                        <div class="components-head">
                            <div class="components-tabs">
                                <button type="button" class="comp-tab" :class="{ active: compTab === 'plugins' }" @click="setCompTab('plugins')">plugins</button>
                                <button type="button" class="comp-tab" :class="{ active: compTab === 'themes' }" @click="setCompTab('themes')">themes</button>
                            </div>
                            <button type="button" class="site-action-btn" :class="{ loading: compLoading }" @click="loadComponents(detailSite.name, { check: true })" :disabled="compLoading" title="Ask WordPress.org for available updates">
                                <span class="btn-label" x-text="compLoading ? 'checking…' : 'check updates'"></span>
                            </button>
                        </div>

                        <p class="comp-hint" x-show="compChecked" x-cloak>Update check run against WordPress.org.</p>
                        <p class="comp-error" x-show="compError" x-text="compError" x-cloak></p>
                        <p class="comp-loading" x-show="compLoading" x-cloak>Reading <span x-text="compTab"></span>…</p>

                        <ul class="comp-list" x-show="!compLoading && !compError" x-cloak>
                            <template x-for="item in compItems" :key="item.name">
                                <li class="comp-row">
                                    <div class="comp-main">
                                        <span class="comp-title" x-text="item.title || item.name"></span>
                                        <span class="comp-slug" x-text="item.name"></span>
                                        <span class="comp-badge" :class="compStatusClass(item)" x-text="item.status"></span>
                                        <span class="comp-badge update" x-show="updateAvailable(item)" x-cloak
                                            x-text="'→ ' + (item.update_version || 'update')"></span>
                                    </div>
                                    <span class="comp-version" x-text="item.version || '—'"></span>
                                    <div class="comp-actions">
                                        <template x-if="compTab === 'plugins' && item.status !== 'must-use'">
                                            <button type="button" class="site-action-btn" :disabled="compBusy[item.name] || item.status === 'active'"
                                                @click="componentOp('plugins', item, 'activate')"
                                                :title="item.status === 'active' ? 'Already active' : 'Activate ' + item.name">activate</button>
                                        </template>
                                        <template x-if="compTab === 'plugins' && item.status !== 'must-use'">
                                            <button type="button" class="site-action-btn" :disabled="compBusy[item.name] || item.status !== 'active'"
                                                @click="componentOp('plugins', item, 'deactivate')"
                                                :title="item.status !== 'active' ? 'Not active' : 'Deactivate ' + item.name">deactivate</button>
                                        </template>
                                        <span class="comp-badge mu" x-show="item.status === 'must-use'" x-cloak>must-use · cannot deactivate</span>
                                        <template x-if="compTab === 'themes' && item.status !== 'active'">
                                            <button type="button" class="site-action-btn" :disabled="compBusy[item.name]"
                                                @click="componentOp('themes', item, 'activate')">activate</button>
                                        </template>
                                        <span class="comp-badge mu" x-show="compTab === 'themes' && item.status === 'active'" x-cloak>active theme · cannot delete</span>
                                        <template x-if="item.update === 'available' || item.update === '1'">
                                            <button type="button" class="site-action-btn" :disabled="compBusy[item.name]"
                                                @click="componentOp(compTab, item, 'update')">update</button>
                                        </template>
                                        <button type="button" class="site-action-btn danger" :disabled="compBusy[item.name] || canDelete(item) !== true"
                                            @click="componentDelete(compTab, item)"
                                            :title="deleteTitle(compTab, item)"
                                            x-text="compArm === item.name ? 'confirm delete?' : 'delete'"></button>
                                    </div>
                                </li>
                            </template>
                            <li class="empty" x-show="compItems.length === 0" x-cloak>No <span x-text="compTab"></span>.</li>
                        </ul>
                    </div>
                </template>

                <template x-if="detailSite.type === 'WordPress'">
                    <div class="components tools">
                        <div class="components-head">
                            <div class="components-tabs">
                                <button type="button" class="comp-tab" :class="{ active: toolTab === 'users' }" @click="setToolTab('users')">users</button>
                                <button type="button" class="comp-tab" :class="{ active: toolTab === 'cron' }" @click="setToolTab('cron')">cron</button>
                                <button type="button" class="comp-tab" :class="{ active: toolTab === 'console' }" @click="setToolTab('console')">console</button>
                            </div>
                            <button type="button" class="site-action-btn" x-show="toolTab !== 'console'" :class="{ loading: toolLoading }" @click="loadTool(detailSite.name)" :disabled="toolLoading">
                                <span class="btn-label" x-text="toolLoading ? 'loading…' : 'refresh'"></span>
                            </button>
                        </div>

                        <p class="comp-error" x-show="toolError" x-text="toolError" x-cloak></p>
                        <p class="comp-loading" x-show="toolLoading && toolTab !== 'console'" x-cloak>Reading <span x-text="toolTab"></span>…</p>

                        <ul class="comp-list" x-show="toolTab === 'users' && !toolLoading && !toolError" x-cloak>
                            <template x-for="u in toolItems" :key="u.ID">
                                <li class="comp-row">
                                    <div class="comp-main">
                                        <span class="comp-title" x-text="u.display_name || u.user_login"></span>
                                        <span class="comp-slug" x-text="u.user_login"></span>
                                        <span class="comp-badge active" x-text="u.roles || '—'"></span>
                                        <span class="comp-version" x-text="u.user_email"></span>
                                    </div>
                                    <span class="comp-version" x-text="'#' + u.ID"></span>
                                    <div class="comp-actions">
                                        <button type="button" class="site-action-btn" :disabled="toolBusy[u.user_login]" @click="userLogin(u)" :title="'One-time login for ' + u.user_login">login</button>
                                    </div>
                                </li>
                            </template>
                            <li class="empty" x-show="toolItems.length === 0" x-cloak>No users.</li>
                        </ul>

                        <ul class="comp-list" x-show="toolTab === 'cron' && !toolLoading && !toolError" x-cloak>
                            <li class="comp-row" x-show="toolItems.length > 0">
                                <div class="comp-main"><span class="comp-title">All due events</span></div>
                                <span class="comp-version"></span>
                                <div class="comp-actions">
                                    <button type="button" class="site-action-btn" :disabled="toolBusy['--due-now']" @click="runCron('--due-now')">run due now</button>
                                </div>
                            </li>
                            <template x-for="e in toolItems" :key="e.hook + '|' + e.next_run_gmt">
                                <li class="comp-row">
                                    <div class="comp-main">
                                        <span class="comp-title" x-text="e.hook"></span>
                                        <span class="comp-badge" x-text="e.recurrence || 'one-off'"></span>
                                    </div>
                                    <span class="comp-version" x-text="e.next_run_gmt"></span>
                                    <div class="comp-actions">
                                        <button type="button" class="site-action-btn" :disabled="toolBusy[e.hook]" @click="runCron(e.hook)">run</button>
                                    </div>
                                </li>
                            </template>
                            <li class="empty" x-show="toolItems.length === 0" x-cloak>No scheduled events.</li>
                        </ul>

                        <div class="console" x-show="toolTab === 'console'" x-cloak>
                            <p class="comp-hint">Runs WP-CLI inside this site. Arguments are passed to WP-CLI, not to a shell.</p>
                            <form class="console-form" @submit.prevent="runConsole()">
                                <input type="text" class="filter-input console-input" x-model="consoleInput"
                                    placeholder="plugin list --format=table" spellcheck="false" autocomplete="off"
                                    autocapitalize="off" autocorrect="off" :disabled="toolLoading"
                                    aria-label="WP-CLI command">
                                <button class="pill primary" type="submit" :disabled="toolLoading || !consoleInput.trim()">
                                    <span class="btn-spinner" x-show="toolLoading" aria-hidden="true" style="display: none;"></span>
                                    <span x-text="toolLoading ? 'running…' : 'run'"></span>
                                </button>
                            </form>
                            <p class="comp-hint" x-show="consoleResult" x-cloak>
                                exit <span x-text="consoleResult && consoleResult.exit_code"></span> ·
                                <span x-text="consoleResult && consoleResult.duration_ms"></span> ms
                            </p>
                            <pre class="console-out" x-show="consoleResult" x-text="consoleOutput" x-cloak></pre>
                            <div class="console-history" x-show="consoleHistory.length" x-cloak>
                                <template x-for="(h, i) in consoleHistory" :key="i">
                                    <button type="button" class="console-hist-btn" @click="consoleInput = h" x-text="h"></button>
                                </template>
                            </div>
                        </div>
                    </div>
                </template>

                <div class="components diag">
                    <div class="components-head">
                        <div class="components-tabs">
                            <button type="button" class="comp-tab" :class="{ active: diagTab === 'logs' }" @click="setDiagTab('logs')">logs</button>
                            <button type="button" class="comp-tab" :class="{ active: diagTab === 'traffic' }" @click="setDiagTab('traffic')">traffic</button>
                        </div>
                        <button type="button" class="site-action-btn" :class="{ loading: diagLoading }" @click="reloadDiag()" :disabled="diagLoading">
                            <span class="btn-label" x-text="diagLoading ? 'loading…' : 'refresh'"></span>
                        </button>
                    </div>

                    <template x-if="diagTab === 'logs'">
                        <div>
                            <div class="log-controls">
                                <div class="components-tabs">
                                    <button type="button" class="comp-tab" :class="{ active: logSource === 'php' }" :disabled="logAvailable.php === false" @click="setLogSource('php')">php errors</button>
                                    <button type="button" class="comp-tab" :class="{ active: logSource === 'debug' }" :disabled="logAvailable.debug === false" @click="setLogSource('debug')">debug.log</button>
                                    <button type="button" class="comp-tab" :class="{ active: logSource === 'access' }" :disabled="logAvailable.access === false" @click="setLogSource('access')">access</button>
                                </div>
                                <select class="log-select" x-model="logLevel" @change="loadLogs(detailSite.name)" aria-label="Minimum level">
                                    <option value="all">all levels</option>
                                    <option value="warning">warning+</option>
                                    <option value="fatal error">fatal only</option>
                                </select>
                                <input type="text" class="filter-input log-search" x-model="logQuery" @input.debounce.400ms="loadLogs(detailSite.name)" placeholder="filter…" spellcheck="false" autocomplete="off">
                            </div>
                            <p class="comp-error" x-show="logError" x-text="logError" x-cloak></p>
                            <p class="comp-loading" x-show="logLoading" x-cloak>Reading logs…</p>
                            <ul class="log-list" x-show="!logLoading" x-cloak>
                                <template x-for="(entry, i) in logItems" :key="i">
                                    <li class="log-entry" :class="levelClass(entry)">
                                        <div class="log-line">
                                            <span class="log-level" x-text="entry.level"></span>
                                            <span class="log-time" x-text="entry.time"></span>
                                            <span class="log-count" x-show="entry.count > 1" x-cloak x-text="'×' + entry.count"></span>
                                            <span class="log-msg" x-text="logEntryText(entry)"></span>
                                        </div>
                                        <template x-if="entry.trace && entry.trace.length">
                                            <details class="log-trace"><summary>trace</summary><pre x-text="entry.trace.join('\n')"></pre></details>
                                        </template>
                                    </li>
                                </template>
                                <li class="empty" x-show="logItems.length === 0" x-cloak>No entries.</li>
                            </ul>
                            <p class="comp-hint" x-show="logTruncated" x-cloak>Showing the tail of a large log file.</p>
                        </div>
                    </template>

                    <template x-if="diagTab === 'traffic'">
                        <div>
                            <div class="log-controls">
                                <div class="components-tabs">
                                    <template x-for="p in ['1h','24h','7d','all']" :key="p">
                                        <button type="button" class="comp-tab" :class="{ active: trafficPeriod === p }" @click="setTrafficPeriod(p)" x-text="p === 'all' ? 'all time' : p"></button>
                                    </template>
                                </div>
                            </div>
                            <p class="comp-error" x-show="trafficError" x-text="trafficError" x-cloak></p>
                            <p class="comp-loading" x-show="trafficLoading" x-cloak>Aggregating…</p>
                            <template x-if="traffic && !trafficLoading">
                                <div class="traffic">
                                    <div class="traffic-cards">
                                        <div class="traffic-card"><span class="traffic-num" x-text="traffic.summary.requests"></span><span class="traffic-label">requests</span></div>
                                        <div class="traffic-card"><span class="traffic-num" x-text="traffic.summary.errors"></span><span class="traffic-label">errors</span></div>
                                        <div class="traffic-card"><span class="traffic-num" x-text="formatSize(traffic.summary.bytes)"></span><span class="traffic-label">bytes</span></div>
                                        <div class="traffic-card"><span class="traffic-num" x-text="traffic.summary.avg_ms + ' ms'"></span><span class="traffic-label">avg</span></div>
                                        <div class="traffic-card"><span class="traffic-num" x-text="traffic.summary.p95_ms + ' ms'"></span><span class="traffic-label">p95</span></div>
                                        <div class="traffic-card"><span class="traffic-num" x-text="traffic.summary.max_ms + ' ms'"></span><span class="traffic-label">max</span></div>
                                    </div>
                                    <div class="traffic-classes">
                                        <span class="comp-badge" x-text="'pages: ' + traffic.classes.pages"></span>
                                        <span class="comp-badge" x-text="'assets: ' + traffic.classes.assets"></span>
                                        <span class="comp-badge" x-text="'admin: ' + traffic.classes.admin"></span>
                                        <span class="comp-badge" x-text="'ajax/rest: ' + traffic.classes.ajax_rest"></span>
                                        <span class="comp-badge" x-text="'cron: ' + traffic.classes.cron"></span>
                                        <span class="comp-badge" x-text="'other: ' + traffic.classes.other"></span>
                                    </div>
                                    <p class="comp-hint" x-text="traffic.note"></p>
                                    <div class="traffic-cols">
                                        <div>
                                            <h4 class="traffic-h">Top paths</h4>
                                            <ul class="traffic-list">
                                                <template x-for="p in traffic.top_paths" :key="p.path">
                                                    <li><code x-text="p.path"></code><span x-text="p.count"></span></li>
                                                </template>
                                                <li class="empty" x-show="!traffic.top_paths.length">No requests.</li>
                                            </ul>
                                        </div>
                                        <div>
                                            <h4 class="traffic-h">Slowest</h4>
                                            <ul class="traffic-list">
                                                <template x-for="s in traffic.slow" :key="s.time + s.uri">
                                                    <li><code x-text="s.uri"></code><span x-text="s.duration_ms + ' ms'"></span></li>
                                                </template>
                                                <li class="empty" x-show="!traffic.slow.length">No requests.</li>
                                            </ul>
                                        </div>
                                    </div>
                                </div>
                            </template>
                        </div>
                    </template>
                </div>

                <div class="components backups">
                    <div class="components-head">
                        <div class="components-tabs">
                            <span class="comp-tab active" style="cursor:default">backups</span>
                        </div>
                        <button type="button" class="site-action-btn" :class="{ loading: snapLoading }" @click="loadSnapshots(detailSite.name)" :disabled="snapLoading">
                            <span class="btn-label" x-text="snapLoading ? 'loading…' : 'refresh'"></span>
                        </button>
                    </div>
                    <form class="console-form" @submit.prevent="createSnapshot()">
                        <input type="text" class="filter-input console-input" x-model="snapNote" placeholder="snapshot note (optional)" maxlength="200" :disabled="!!job">
                        <button class="pill primary" type="submit" :disabled="!!job" x-text="job ? 'working…' : 'create snapshot'"></button>
                    </form>
                    <p class="comp-error" x-show="snapError" x-text="snapError" x-cloak></p>
                    <ul class="comp-list" x-show="!snapLoading" x-cloak>
                        <template x-for="s in snapshots" :key="s.id">
                            <li class="comp-row">
                                <div class="comp-main">
                                    <span class="comp-title" x-text="s.note || '(no note)'"></span>
                                    <span class="comp-slug" x-text="s.id"></span>
                                    <span class="comp-badge" x-text="s.type"></span>
                                    <span class="comp-version" x-text="formatSize((s.files_bytes || 0) + (s.db_bytes || 0))"></span>
                                </div>
                                <span class="comp-version" x-text="s.created"></span>
                                <div class="comp-actions">
                                    <button type="button" class="site-action-btn" @click="downloadSnapshot(s.id)" title="Download as a full backup">download</button>
                                    <button type="button" class="site-action-btn danger" :disabled="!!job" @click="restoreSnapshot(s)" x-text="snapArm === s.id ? 'confirm restore?' : 'restore'"></button>
                                    <button type="button" class="site-action-btn danger" :disabled="!!job" @click="deleteSnapshot(s)" x-text="snapArmDel === s.id ? 'confirm delete?' : 'delete'"></button>
                                </div>
                            </li>
                        </template>
                        <li class="empty" x-show="snapshots.length === 0" x-cloak>No snapshots yet.</li>
                    </ul>
                    <div class="job-status" x-show="job" x-cloak>
                        <span class="btn-spinner" x-show="job && job.status === 'running'" aria-hidden="true"></span>
                        <span x-text="job ? (job.label + ' — ' + job.status) : ''"></span>
                    </div>
                    <pre class="console-out" x-show="job && job.log" x-text="job && job.log" x-cloak></pre>
                    <pre class="console-out" x-show="!job && jobLog" x-text="jobLog" x-cloak></pre>
                </div>
            </div>
        </template>
    </section>

    <div x-show="showDbModal" x-transition.opacity class="modal-backdrop" @click.self="showDbModal = false" @keydown.escape.window="showDbModal = false" style="display: none;">
        <div class="modal">
            <h3>Database credentials</h3>
            <p class="modal-sub">Plak uses these to create new WordPress databases.</p>
            <div class="db-creds">
                <div class="db-cred-row">
                    <span class="db-cred-label">user</span>
                    <code class="db-cred-value"><?= htmlspecialchars($config_data['DB_USER'] ?? '—') ?></code>
                </div>
                <div class="db-cred-row">
                    <span class="db-cred-label">password</span>
                    <code class="db-cred-value"><?= htmlspecialchars($config_data['DB_PASSWORD'] ?? '—') ?></code>
                </div>
            </div>
            <div class="modal-foot">
                <span>stored in <?= htmlspecialchars(str_replace(getenv('HOME'), '~', $config_file)) ?></span>
                <button class="pill" @click="showDbModal = false">close</button>
            </div>
        </div>
    </div>

    <div x-show="snackbar.visible" x-transition.opacity.duration.200ms class="snackbar" :class="{ error: snackbar.isError }" x-text="snackbar.message" style="display: none;"></div>

    <div x-show="showMail" x-transition.opacity class="modal-backdrop" @click.self="closeMail()" @keydown.escape.window="showMail && closeMail()" style="display: none;">
        <div class="modal mail-modal">
            <div class="mail-head">
                <h3>Mail <span class="mail-scope" x-text="mailScope === 'site' ? '· ' + mailSiteName : '· all sites'"></span></h3>
                <div class="mail-head-actions">
                    <span class="comp-badge" x-show="mailUnread" x-cloak x-text="mailUnread + ' unread'"></span>
                    <button class="pill" @click="loadMail()" :disabled="mailLoading" x-text="mailLoading ? '…' : 'refresh'"></button>
                    <button class="pill" @click="closeMail()">close</button>
                </div>
            </div>

            <template x-if="!mailSelected">
                <div>
                    <div class="mail-controls">
                        <input type="text" class="filter-input log-search" x-model="mailSearch" @input.debounce.400ms="loadMail()" placeholder="search mail…" spellcheck="false" autocomplete="off" autocapitalize="off">
                    </div>
                    <p class="comp-error" x-show="mailError" x-text="mailError" x-cloak></p>
                    <p class="comp-loading" x-show="mailOffline" x-cloak>Mailpit is not reachable. Start it with <code>plak install</code>.</p>
                    <ul class="mail-list" x-show="!mailOffline" x-cloak>
                        <template x-for="m in mailMessages" :key="m.id">
                            <li class="mail-row" :class="{ unread: !m.read }">
                                <button type="button" class="mail-open" @click="openMessage(m.id)">
                                    <span class="mail-from" x-text="m.from"></span>
                                    <span class="mail-subject" x-text="m.subject"></span>
                                    <span class="mail-snippet" x-text="m.snippet"></span>
                                </button>
                                <div class="mail-row-meta">
                                    <span class="comp-badge" x-show="m.site" x-cloak x-text="m.site"></span>
                                    <span class="comp-badge" x-show="m.attachments" x-cloak x-text="'📎 ' + m.attachments"></span>
                                    <span class="mail-date" x-text="m.created ? new Date(m.created).toLocaleString() : ''"></span>
                                    <button type="button" class="site-action-btn" @click="toggleSeen(m)" x-text="m.read ? 'unread' : 'read'"></button>
                                    <button type="button" class="site-action-btn danger" @click="deleteMail(m.id)">delete</button>
                                </div>
                            </li>
                        </template>
                        <li class="empty" x-show="mailMessages.length === 0" x-cloak>No messages.</li>
                    </ul>
                    <p class="comp-hint" x-text="mailNote"></p>
                </div>
            </template>

            <template x-if="mailSelected">
                <div class="mail-detail">
                    <div class="mail-detail-head">
                        <button class="site-action-btn" @click="closeMessage()">← back</button>
                        <div class="mail-detail-subject" x-text="mailDetail ? mailDetail.subject : '…'"></div>
                    </div>
                    <p class="mail-detail-meta" x-show="mailDetail" x-cloak x-text="mailDetail && (mailDetail.from + '  →  ' + (mailDetail.to || []).join(', '))"></p>
                    <p class="comp-error" x-show="mailDetailError" x-text="mailDetailError" x-cloak></p>
                    <template x-if="mailDetail">
                        <div>
                            <div class="mail-links" x-show="mailDetail.links && mailDetail.links.length" x-cloak>
                                <template x-for="l in mailDetail.links" :key="l">
                                    <button type="button" class="console-hist-btn" @click="copyLink(l)" :title="'Copy ' + l" x-text="l"></button>
                                </template>
                            </div>
                            <label class="plain-toggle mail-imgtoggle">
                                <input type="checkbox" x-model="mailShowImages"> load remote images
                            </label>
                            <iframe class="mail-frame" sandbox="" referrerpolicy="no-referrer" :srcdoc="mailFrameHtml()" x-show="mailDetail.html" x-cloak></iframe>
                            <pre class="console-out" x-show="!mailDetail.html" x-text="mailDetail.text"></pre>
                        </div>
                    </template>
                </div>
            </template>
        </div>
    </div>

    <div x-show="showImport" x-transition.opacity class="modal-backdrop" @click.self="!job && (showImport = false)" @keydown.escape.window="showImport && !job && (showImport = false)" style="display: none;">
        <div class="modal">
            <h3>Import a backup</h3>
            <p class="modal-sub">Create a new site from a Plak, Local or hosting backup (zip, tar.gz, tgz or tar).</p>
            <form class="import-form" @submit.prevent="importBackup()">
                <input type="text" class="filter-input console-input" x-model="importName" @input="importName = importName.toLowerCase().replace(/[^a-z0-9-]/g, '')" placeholder="new-site-name" required :disabled="!!job" autocomplete="off">
                <input type="file" class="import-file" x-ref="importFile" accept=".zip,.tar,.gz,.tgz" :disabled="!!job">
                <p class="comp-error" x-show="importError" x-text="importError" x-cloak></p>
                <div class="modal-foot">
                    <span x-text="job ? (job.label + ' — ' + job.status) : ''"></span>
                    <div class="comp-actions">
                        <button type="button" class="pill" @click="showImport = false" :disabled="job && job.status === 'running'">close</button>
                        <button type="submit" class="pill primary" :disabled="!importName || !!job" x-text="job && job.status === 'running' ? 'importing…' : 'import'"></button>
                    </div>
                </div>
            </form>
        </div>
    </div>

    <script>
        const PORT_SUFFIX = '<?= $__plak_site_port_suffix ?>';
        const SITES_DIR = 'SITES_DIR_PLACEHOLDER';
        // Echoed on every mutating request; api.php rejects POSTs without it.
        const CSRF_TOKEN = '<?= htmlspecialchars($__plak_site_csrf, ENT_QUOTES) ?>';

        document.addEventListener('alpine:init', () => {
            Alpine.data('dashboard', () => ({
                // Respect the OS theme preference on first visit, dark otherwise.
                theme: localStorage.getItem('theme') || (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark'),
                sites: [],
                isLoading: true,
                adding: false,
                showDbModal: false,
                // Per-site detail view, driven by the URL hash so each site has
                // a navigable, linkable address (#/site/<name>) that works with
                // back/forward.
                detailSite: null,
                detailInfo: null,
                detailLoading: false,
                // Plugins/themes panel for the open WordPress site.
                compTab: 'plugins',
                compItems: [],
                compLoading: false,
                compError: null,
                compChecked: false,
                compBusy: {},
                compArm: null,
                compArmTimer: null,
                // Tools panel (users / cron / WP-CLI console) for the open site.
                toolTab: 'users',
                toolItems: [],
                toolLoading: false,
                toolError: null,
                toolBusy: {},
                consoleInput: '',
                consoleOutput: '',
                consoleResult: null,
                consoleHistory: [],
                // Diagnostics panel (logs / traffic) for the open site.
                diagTab: 'logs',
                logSource: 'php',
                logLevel: 'all',
                logQuery: '',
                logItems: [],
                logAvailable: {},
                logLoading: false,
                logError: null,
                logTruncated: false,
                trafficPeriod: '24h',
                traffic: null,
                trafficLoading: false,
                trafficError: null,
                // Mail inbox (global or filtered by the open site).
                showMail: false,
                mailScope: 'all',
                mailSiteName: '',
                mailMessages: [],
                mailTotal: 0,
                mailUnread: 0,
                mailNote: '',
                mailLoading: false,
                mailError: null,
                mailOffline: false,
                mailSearch: '',
                mailSelected: null,
                mailDetail: null,
                mailDetailError: null,
                mailShowImages: false,
                mailPoll: null,
                // Backups, long-running jobs and the import form (CLI-16).
                snapshots: [],
                snapLoading: false,
                snapError: null,
                snapNote: '',
                snapArm: null,
                snapArmDel: null,
                job: null,
                jobLog: '',
                jobPoll: null,
                showImport: false,
                importName: '',
                importError: null,
                isRefreshingSizes: false,
                filter: '',
                typeFilter: null, // null | 'WordPress' | 'Plain' — set via the row type pills, cleared via the chip × or overall filter clear
                sort: 'name',
                sortModes: ['name', 'size', 'modified'],
                newSite: { name: '', isPlain: false, agent: true, isLoading: false },
                snackbar: { visible: false, message: '', isError: false, timer: null },
                // Persistent dismissible banners for newly-created sites — the
                // snackbar only lives ~3.5s, not long enough to reach for the
                // admin login after spinning up a fresh install.
                alerts: [],
                deleteQueue: [],
                isProcessingQueue: false,

                get adminerUrl() { return 'https://db.plak.localhost' + PORT_SUFFIX; },
                get mailpitUrl() { return 'https://mail.plak.localhost' + PORT_SUFFIX; },
                get diagLoading() { return this.logLoading || this.trafficLoading; },
                get totalBytes() { return this.sites.reduce((t, s) => t + (s.size_bytes || 0), 0); },
                get filteredSites() {
                    // Two independent filters ANDed together: typeFilter (chip,
                    // exact match on site.type) and filter (free text, substring
                    // match on name OR type). Keeping them separate means the
                    // user can type anything in the input without worrying about
                    // stepping on the type constraint.
                    let base = [...this.sites];
                    if (this.typeFilter) {
                        base = base.filter(s => s.type === this.typeFilter);
                    }
                    const q = this.filter.trim().toLowerCase();
                    if (q) {
                        base = base.filter(s =>
                            s.name.toLowerCase().includes(q) ||
                            (s.type || '').toLowerCase().includes(q));
                    }
                    if (this.sort === 'size') {
                        base.sort((a, b) => (b.size_bytes || 0) - (a.size_bytes || 0));
                    } else if (this.sort === 'modified') {
                        base.sort((a, b) => (b.modified_at || 0) - (a.modified_at || 0));
                    } else {
                        base.sort((a, b) => a.name.localeCompare(b.name));
                    }
                    return base;
                },

                get typeFilterLabel() {
                    return this.typeFilter === 'WordPress' ? 'type: wp' : 'type: static';
                },

                clearAllFilters() {
                    this.filter = '';
                    this.typeFilter = null;
                },
                get siteCountLabel() {
                    const total = this.sites.length;
                    const visible = this.filteredSites.length;
                    const suffix = ' site' + (total === 1 ? '' : 's');
                    return visible === total ? total + suffix : visible + ' of ' + total + suffix;
                },

                init() {
                    this.applyTheme();
                    this.$watch('theme', () => { this.applyTheme(); localStorage.setItem('theme', this.theme); });

                    // `/` focuses the filter (GitHub-style). Ignored when typing
                    // in a form field or holding a modifier key.
                    window.addEventListener('keydown', (e) => {
                        if (e.key !== '/' || e.ctrlKey || e.metaKey || e.altKey) return;
                        const el = document.activeElement;
                        const tag = el && el.tagName;
                        if (tag === 'INPUT' || tag === 'TEXTAREA' || (el && el.isContentEditable)) return;
                        e.preventDefault();
                        this.$refs.filterInput && this.$refs.filterInput.focus();
                    });

                    this.getSites().then(() => {
                        // If the size cache is empty (fresh install or just deleted),
                        // kick off a background refresh so sizes populate without
                        // making the user hunt for the ↻ button.
                        if (this.sites.length > 0 && this.sites.every(s => s.size_bytes === null)) {
                            this.refreshSizes();
                        }
                        // Honour a deep link (#/site/<name>) after sites load.
                        this.applyHash();
                    });

                    window.addEventListener('hashchange', () => this.applyHash());

                    // Reattach to a snapshot/import job that survived a reload.
                    this.resumeJob();
                },

                // Hash routing for the per-site view: #/site/<name>.
                parseSiteHash() {
                    const m = /^#\/site\/(.+)$/.exec(window.location.hash || '');
                    return m ? decodeURIComponent(m[1]) : null;
                },

                applyHash() {
                    const name = this.parseSiteHash();
                    const previous = this.detailSite ? this.detailSite.name : null;
                    if (name && this.sites.some(s => s.name === name)) {
                        this.detailSite = this.sites.find(s => s.name === name);
                        if (previous !== name) {
                            // Reset the components panel for the new site.
                            this.compTab = 'plugins';
                            this.compItems = [];
                            this.compError = null;
                            this.compChecked = false;
                            this.compBusy = {};
                            this.compArm = null;
                            // Reset the tools panel and load its default tab.
                            this.toolTab = 'users';
                            this.toolItems = [];
                            this.toolError = null;
                            this.toolBusy = {};
                            this.consoleInput = '';
                            this.consoleOutput = '';
                            this.consoleResult = null;
                            this.consoleHistory = [];
                            // Reset diagnostics and load logs for the new site.
                            this.diagTab = 'logs';
                            this.logSource = 'php';
                            this.logLevel = 'all';
                            this.logQuery = '';
                            this.logItems = [];
                            this.logError = null;
                            this.logTruncated = false;
                            this.logAvailable = {};
                            this.traffic = null;
                            this.trafficError = null;
                            // Reset backups for the new site.
                            this.snapshots = [];
                            this.snapError = null;
                            this.snapNote = '';
                            this.snapArm = null;
                            this.snapArmDel = null;
                            if (this.detailSite.type === 'WordPress') this.loadTool(name);
                            this.loadLogs(name);
                            this.loadSnapshots(name);
                        }
                    } else {
                        this.detailSite = null;
                        this.detailInfo = null;
                        this.compItems = [];
                    }
                },

                closeSiteDetail() {
                    if (this.parseSiteHash()) {
                        // Clears the hash and fires hashchange, which closes it.
                        window.location.hash = '';
                    } else {
                        this.detailSite = null;
                        this.detailInfo = null;
                        this.compItems = [];
                        this.toolItems = [];
                    }
                },

                // Fetch version/plugin counts on demand; never on page load, so
                // opening the dashboard stays fast.
                async loadSiteInfo(name) {
                    this.detailLoading = true;
                    try {
                        const res = await this.apiPost('site_info', { site_name: name });
                        if (res.success) {
                            this.detailInfo = res.info || {};
                        }
                    } finally {
                        this.detailLoading = false;
                    }
                },

                setCompTab(tab) {
                    if (this.compTab === tab) return;
                    this.compTab = tab;
                    this.compItems = [];
                    this.compError = null;
                    this.compChecked = false;
                    this.compArm = null;
                    const site = this.detailSite;
                    if (site) this.loadComponents(site.name);
                },

                // `check` asks WordPress.org for updates (slow, explicit only);
                // an ordinary list never blocks on a remote query.
                async loadComponents(name, opts = {}) {
                    this.compLoading = true;
                    this.compError = null;
                    const action = this.compTab === 'plugins' ? 'site_plugins' : 'site_themes';
                    const res = await this.apiPost(action, { site_name: name, check: !!opts.check });
                    // Ignore a response that arrives after the user navigated away.
                    if (!this.detailSite || this.detailSite.name !== name) return;
                    this.compLoading = false;
                    if (!res.success) {
                        this.compError = res.message || 'wp-cli failed.';
                        this.compItems = [];
                        return;
                    }
                    this.compItems = res.items || [];
                    if (opts.check) this.compChecked = true;
                },

                updateAvailable(item) {
                    return item.update === 'available' || item.update === '1' || item.update === true;
                },

                compStatusClass(item) {
                    if (item.status === 'must-use') return 'mu';
                    if (item.status === 'active') return 'active';
                    if (item.status === 'inactive') return 'inactive';
                    return '';
                },

                // Deleting an active theme or a must-use plugin is invalid.
                canDelete(item) {
                    if (this.compTab === 'plugins') return item.status !== 'must-use';
                    return item.status !== 'active';
                },

                deleteTitle(tab, item) {
                    if (tab === 'plugins' && item.status === 'must-use') return 'Must-use plugins cannot be deleted';
                    if (tab === 'themes' && item.status === 'active') return 'The active theme cannot be deleted';
                    return 'Delete ' + item.name;
                },

                async componentOp(tab, item, op) {
                    if (this.compBusy[item.name]) return;
                    this.compBusy = { ...this.compBusy, [item.name]: op };
                    const res = await this.apiPost(tab === 'plugins' ? 'site_plugin_op' : 'site_theme_op',
                        { site_name: this.detailSite.name, slug: item.name, op, status: item.status });
                    const busy = { ...this.compBusy };
                    delete busy[item.name];
                    this.compBusy = busy;
                    const last = (res.message || '').split('\n').filter(Boolean).pop() || '';
                    this.showSnack(last.replace(/^(Success|Error|Warning): /, '') || (res.success ? 'Done.' : 'Failed.'), !res.success);
                    if (res.success) this.loadComponents(this.detailSite.name);
                },

                // Two-step delete: the first click arms, the second confirms.
                componentDelete(tab, item) {
                    if (this.canDelete(item) !== true) return;
                    if (this.compArm !== item.name) {
                        this.compArm = item.name;
                        clearTimeout(this.compArmTimer);
                        this.compArmTimer = setTimeout(() => { this.compArm = null; }, 3500);
                        return;
                    }
                    this.compArm = null;
                    clearTimeout(this.compArmTimer);
                    this.componentOp(tab, item, 'delete');
                },

                setToolTab(tab) {
                    if (this.toolTab === tab) return;
                    this.toolTab = tab;
                    this.toolItems = [];
                    this.toolError = null;
                    this.toolBusy = {};
                    if (tab !== 'console' && this.detailSite) this.loadTool(this.detailSite.name);
                },

                // Users and cron both read from WP-CLI; the active tab decides
                // which action runs. Never fired on page load.
                async loadTool(name) {
                    this.toolLoading = true;
                    this.toolError = null;
                    const action = this.toolTab === 'cron' ? 'site_cron' : 'site_users';
                    const res = await this.apiPost(action, { site_name: name });
                    if (!this.detailSite || this.detailSite.name !== name) return;
                    this.toolLoading = false;
                    if (!res.success) {
                        this.toolError = res.message || 'wp-cli failed.';
                        this.toolItems = [];
                        return;
                    }
                    this.toolItems = res.items || [];
                },

                async userLogin(user) {
                    if (this.toolBusy[user.user_login]) return;
                    this.toolBusy = { ...this.toolBusy, [user.user_login]: true };
                    const res = await this.apiPost('site_user_login', { site_name: this.detailSite.name, user_login: user.user_login });
                    const busy = { ...this.toolBusy };
                    delete busy[user.user_login];
                    this.toolBusy = busy;
                    if (res.success && res.url) {
                        window.open(res.url, '_blank');
                        this.showSnack('Login link opened in a new tab.');
                    }
                },

                async runCron(hook) {
                    if (this.toolBusy[hook]) return;
                    this.toolBusy = { ...this.toolBusy, [hook]: true };
                    const res = await this.apiPost('site_cron_run', { site_name: this.detailSite.name, hook });
                    const busy = { ...this.toolBusy };
                    delete busy[hook];
                    this.toolBusy = busy;
                    const last = (res.output || res.message || '').split('\n').filter(Boolean).pop() || '';
                    this.showSnack(res.success ? (last || 'Cron event run.') : (last || 'Cron run failed.'), !res.success);
                    if (res.success) this.loadTool(this.detailSite.name);
                },

                // Split a console line into argv, honouring single/double quotes
                // so values with spaces stay a single argument.
                tokenizeConsole(input) {
                    const args = [];
                    let cur = '';
                    let quote = null;
                    let has = false;
                    for (let i = 0; i < input.length; i++) {
                        const c = input[i];
                        if (quote) {
                            if (c === quote) { quote = null; }
                            else if (c === '\\' && quote === '"' && i + 1 < input.length) { cur += input[++i]; }
                            else { cur += c; }
                        } else if (c === '"' || c === "'") {
                            quote = c; has = true;
                        } else if (/\s/.test(c)) {
                            if (has) { args.push(cur); cur = ''; has = false; }
                        } else {
                            cur += c; has = true;
                        }
                    }
                    if (has) args.push(cur);
                    return args;
                },

                async runConsole() {
                    const args = this.tokenizeConsole(this.consoleInput);
                    if (!args.length || this.toolLoading) return;
                    this.toolLoading = true;
                    const res = await this.apiPost('site_wpcli', { site_name: this.detailSite.name, args });
                    this.toolLoading = false;
                    this.consoleResult = res;
                    this.consoleOutput = String(res.output || res.message || '').replace(/\s+$/, '');
                    const line = this.consoleInput.trim();
                    if (line) {
                        this.consoleHistory = [line, ...this.consoleHistory.filter(h => h !== line)].slice(0, 10);
                    }
                },

                setDiagTab(tab) {
                    if (this.diagTab === tab) return;
                    this.diagTab = tab;
                    if (!this.detailSite) return;
                    if (tab === 'logs') this.loadLogs(this.detailSite.name);
                    else this.loadTraffic(this.detailSite.name);
                },

                setLogSource(src) {
                    if (this.logSource === src) return;
                    this.logSource = src;
                    this.loadLogs(this.detailSite.name);
                },

                setTrafficPeriod(period) {
                    if (this.trafficPeriod === period) return;
                    this.trafficPeriod = period;
                    this.loadTraffic(this.detailSite.name);
                },

                reloadDiag() {
                    if (!this.detailSite) return;
                    if (this.diagTab === 'logs') this.loadLogs(this.detailSite.name);
                    else this.loadTraffic(this.detailSite.name);
                },

                async loadLogs(name) {
                    this.logLoading = true;
                    this.logError = null;
                    const res = await this.apiPost('site_logs', {
                        site_name: name,
                        source: this.logSource,
                        level: this.logLevel,
                        q: this.logQuery,
                    });
                    if (!this.detailSite || this.detailSite.name !== name) return;
                    this.logLoading = false;
                    if (!res.success) {
                        this.logError = res.message || 'Could not read logs.';
                        this.logItems = [];
                        return;
                    }
                    this.logItems = res.items || [];
                    this.logAvailable = res.available || {};
                    this.logTruncated = !!res.truncated;
                },

                async loadTraffic(name) {
                    this.trafficLoading = true;
                    this.trafficError = null;
                    const res = await this.apiPost('site_traffic', { site_name: name, period: this.trafficPeriod });
                    if (!this.detailSite || this.detailSite.name !== name) return;
                    this.trafficLoading = false;
                    if (!res.success) {
                        this.trafficError = res.message || 'Could not read traffic.';
                        this.traffic = null;
                        return;
                    }
                    this.traffic = res;
                },

                logEntryText(entry) {
                    if (entry.method !== undefined) {
                        return entry.method + ' ' + entry.uri + ' → ' + entry.status;
                    }
                    return entry.message + (entry.location ? '  —  ' + entry.location : '');
                },

                levelClass(entry) {
                    const l = String(entry.level || '').toLowerCase();
                    if (l === 'error' || l.indexOf('fatal') !== -1 || l.indexOf('parse') !== -1) return 'lvl-error';
                    if (l === 'warn' || l.indexOf('warning') !== -1 || l.indexOf('deprecated') !== -1) return 'lvl-warn';
                    return 'lvl-info';
                },

                openMail(scope = 'all', siteName = null) {
                    this.mailScope = scope;
                    this.mailSiteName = siteName || (this.detailSite ? this.detailSite.name : '');
                    this.showMail = true;
                    this.mailSelected = null;
                    this.mailDetail = null;
                    this.mailDetailError = null;
                    this.loadMail();
                    this.startMailPoll();
                },

                closeMail() {
                    this.showMail = false;
                    this.stopMailPoll();
                },

                // Poll while the list is visible so new mail appears on its own.
                // Skipped while a message is open or Mailpit is known offline.
                startMailPoll() {
                    this.stopMailPoll();
                    this.mailPoll = setInterval(() => {
                        if (this.showMail && !this.mailSelected && !this.mailOffline) this.loadMail(true);
                    }, 5000);
                },

                stopMailPoll() {
                    if (this.mailPoll) { clearInterval(this.mailPoll); this.mailPoll = null; }
                },

                async loadMail(silent = false) {
                    if (!silent) this.mailLoading = true;
                    const res = await this.apiPost('mail_messages', {
                        scope: this.mailScope,
                        site_name: this.mailScope === 'site' ? this.mailSiteName : '',
                        search: this.mailSearch,
                    });
                    this.mailLoading = false;
                    if (!res.success) {
                        this.mailOffline = !!res.offline;
                        this.mailError = res.offline ? null : (res.message || 'Could not read mail.');
                        if (!silent) this.mailMessages = [];
                        return;
                    }
                    this.mailOffline = false;
                    this.mailError = null;
                    this.mailMessages = res.messages || [];
                    this.mailTotal = res.total || 0;
                    this.mailUnread = res.unread || 0;
                    this.mailNote = res.note || '';
                },

                async openMessage(id) {
                    this.mailSelected = id;
                    this.mailDetail = null;
                    this.mailDetailError = null;
                    this.mailShowImages = false;
                    const res = await this.apiPost('mail_message', { id });
                    if (this.mailSelected !== id) return;
                    if (!res.success) {
                        this.mailDetailError = res.message || 'Could not read the message.';
                        return;
                    }
                    this.mailDetail = res;
                    const row = this.mailMessages.find(m => m.id === id);
                    if (row) row.read = true;
                },

                closeMessage() {
                    this.mailSelected = null;
                    this.mailDetail = null;
                    this.loadMail(true);
                },

                // The message body is isolated in a sandboxed iframe. Remote
                // images stay blocked by the CSP until the user opts in.
                mailFrameHtml() {
                    if (!this.mailDetail) return '';
                    const csp = "default-src 'none'; style-src 'unsafe-inline'"
                        + (this.mailShowImages ? '; img-src data: https:' : '; img-src data:');
                    return '<!DOCTYPE html><html><head><meta charset="utf-8">'
                        + '<meta http-equiv="Content-Security-Policy" content="' + csp + '">'
                        + '<base target="_blank"></head><body>' + (this.mailDetail.html || '') + '</body></html>';
                },

                async toggleSeen(m) {
                    const res = await this.apiPost('mail_seen', { ids: [m.id], read: !m.read });
                    if (res.success) m.read = !m.read;
                },

                async deleteMail(id) {
                    if (!confirm('Delete this message?')) return;
                    const res = await this.apiPost('mail_delete', { ids: [id] });
                    if (res.success) {
                        this.mailMessages = this.mailMessages.filter(m => m.id !== id);
                        this.showSnack('Message deleted.');
                    }
                },

                async copyLink(url) {
                    try {
                        await navigator.clipboard.writeText(url);
                        this.showSnack('Link copied.');
                    } catch (e) {
                        this.showSnack('Could not copy link.', true);
                    }
                },

                // --- Backups, jobs and imports (CLI-16) ---
                async loadSnapshots(name) {
                    this.snapLoading = true;
                    this.snapError = null;
                    const res = await this.apiPost('snapshots', { site_name: name });
                    if (!this.detailSite || this.detailSite.name !== name) return;
                    this.snapLoading = false;
                    if (!res.success) {
                        this.snapError = res.message || 'Could not list snapshots.';
                        this.snapshots = [];
                        return;
                    }
                    this.snapshots = res.items || [];
                },

                openImport() {
                    this.showImport = true;
                    this.importName = '';
                    this.importError = null;
                },

                // Persist a running job's id so a reload can reattach to it.
                trackJob(res) {
                    if (!res || !res.success || !res.job) return false;
                    this.job = { id: res.job, label: 'Working', status: 'running', log: '' };
                    try { localStorage.setItem('plakJob', JSON.stringify({ id: res.job })); } catch (e) {}
                    this.pollJob();
                    return true;
                },

                resumeJob() {
                    let saved = null;
                    try { saved = JSON.parse(localStorage.getItem('plakJob') || 'null'); } catch (e) {}
                    if (saved && saved.id) {
                        this.job = { id: saved.id, label: 'Working', status: 'running', log: '' };
                        this.pollJob();
                    }
                },

                async pollJob() {
                    if (!this.job) return;
                    const id = this.job.id;
                    clearTimeout(this.jobPoll);
                    const res = await this.apiPost('job_status', { id });
                    if (!this.job || this.job.id !== id) return;
                    if (!res.success) {
                        this.job = null;
                        try { localStorage.removeItem('plakJob'); } catch (e) {}
                        return;
                    }
                    this.job = res.job;
                    if (this.job.status === 'running') {
                        this.jobPoll = setTimeout(() => this.pollJob(), 1500);
                        return;
                    }
                    const ok = this.job.status === 'done';
                    this.jobLog = this.job.log || '';
                    const label = this.job.label;
                    this.job = null;
                    try { localStorage.removeItem('plakJob'); } catch (e) {}
                    this.showSnack(ok ? (label + ' finished.') : (label + ' failed — check the log and retry from the CLI if needed.'), !ok);
                    if (ok) {
                        if (this.detailSite) this.loadSnapshots(this.detailSite.name);
                        this.getSites();
                    }
                },

                async createSnapshot() {
                    if (this.job) return;
                    const res = await this.apiPost('snapshot_create', { site_name: this.detailSite.name, note: this.snapNote });
                    if (this.trackJob(res)) this.snapNote = '';
                },

                // Two-step confirmation, like component deletion.
                restoreSnapshot(s) {
                    if (this.job) return;
                    if (this.snapArm !== s.id) {
                        this.snapArm = s.id;
                        this.snapArmDel = null;
                        return;
                    }
                    this.snapArm = null;
                    this.apiPost('snapshot_restore', { site_name: this.detailSite.name, id: s.id }).then(res => {
                        if (res.success && res.job) this.trackJob(res);
                    });
                },

                async deleteSnapshot(s) {
                    if (this.job) return;
                    if (this.snapArmDel !== s.id) {
                        this.snapArmDel = s.id;
                        this.snapArm = null;
                        return;
                    }
                    this.snapArmDel = null;
                    const res = await this.apiPost('snapshot_delete', { site_name: this.detailSite.name, id: s.id });
                    if (res.success) {
                        this.snapshots = this.snapshots.filter(x => x.id !== s.id);
                        this.showSnack('Snapshot deleted.');
                    }
                },

                downloadSnapshot(id) {
                    if (!this.detailSite) return;
                    const url = 'api.php?action=download_snapshot&site=' + encodeURIComponent(this.detailSite.name)
                        + '&id=' + encodeURIComponent(id) + '&token=' + encodeURIComponent(CSRF_TOKEN);
                    window.location.href = url;
                },

                async importBackup() {
                    const input = this.$refs.importFile;
                    const file = input && input.files && input.files[0];
                    this.importError = null;
                    if (!file) { this.importError = 'Choose a backup file.'; return; }
                    if (!/\.(zip|tar\.gz|tgz|tar)$/i.test(file.name)) {
                        this.importError = 'Unsupported archive. Use zip, tar.gz, tgz or tar.';
                        return;
                    }
                    const form = new FormData();
                    form.append('action', 'import_site');
                    form.append('csrf', CSRF_TOKEN);
                    form.append('site_name', this.importName);
                    form.append('backup', file);
                    this.job = { id: null, label: 'Import ' + this.importName, status: 'running', log: '' };
                    try {
                        const res = await fetch('api.php', { method: 'POST', body: form }).then(r => r.json());
                        if (!res.success || !res.job) {
                            this.job = null;
                            this.importError = res.message || 'Import could not start.';
                            return;
                        }
                        if (input) input.value = '';
                        this.trackJob(res);
                    } catch (e) {
                        this.job = null;
                        this.importError = 'Upload failed. Check the connection and try again.';
                    }
                },

                applyTheme() {
                    document.documentElement.dataset.theme = this.theme;
                },

                toggleTheme() {
                    this.theme = this.theme === 'light' ? 'dark' : 'light';
                },

                toggleAdd() {
                    this.adding = !this.adding;
                    if (this.adding) {
                        this.$nextTick(() => { if (this.$refs.newSiteInput) this.$refs.newSiteInput.focus(); });
                    }
                },

                formatSize(bytes) {
                    if (bytes === null || bytes === undefined) return '—';
                    if (bytes === 0) return '0 B';
                    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
                    const i = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
                    const v = bytes / Math.pow(1024, i);
                    return (v >= 10 || i === 0 ? Math.round(v) : v.toFixed(1)) + ' ' + units[i];
                },

                formatRelative(ts) {
                    if (!ts) return '—';
                    const s = Math.max(0, Date.now() / 1000 - ts);
                    if (s < 60) return 'now';
                    if (s < 3600) return Math.floor(s / 60) + 'm';
                    if (s < 86400) return Math.floor(s / 3600) + 'h';
                    if (s < 86400 * 30) return Math.floor(s / 86400) + 'd';
                    if (s < 86400 * 365) return Math.floor(s / 86400 / 30) + 'mo';
                    return Math.floor(s / 86400 / 365) + 'y';
                },

                escapeHtml(s) {
                    return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
                },

                // Wrap every case-insensitive occurrence of `query` in <mark> while
                // escaping every other substring. Safe for x-html use because the
                // inner text comes from the trusted domain, not from query (query
                // only controls WHERE to split).
                highlightMatch(text, query) {
                    const q = (query || '').trim();
                    if (!q) return this.escapeHtml(text);
                    const lower = text.toLowerCase();
                    const lowerQ = q.toLowerCase();
                    let out = '';
                    let i = 0;
                    while (i < text.length) {
                        const idx = lower.indexOf(lowerQ, i);
                        if (idx === -1) { out += this.escapeHtml(text.slice(i)); break; }
                        out += this.escapeHtml(text.slice(i, idx));
                        out += '<mark>' + this.escapeHtml(text.slice(idx, idx + q.length)) + '</mark>';
                        i = idx + q.length;
                    }
                    return out;
                },

                // Wrap the site name in <span class="host-accent"> so it reads
                // teal while the .localhost suffix stays dim — matches the
                // landing-page dashboard mock. Split at the first dot; if
                // there's none, the whole string is treated as the name.
                highlightedDomain(domain, query) {
                    const stripped = String(domain).replace(/^https?:\/\//, '');
                    const dotIdx = stripped.indexOf('.');
                    if (dotIdx === -1) return '<span class="host-accent">' + this.highlightMatch(stripped, query) + '</span>';
                    const name = stripped.slice(0, dotIdx);
                    const suffix = stripped.slice(dotIdx);
                    return '<span class="host-accent">' + this.highlightMatch(name, query) + '</span>' + this.highlightMatch(suffix, query);
                },

                cycleSort() {
                    const i = this.sortModes.indexOf(this.sort);
                    this.sort = this.sortModes[(i + 1) % this.sortModes.length];
                },

                openSite(site) {
                    // Don't navigate when the click was part of a drag-to-select,
                    // so users can still grab the domain/size text to copy.
                    if (window.getSelection && window.getSelection().toString()) return;
                    // Navigate to the linkable per-site detail view.
                    window.location.hash = '#/site/' + encodeURIComponent(site.name);
                },

                showSnack(msg, isError = false) {
                    if (this.snackbar.timer) clearTimeout(this.snackbar.timer);
                    this.snackbar = { visible: true, message: msg, isError, timer: null };
                    this.snackbar.timer = setTimeout(() => { this.snackbar.visible = false; }, 3500);
                },

                async apiPost(action, payload = {}) {
                    try {
                        const res = await fetch('api.php', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json', 'X-Plak-CSRF': CSRF_TOKEN },
                            body: JSON.stringify({ action, csrf: CSRF_TOKEN, ...payload })
                        }).then(r => r.json());
                        if (!res.success) this.showSnack(res.message || 'An error occurred.', true);
                        return res;
                    } catch (e) {
                        this.showSnack('Network error.', true);
                        return { success: false };
                    }
                },

                async getSites() {
                    this.isLoading = true;
                    try {
                        const r = await fetch('api.php?action=list_sites');
                        const data = await r.json();
                        this.sites = data.map(s => ({ ...s, isLoggingIn: false, isPreparingAgent: false }));
                    } catch (e) {
                        this.showSnack('Could not fetch sites.', true);
                    } finally {
                        this.isLoading = false;
                    }
                },

                async addSite() {
                    if (!this.newSite.name) return;
                    this.newSite.isLoading = true;
                    const name = this.newSite.name;
                    const isPlain = this.newSite.isPlain;
                    const agent = isPlain ? false : this.newSite.agent;

                    const add = await this.apiPost('add_site', { site_name: name, is_plain: isPlain, agent });
                    if (add.success) {
                        // Optimistic insert: we already know every field the row
                        // template uses. No auto-refresh — the Caddy reload that
                        // follows can take tens of seconds on fleets with lots of
                        // sites and would either hang the fetch or drop the UI
                        // into an ERR_CONNECTION_REFUSED during the config swap.
                        this.sites.push({
                            name,
                            domain: 'https://' + name + '.localhost' + PORT_SUFFIX,
                            type: isPlain ? 'Plain' : 'WordPress',
                            display_path: '~/Plak/Sites/' + name + '.localhost',
                            full_path: SITES_DIR + '/' + name + '.localhost',
                            // Server calculates size in add_site and returns it
                            // alongside success. Fall back to null so the row
                            // shows "—" until the next refresh if anything failed.
                            size_bytes: (typeof add.size_bytes === 'number') ? add.size_bytes : null,
                            modified_at: Math.floor(Date.now() / 1000),
                            isLoggingIn: false,
                        });
                        this.showSnack('Site created.');
                        this.newSite.name = '';
                        this.adding = false;
                        this.apiPost('reload_server'); // fire and forget — Caddy reloads in the background

                        // Surface a persistent alert so the user can jump
                        // straight into the new site without hunting for the
                        // row. WP sites get a one-time admin login; plain
                        // sites get a simple "open site" link.
                        this.alerts.push({
                            id: Date.now() + Math.random(),
                            name,
                            isPlain,
                            isLoggingIn: false,
                        });
                    }
                    this.newSite.isLoading = false;
                },

                async loginToNewSite(alert) {
                    alert.isLoggingIn = true;
                    const res = await this.apiPost('get_login_link', { site_name: alert.name });
                    if (res.success && res.url) {
                        window.open(res.url, '_blank');
                        // Acted on — banner's job is done. The new tab has the
                        // one-time URL; dashboard can drop the prompt.
                        this.dismissAlert(alert.id);
                    }
                    alert.isLoggingIn = false;
                },

                dismissAlert(id) {
                    this.alerts = this.alerts.filter(a => a.id !== id);
                },

                async deleteSite(name) {
                    if (!confirm(`Delete ${name}? This removes its files and database.`)) return;

                    // Optimistic: pull from the local list immediately so the UI feels
                    // instant, and enqueue the backend work. processDeleteQueue below
                    // drains the queue single-file so concurrent deletes don't race on
                    // shared state (Caddyfile regeneration, /etc/hosts edits).
                    const idx = this.sites.findIndex(s => s.name === name);
                    if (idx === -1) return;
                    this.sites.splice(idx, 1);
                    this.deleteQueue.push(name);
                    this.processDeleteQueue();
                },

                async processDeleteQueue() {
                    // Single-flight runner: whichever call picks up the lock drains the
                    // full queue. Concurrent deleteSite() calls just enqueue and return.
                    if (this.isProcessingQueue) return;
                    this.isProcessingQueue = true;

                    let anyFailed = false;
                    try {
                        // Outer loop catches deletes queued while we were awaiting the
                        // reload below — otherwise they'd sit forever because the next
                        // deleteSite() call short-circuits on isProcessingQueue.
                        while (this.deleteQueue.length > 0) {
                            while (this.deleteQueue.length > 0) {
                                const target = this.deleteQueue.shift();
                                const del = await this.apiPost('delete_site', { site_name: target });
                                if (del.success) {
                                    this.showSnack('Site deleted.');
                                } else {
                                    anyFailed = true; // apiPost already surfaced the error
                                }
                            }
                            // Kick a reload at the end of the batch. Race-safety
                            // lives server-side: plak_site_reload() uses a mkdir lock
                            // with a pending marker to coalesce concurrent calls,
                            // since reload_server itself backgrounds the shell
                            // command (shell_exec '...&') and returns instantly.
                            // Two unsynchronized frankenphp reload calls otherwise
                            // deadlock Caddy's admin server (10s shutdown timeout).
                            await this.apiPost('reload_server');
                        }
                    } finally {
                        this.isProcessingQueue = false;
                    }

                    // If anything failed mid-queue the optimistic UI is now out of sync
                    // with the backend (e.g. a survivor is missing from our list).
                    // Cheapest correct fix: re-fetch the authoritative list.
                    if (anyFailed) await this.getSites();
                },

                async getLoginLink(name) {
                    const site = this.sites.find(s => s.name === name);
                    if (!site) return;
                    site.isLoggingIn = true;
                    const res = await this.apiPost('get_login_link', { site_name: name });
                    if (res.success && res.url) {
                        window.open(res.url, '_blank');
                        this.showSnack('Login link opened in a new tab.');
                    }
                    site.isLoggingIn = false;
                },

                async prepareAgent(site) {
                    if (site.isPreparingAgent) return;
                    site.isPreparingAgent = true;
                    const res = await this.apiPost('prepare_agent', { site_name: site.name });
                    site.isPreparingAgent = false;
                    const last = (res.message || '').split('\n').filter(Boolean).pop() || '';
                    this.showSnack(res.success ? (last.replace(/^(Success|Error|Warning): /, '') || 'Agent ready.') : (last || 'Agent preparation failed.'), !res.success);
                    if (res.success) {
                        site.agent_ready = true;
                    }
                },

                async copyPath(path) {
                    try {
                        await navigator.clipboard.writeText(path);
                        this.showSnack('Path copied to clipboard.');
                    } catch (e) {
                        this.showSnack('Could not copy path.', true);
                    }
                },

                async refreshSizes() {
                    this.isRefreshingSizes = true;
                    const res = await this.apiPost('refresh_sizes');
                    if (res.success) {
                        await this.getSites();
                        this.showSnack('Disk sizes updated.');
                    }
                    this.isRefreshingSizes = false;
                }
            }));
        });
    </script>
</body>
</html>
EOM

    # Find the absolute path to this script to pass to the GUI
    local script_dir
    script_dir=$(cd "$(dirname "$0")" && pwd)
    local absolute_script_path="$script_dir/$(basename "$0")"

    # Escape the paths for use in sed
    local escaped_path
    escaped_path=$(printf '%s\n' "$absolute_script_path" | sed -e 's/[\/&]/\\&/g')
    local escaped_sites_dir
    escaped_sites_dir=$(printf '%s\n' "$SITES_DIR" | sed -e 's/[\/&]/\\&/g')
    local escaped_home
    escaped_home=$(printf '%s\n' "$HOME" | sed -e 's/[\/&]/\\&/g')

    # Substitute placeholders in both api.php and index.php. IS_WSL gates the
    # private-range allowance that WSL2's NAT adapter needs.
    local wsl_flag="false"
    [ "$IS_WSL" = true ] && wsl_flag="true"

    sed -e "s/PLAK_SITE_EXECUTABLE_PATH_PLACEHOLDER/${escaped_path}/g" \
        -e "s/SITES_DIR_PLACEHOLDER/${escaped_sites_dir}/g" \
        -e "s/USER_HOME_PLACEHOLDER/${escaped_home}/g" \
        -e "s/IS_WSL_PLACEHOLDER/${wsl_flag}/g" \
        "$GUI_DIR/api.php.tmp" > "$GUI_DIR/api.php"

    sed -e "s/SITES_DIR_PLACEHOLDER/${escaped_sites_dir}/g" \
        "$GUI_DIR/index.php.tmp" > "$GUI_DIR/index.php"

    # health.php reports the web process's PHP/OPcache state to `plak health`.
    # Read-only, served from the same local-only plak.localhost block as the
    # dashboard, and free of placeholders (no paths to substitute).
    cat > "$GUI_DIR/health.php" << 'EOM'
<?php
// Read-only PHP/OPcache probe for `plak health`. It reports, never changes.
if (!in_array($_SERVER['REMOTE_ADDR'] ?? '', ['127.0.0.1', '::1'], true)) {
    http_response_code(403);
    exit;
}
header('Cache-Control: no-store');
header('Content-Type: application/json');
$status = function_exists('opcache_get_status') ? @opcache_get_status(false) : null;
$config = function_exists('opcache_get_configuration') ? @opcache_get_configuration() : null;
$report = [
    'source' => PHP_SAPI === 'cli' ? 'cli' : 'web',
    'sapi' => PHP_SAPI,
    'php_version' => PHP_VERSION,
    'opcache_extension_loaded' => extension_loaded('Zend OPcache'),
    'opcache_enabled' => (bool) ini_get('opcache.enable'),
    'opcache_status' => $status ?: null,
    'opcache_configuration' => $config ? ($config['directives'] ?? null) : null,
];
if (($_GET['format'] ?? '') === 'text') {
    header('Content-Type: text/plain');
    echo ($report['source'] === 'web' ? 'Web PHP: ' : 'CLI PHP: ') . PHP_VERSION . ' (' . PHP_SAPI . ")\n";
    if (!$status) {
        echo "Web OPcache: unavailable/disabled (not the CLI cache)\n";
    } else {
        echo 'Web OPcache cache_full: ' . ($status['cache_full'] ? 'yes' : 'no') . "\n";
        foreach (['memory_usage', 'opcache_statistics'] as $section) {
            foreach (($status[$section] ?? []) as $key => $value) {
                if (is_scalar($value)) echo "$key: $value\n";
            }
        }
        foreach (['opcache.memory_consumption', 'opcache.interned_strings_buffer', 'opcache.max_accelerated_files'] as $key) {
            echo $key . ': ' . ($config['directives'][$key] ?? 'unknown') . "\n";
        }
        if ($status['cache_full']) echo "Recommendation: inspect usage and raise validated limits explicitly; no automatic restart.\n";
    }
} else {
    echo json_encode($report, JSON_PARTIAL_OUTPUT_ON_ERROR);
}
EOM

    # Clean up temp files
    rm "$GUI_DIR/api.php.tmp" "$GUI_DIR/index.php.tmp"
}

# Source: shared/site/snapshot
# Site snapshots: local recovery points of files and database per site.
#
# A snapshot is a self-contained directory under the site's private folder:
#
#   <SITES_DIR>/<name>.localhost/private/snapshots/<id>/
#     meta          key=value metadata (site, created, note, type)
#     files.tar.gz  wp-content plus root files when available (WordPress only)
#     database.sql  database export (WordPress only, when the dump succeeds)
#
# Restore replaces the current state after keeping a safety snapshot, and uses
# the shared recoverable database contract for the SQL step so a partial
# restore is never reported as success.

plak_snapshot_dir() {
    printf '%s/%s.localhost/private/snapshots\n' "$SITES_DIR" "$1"
}

# Unique, sortable identifier: UTC timestamp plus random suffix for collision
# safety when two snapshots are created within the same second.
plak_snapshot_new_id() {
    printf '%s-%s\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$(openssl rand -hex 3)"
}

plak_snapshot_valid_id() {
    [[ "$1" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{6}$ ]]
}

plak_snapshot_list_ids() {
    local dir
    dir=$(plak_snapshot_dir "$1")
    [ -d "$dir" ] || return 0
    find "$dir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' 2>/dev/null | sort
}

plak_snapshot_meta() {
    local dir="$1" key="$2"
    local file="$dir/meta"
    [ -f "$file" ] || return 1
    local line
    line=$(grep -m1 "^${key}=" "$file" 2>/dev/null || true)
    [ -n "$line" ] || return 1
    printf '%s' "${line#*=}"
}

# Keep the current state as a safety snapshot before a destructive operation.
plak_snapshot_keep_safety() {
    local site="$1"
    plak_snapshot_create "$site" --note "pre-restore safety" --json >/dev/null
}

# Source: shared/site/wp-cli
# Run the PHP entry point behind `wp` with FrankenPHP and Plak's PHPRC.
# No eval or shell execution is used to inspect wrappers.

plak_core_version_valid() {
    [ "${#1}" -le 32 ] && [[ "$1" = latest || "$1" = nightly || "$1" =~ ^[1-9][0-9]*\.[0-9]+(\.[0-9]+)?$ ]]
}

plak_wp_realpath() {
    local path="$1" target hops=0
    while [ -L "$path" ]; do
        if [ "$hops" -ge 40 ]; then
            echo "Error: too many symlinks resolving WP-CLI: $1" >&2
            return 1
        fi
        target=$(readlink "$path") || return 1
        case "$target" in
            /*) path="$target" ;;
            *) path="$(dirname "$path")/$target" ;;
        esac
        hops=$((hops + 1))
    done
    [ -f "$path" ] && [ -r "$path" ] || return 1
    local dir
    dir=$(cd "$(dirname "$path")" && pwd -P) || return 1
    printf '%s/%s\n' "$dir" "$(basename "$path")"
}

plak_wp_file_is_php() {
    local first="" second=""
    # The official PHAR has a PHP shebang followed by <?php. Checking the
    # opening tag also avoids mistaking a shell path containing 'php' for PHP.
    {
        IFS= read -r first || true
        IFS= read -r second || true
    } < "$1"
    case "$first" in
        '<?php'*) return 0 ;;
        '#!'*) [[ "$second" == '<?php'* ]] ;;
        *) return 1 ;;
    esac
}

plak_wp_resolve_phar() {
    local path
    path=$(type -P wp) || {
        echo "Error: WP-CLI not found. Run 'plak install'." >&2
        return 1
    }
    path=$(plak_wp_realpath "$path") || {
        echo "Error: WP-CLI is not a readable file or has broken symlinks." >&2
        return 1
    }
    if plak_wp_file_is_php "$path"; then
        printf '%s\n' "$path"
        return 0
    fi

    # Recognize literal PHAR paths in common shell wrappers (including
    # Homebrew), quoted paths with spaces, and paths rooted at HOME.
    # Complex computed wrappers are rejected rather than executed using a
    # different PHP, or printed by PHP as a bogus successful invocation.
    local token candidate resolved
    while IFS= read -r token; do
        case "$token" in
            \"*\") candidate="${token:1:${#token}-2}" ;;
            \'*\') candidate="${token:1:${#token}-2}" ;;
            *) candidate="$token" ;;
        esac
        # Match the literal spelling in the wrapper, then expand only HOME.
        # shellcheck disable=SC2016,SC2088
        case "$candidate" in
            '~/'*) candidate="$HOME/${candidate:2}" ;;
            '$HOME/'*) candidate="$HOME/${candidate:6}" ;;
            '${HOME}/'*) candidate="$HOME/${candidate:8}" ;;
        esac
        case "$candidate" in
            *'$'*|*'`'*) continue ;;
            /*) ;;
            *) candidate="$(dirname "$path")/$candidate" ;;
        esac
        resolved=$(plak_wp_realpath "$candidate") || continue
        if plak_wp_file_is_php "$resolved"; then
            printf '%s\n' "$resolved"
            return 0
        fi
    done < <(sed '/^[[:space:]]*#/d' "$path" | grep -oE "\"[^\"]+\.phar\"|'[^']+\.phar'|[^[:space:]\"';|&<>]+\.phar" || true)

    echo "Error: cannot resolve the WP-CLI PHAR referenced by wrapper '$path'. Put the official WP-CLI PHAR (or a symlink to it) on PATH as 'wp'." >&2
    return 1
}

# Caller owns a local PLAK_WP_COMMAND array (Bash dynamic scope), so paths
# and arguments never need to be serialized into a shell command string.
plak_wp_resolve_command() {
    local wp_path frank
    PLAK_WP_COMMAND=()
    wp_path=$(plak_wp_resolve_phar) || return 1
    frank=$(type -P frankenphp) || {
        echo "Error: FrankenPHP not found. Run 'plak install'." >&2
        return 1
    }
    frank=$(plak_wp_realpath "$frank") || return 1
    PLAK_WP_COMMAND=("$frank" php-cli "$wp_path")
    if [ "$(id -u)" -eq 0 ]; then
        PLAK_WP_COMMAND+=(--allow-root)
    fi
}

plak_wp_cli() {
    local PLAK_WP_COMMAND=()
    plak_wp_resolve_command || return $?
    "${PLAK_WP_COMMAND[@]}" "$@"
}

# Source: shared/ui
# Shared UI helpers for Plak Bash commands.

plak_ui_title() {
    if plak_command_exists gum; then
        gum style --bold --foreground 212 "$1"
    else
        echo "$1"
    fi
}

plak_ui_error() {
    if plak_command_exists gum; then
        gum style --foreground red "Error: $1" >&2
    else
        echo "Error: $1" >&2
    fi
}

plak_ui_warn() {
    if plak_command_exists gum; then
        gum style --foreground yellow "$1"
    else
        echo "$1"
    fi
}

plak_ui_success() {
    [ "${PLAK_QUIET:-0}" = "1" ] && return 0
    if plak_command_exists gum; then
        gum style --foreground green "$1"
    else
        echo "$1"
    fi
}

# Emit a JSON string literal (including the surrounding quotes) with the
# backslash and control characters JSON requires. Hand-rolled because Plak
# has no jq dependency at runtime.
plak_json_string() {
    local s="${1:-}"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    local code char oct escaped
    for code in {1..31}; do
        printf -v oct '%03o' "$code"
        printf -v char '%b' "\\$oct"
        printf -v escaped '\\u%04x' "$code"
        s=${s//"$char"/"$escaped"}
    done
    printf '"%s"' "$s"
}

# Source: shared/validate
# Shared validation helpers for Plak Bash commands.

plak_validate_site_name() {
    local value="${1:-}"
    [[ "$value" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] && [ "${#value}" -le 63 ]
}

plak_validate_hostname_alias() {
    local value="$1"
    [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]]
}

plak_validate_port() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 1 ] && [ "$value" -le 65535 ]
}

# --- Command Functions ---
# Source: commands/health
# Read-only probes; mutations always require an explicit subcommand/flag.
plak_health() {
    case "${1:-}" in
        opcache) shift; plak_health_opcache "$@" ;;
        http2) shift; plak_health_http2 "$@" ;;
        -h|--help) plak_display_command_help health ;;
        *) plak_health_report "$@" ;;
    esac
}

plak_health_web() {
    local format="${1:-json}" response
    response=$(curl --noproxy '*' --resolve "plak.localhost:${HTTPS_PORT}:127.0.0.1" \
        --connect-timeout 2 --max-time 5 -fksS \
        "$(url_for plak.localhost)/health.php?format=$format" 2>/dev/null) || return 1
    # A missing probe may route to dashboard HTML with HTTP 200. Do not embed
    # that HTML as JSON or accidentally accept a CLI-cache response.
    case "$format:$response" in
        'json:{"source":"web",'*|'text:Web PHP: '*) printf '%s\n' "$response" ;;
        *) return 1 ;;
    esac
}

plak_health_service() {
    local service="$1" state
    if [ "$service" = frankenphp ]; then
        if is_caddy_running; then echo running; else echo stopped; fi
    elif [ "$OS" = linux ] && command -v systemctl >/dev/null 2>&1; then
        [ "$service" != mariadb ] || service=$(get_mariadb_service_name)
        state=$(systemctl is-active "$service" 2>/dev/null) || true
        case "$state" in
            active) echo running ;;
            inactive|failed) echo stopped ;;
            *) echo unknown ;;
        esac
    elif [ "$OS" = macos ]; then
        if [ "$service" = mariadb ] && command -v brew >/dev/null 2>&1; then
            state=$(brew services list 2>/dev/null) || { echo unknown; return; }
            if grep -q 'mariadb.*started' <<< "$state"; then echo running; else echo stopped; fi
        elif [ "$service" = mailpit ] && command -v launchctl >/dev/null 2>&1; then
            if launchctl list com.plak.mailpit >/dev/null 2>&1; then echo running; else echo stopped; fi
        else echo unknown; fi
    else echo unknown; fi
}

plak_health_report() {
    local json=false
    case "${1:-}" in --json) json=true; shift ;; esac
    [ "$#" -eq 0 ] || { plak_ui_error 'Usage: plak health [--json]'; return 1; }
    local frank db mail version="" free=null used=null signals="" abandoned="" web=null item
    frank=$(plak_health_service frankenphp)
    db=$(plak_health_service mariadb)
    mail=$(plak_health_service mailpit)
    if command -v "$CADDY_CMD" >/dev/null 2>&1; then
        version=$("$CADDY_CMD" version 2>/dev/null) || version=""
    fi
    if [ -d "$PLAK_SITE_DIR" ]; then
        used=$(du -sk "$PLAK_SITE_DIR" 2>/dev/null | awk 'NR==1 {printf "%.0f", $1*1024}')
        free=$(df -Pk "$PLAK_SITE_DIR" 2>/dev/null | awk 'NR==2 {printf "%.0f", $4*1024}')
    fi
    for item in caddy-process.log errors.log caddy-reload.log; do
        if [ -r "$LOGS_DIR/$item" ]; then
            signals+=$(tail -c 65536 "$LOGS_DIR/$item" | grep -Ei 'fatal|panic|error|failed' | tail -5 | sed "s/^/$item: /" || true)
            signals+=$'\n'
        fi
    done
    if [ "$OS" = linux ] && command -v journalctl >/dev/null 2>&1; then
        signals+=$(journalctl -u plak.service --since '24 hours ago' -p err -n 5 --no-pager 2>/dev/null || true)
    fi
    # Age/recovery directories are candidates, not proof of abandonment.
    if [ -d "$SITES_DIR" ]; then
        abandoned=$(find "$SITES_DIR" -type d -name restore_recovery -print 2>/dev/null)
    fi
    if [ -d "$PLAK_SITE_DIR/cache/jobs" ]; then
        abandoned+=$'\n'
        abandoned+=$(find "$PLAK_SITE_DIR/cache/jobs" -type f -mtime +1 -print 2>/dev/null)
    fi
    if [ "$json" = true ]; then
        web=$(plak_health_web json) || web=null
        printf '{"platform":'; plak_json_string "$OS"
        printf ',"services":{"frankenphp":"%s","mariadb":"%s","mailpit":"%s"},"frankenphp_version":' "$frank" "$db" "$mail"
        if [ -n "$version" ]; then plak_json_string "$version"; else printf null; fi
        printf ',"disk":{"used_bytes":%s,"free_bytes":%s},"failure_signals":' "${used:-null}" "${free:-null}"
        plak_json_string "$signals"
        printf ',"abandoned_candidates":'; plak_json_string "$abandoned"
        printf ',"web_php":%s}\n' "${web:-null}"
    else
        plak_ui_title 'Plak health (read-only)'
        printf 'Platform: %s\nFrankenPHP: %s (%s)\nMariaDB: %s\nMailpit: %s\n' "$OS" "$frank" "${version:-version unknown}" "$db" "$mail"
        printf 'Disk: used=%s bytes; free=%s bytes (null = unknown)\n' "${used:-null}" "${free:-null}"
        printf '\nAvailable failure signals (not proven crash causes):\n%s\n' "${signals:-none available}"
        printf '\nRecovery/old-job candidates (inspect before removing):\n%s\n' "${abandoned:-none available}"
        plak_health_web text || echo 'Web PHP/OPcache: unknown; start Plak and run plak reload to deploy the probe.'
    fi
}

plak_health_opcache_valid() {
    local key="$1" value="$2" min max
    case "$key" in
        opcache.enable|opcache.validate_timestamps) [[ "$value" = 0 || "$value" = 1 ]]; return ;;
        opcache.memory_consumption) min=8; max=4096 ;;
        opcache.interned_strings_buffer) min=1; max=1024 ;;
        opcache.max_accelerated_files) min=200; max=1000000 ;;
        opcache.revalidate_freq) min=0; max=3600 ;;
        *) return 1 ;;
    esac
    [[ "$value" =~ ^(0|[1-9][0-9]{0,6})$ ]] || return 1
    [ "$value" -ge "$min" ] && [ "$value" -le "$max" ]
}

plak_health_opcache() {
    if [ "${1:-}" != set ]; then
        local format=text
        case "${1:-}" in --json) format=json; shift ;; esac
        [ "$#" -eq 0 ] || { plak_ui_error 'Usage: plak health opcache [--json]'; return 1; }
        plak_health_web "$format" || { plak_ui_error 'Web OPcache unknown: probe unavailable (no CLI-cache fallback).'; return 1; }
        return
    fi
    shift
    local restart=false item key value tmp content
    local -a settings=()
    for item in "$@"; do
        case "$item" in
            --restart|--apply) restart=true ;;
            --yes) : ;; # Not implicit permission to restart.
            *=*)
                key=${item%%=*}; value=${item#*=}
                plak_health_opcache_valid "$key" "$value" || { plak_ui_error "Invalid OPcache setting: $item"; return 1; }
                settings+=("$item") ;;
            *) plak_ui_error "Unknown argument: $item"; return 1 ;;
        esac
    done
    [ "${#settings[@]}" -gt 0 ] || { plak_ui_error 'Provide at least one directive=value.'; return 1; }
    [ -f "$PHP_INI_FILE" ] || { plak_ui_error "Missing $PHP_INI_FILE; run plak install."; return 1; }
    tmp=$(mktemp "$PHP_INI_FILE.XXXXXX") || return 1
    cp -p "$PHP_INI_FILE" "$tmp" || { rm -f "$tmp"; return 1; }
    for item in "${settings[@]}"; do
        key=${item%%=*}; value=${item#*=}
        content=$(awk -F= -v key="$key" '{k=$1; gsub(/^[ \t]+|[ \t]+$/, "", k); if(k!=key) print}' "$tmp") || { rm -f "$tmp"; return 1; }
        printf '%s\n%s = %s\n' "$content" "$key" "$value" > "$tmp" || { rm -f "$tmp"; return 1; }
    done
    mv "$tmp" "$PHP_INI_FILE" || return 1
    if [ "$restart" = true ]; then
        local SUDO_CMD="${SUDO_CMD:-}"
        # Explicit restart permission does not authorize an unattended password
        # prompt. sudo must fail actionably instead of waiting for input.
        if ! plak_has_tty && [ -n "$SUDO_CMD" ]; then SUDO_CMD="$SUDO_CMD -n"; fi
        regenerate_caddyfile || return 1
        start_caddy_service || return 1
        echo 'OPcache settings saved; FrankenPHP restarted. Verify with plak health opcache.'
    else
        echo 'OPcache settings saved; no reload/restart performed. Apply with the same command plus --restart.'
    fi
}

plak_health_http2() {
    local json=false negotiated=unknown configured
    case "${1:-}" in --json) json=true; shift ;; esac
    [ "$#" -eq 0 ] || { plak_ui_error 'Usage: plak health http2 [--json]'; return 1; }
    configured=$(plak_config_get HTTP2_ENABLED 0)
    if curl --version 2>/dev/null | grep -q HTTP2; then
        negotiated=$(curl --noproxy '*' --resolve "plak.localhost:${HTTPS_PORT}:127.0.0.1" \
            --http2 --connect-timeout 2 --max-time 5 -fksS -o /dev/null -w '%{http_version}' \
            "$(url_for plak.localhost)/health.php" 2>/dev/null) || negotiated=unknown
    fi
    if [ "$json" = true ]; then
        printf '{"configured_h2":%s,"negotiated":' "$([ "$configured" = 1 ] && echo true || echo false)"
        plak_json_string "$negotiated"; printf '}\n'
    else
        printf 'HTTP/2 configured: %s; negotiated: %s\n' "$configured" "$negotiated"
        echo 'A protocol probe is not a performance evaluation; see docs/health.md.'
    fi
}

# Source: commands/hosts
plak_hosts_entries() {
    local hosts_file="${1:-$PLAK_HOSTS_FILE}"

    [ -f "$hosts_file" ] || return 0

    awk '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        NF >= 2 {
            ip = $1
            for (i = 2; i <= NF; i++) {
                if ($i ~ /^#/) break
                print ip "," $i
            }
        }
    ' "$hosts_file"
}

plak_hosts_exists() {
    local domain="$1"
    plak_hosts_entries | awk -F, -v target="$domain" '$2 == target { found = 1 } END { exit found ? 0 : 1 }'
}

plak_hosts_validate_name() {
    local domain="$1"
    [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] && [[ "$domain" == *.* || "$domain" == "localhost" ]]
}

plak_hosts_validate_ip() {
    local ip="$1"
    [[ "$ip" =~ ^[A-Za-z0-9:.%-]+$ ]]
}

plak_hosts_write_hosts_file() {
    local tmp_file="$1" backup_path
    backup_path="${PLAK_HOSTS_FILE}.plak.bak.$(date +%Y%m%d%H%M%S)"

    if [ -w "$PLAK_HOSTS_FILE" ]; then
        cp "$PLAK_HOSTS_FILE" "$backup_path"
        cat "$tmp_file" > "$PLAK_HOSTS_FILE"
        return 0
    fi

    sudo cp "$PLAK_HOSTS_FILE" "$backup_path"
    sudo cp "$tmp_file" "$PLAK_HOSTS_FILE"
}

plak_hosts_add_entry() {
    local ip="$1" domain="$2" tmp_file

    [ -f "$PLAK_HOSTS_FILE" ] || {
        plak_ui_error "Hosts file not found: $PLAK_HOSTS_FILE"
        return 1
    }

    if plak_hosts_exists "$domain"; then
        plak_ui_error "Host entry '$domain' already exists in $PLAK_HOSTS_FILE."
        return 1
    fi

    tmp_file=$(mktemp)
    cat "$PLAK_HOSTS_FILE" > "$tmp_file"
    printf '\n%s\t%s # plak\n' "$ip" "$domain" >> "$tmp_file"

    plak_hosts_write_hosts_file "$tmp_file"
    rm -f "$tmp_file"
}

plak_hosts_remove_entry() {
    local domain="$1" tmp_file

    [ -f "$PLAK_HOSTS_FILE" ] || return 1
    tmp_file=$(mktemp)

    awk -v target="$domain" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
        {
            hash = 0
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^#/) { hash = i; break }
            }
            max = hash ? hash - 1 : NF
            if (max < 2) { print; next }

            ip = $1
            keep = ""
            removed_here = 0
            for (i = 2; i <= max; i++) {
                if ($i == target) {
                    removed_here = 1
                } else {
                    keep = keep (keep ? " " : "") $i
                }
            }

            if (!removed_here) { print; next }
            found = 1
            if (keep != "") {
                line = ip "\t" keep
                if (hash) {
                    comment = ""
                    for (i = hash; i <= NF; i++) comment = comment (comment ? " " : "") $i
                    line = line " " comment
                }
                print line
            }
        }
        END { if (!found) exit 2 }
    ' "$PLAK_HOSTS_FILE" > "$tmp_file" || {
        local code=$?
        rm -f "$tmp_file"
        return "$code"
    }

    plak_hosts_write_hosts_file "$tmp_file"
    rm -f "$tmp_file"
}

plak_hosts_list() {
    if [ ! -f "$PLAK_HOSTS_FILE" ]; then
        plak_ui_warn "Hosts file not found: $PLAK_HOSTS_FILE"
        return 0
    fi

    local rows
    rows=$(plak_hosts_entries)

    if [ -z "$rows" ]; then
        plak_ui_warn "No hosts entries found."
        return 0
    fi

    if plak_command_exists gum && [ -t 1 ]; then
        {
            echo "IP,Domain"
            echo "$rows"
        } | gum table --separator ","
    else
        echo "$rows" | column -t -s ',' 2>/dev/null || echo "$rows"
    fi
}

plak_hosts_add() {
    local domain="" ip="" yes=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --ip) ip="$2"; shift 2 ;;
            --yes|-y) yes=1; shift 1 ;;
            -*) plak_ui_error "Unknown flag: $1"; exit 1 ;;
            *)
                if [ -z "$ip" ]; then
                    ip="$1"
                elif [ -z "$domain" ]; then
                    domain="$1"
                fi
                shift 1
                ;;
        esac
    done

    local have_all=1
    [ -z "$ip" ] && have_all=0
    [ -z "$domain" ] && have_all=0

    if [ "$have_all" -eq 0 ]; then
        plak_require_gum
        plak_ui_title "Add hosts entry"
    fi

    if [ -z "$domain" ]; then
        while true; do
            domain=$(gum input --prompt "Domain: " --placeholder "site.localhost")
            [ -n "$domain" ] || return 0
            if plak_hosts_validate_name "$domain"; then
                break
            fi
            plak_ui_error "Invalid domain name."
        done
    else
        if ! plak_hosts_validate_name "$domain"; then
            plak_ui_error "Invalid domain name '$domain'."
            exit 1
        fi
    fi

    if [ -z "$ip" ]; then
        while true; do
            ip=$(gum input --prompt "IP: " --value "127.0.0.1")
            [ -n "$ip" ] || return 0
            if plak_hosts_validate_ip "$ip"; then
                break
            fi
            plak_ui_error "Invalid IP or host value."
        done
    else
        if ! plak_hosts_validate_ip "$ip"; then
            plak_ui_error "Invalid IP '$ip'."
            exit 1
        fi
    fi

    if [ "$have_all" -eq 0 ]; then
        gum style --border normal --margin "1 0" --padding "1 2" --border-foreground 212 \
            "Hosts entry" \
            "$ip    $domain"

        if [ "$yes" -eq 0 ]; then
            if ! gum confirm "Add this entry to $PLAK_HOSTS_FILE?"; then
                plak_ui_warn "Cancelled."
                return 0
            fi
        fi
    fi

    plak_hosts_add_entry "$ip" "$domain"
    plak_ui_success "Host entry '$domain' added to $PLAK_HOSTS_FILE."
}

plak_hosts_delete() {
    local domain="" yes=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --yes|-y) yes=1; shift 1 ;;
            -*) plak_ui_error "Unknown flag: $1"; exit 1 ;;
            *) domain="$1"; shift 1 ;;
        esac
    done

    if [ -z "$domain" ]; then
        plak_require_gum
        local rows
        rows=$(plak_hosts_entries)
        if [ -z "$rows" ]; then
            plak_ui_warn "No hosts entries found."
            return 0
        fi
        local selected
        selected=$(echo "$rows" | awk -F, '{ print $2 "    " $1 }' | gum filter --placeholder "Choose domain to delete")
        [ -n "$selected" ] || return 0
        domain=$(echo "$selected" | awk '{ print $1 }')
    fi

    if [ "$yes" -eq 0 ]; then
        if [ -t 0 ] && plak_command_exists gum; then
            plak_require_gum
            if ! gum confirm "Delete domain '$domain' from $PLAK_HOSTS_FILE?"; then
                plak_ui_warn "Cancelled."
                return 0
            fi
        else
            plak_ui_error "Refusing to delete '$domain' without --yes in non-interactive mode."
            exit 1
        fi
    fi

    plak_hosts_remove_entry "$domain"
    plak_ui_success "Host entry '$domain' deleted from $PLAK_HOSTS_FILE."
}

plak_hosts() {
    local action="${1:-help}"
    if [ "$#" -gt 0 ]; then
        shift
    fi

    case "$action" in
        list|view)
            plak_hosts_list "$@"
            ;;
        add|create)
            plak_hosts_add "$@"
            ;;
        delete|remove)
            plak_hosts_delete "$@"
            ;;
        help|--help|-h)
            plak_display_command_help hosts
            ;;
        *)
            plak_ui_error "Unknown hosts action '$action'"
            plak_display_command_help hosts
            exit 1
            ;;
    esac
}

# Source: commands/install
plak_install() {
    plak_site_install "$@"
}

# Source: commands/remote
plak_remote_parse_hosts() {
    local config_path="${1:-$PLAK_SSH_CONFIG}"

    [ -f "$config_path" ] || return 0

    awk '
        BEGIN { IGNORECASE = 1 }
        /^[ \t]*Host[ \t]+/ {
            if (cur_name != "") printf "%s|%s|%s|%s|%s|%s\n", cur_name, cur_host, cur_user, cur_port, cur_idf, cur_path
            cur_name = ""; cur_host = ""; cur_user = ""; cur_port = ""; cur_idf = ""; cur_path = ""
            for (i = 2; i <= NF; i++) {
                if ($i !~ /[*?]/) { cur_name = $i; break }
            }
            next
        }
        /^[ \t]+HostName[ \t]+/ { cur_host = $2; next }
        /^[ \t]+User[ \t]+/ { cur_user = $2; next }
        /^[ \t]+Port[ \t]+/ { cur_port = $2; next }
        /^[ \t]+IdentityFile[ \t]+/ { cur_idf = $2; next }
        /^[ \t]+# plak-remote-path[ \t]*:/ {
            sub(/^[ \t]+# plak-remote-path[ \t]*:[ \t]*/, "")
            cur_path = $0
            next
        }
        END { if (cur_name != "") printf "%s|%s|%s|%s|%s|%s\n", cur_name, cur_host, cur_user, cur_port, cur_idf, cur_path }
    ' "$config_path"
}

plak_remote_host_exists() {
    local name="$1"
    plak_remote_parse_hosts | awk -F'|' -v target="$name" '$1 == target { found = 1 } END { exit found ? 0 : 1 }'
}

plak_remote_get_host() {
    local name="$1"
    plak_remote_parse_hosts | awk -F'|' -v target="$name" '$1 == target { print; exit }'
}

plak_remote_ensure_config() {
    local config_dir
    config_dir=$(dirname "$PLAK_SSH_CONFIG")

    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
        chmod 700 "$config_dir"
    fi

    if [ ! -f "$PLAK_SSH_CONFIG" ]; then
        : > "$PLAK_SSH_CONFIG"
        chmod 600 "$PLAK_SSH_CONFIG"
    fi
}

plak_remote_append_config() {
    local name="$1" hostname="$2" user="$3" port="$4" identity_file="${5:-}" remote_path="${6:-}"

    plak_remote_ensure_config

    {
        echo ""
        echo "Host $name"
        echo "    HostName $hostname"
        echo "    User $user"
        echo "    Port $port"
        if [ -n "$identity_file" ]; then
            echo "    IdentityFile $identity_file"
        fi
        if [ -n "$remote_path" ]; then
            echo "    # plak-remote-path: $remote_path"
        fi
    } >> "$PLAK_SSH_CONFIG"
}

plak_remote_remove_config() {
    local name="$1" tmp_file

    [ -f "$PLAK_SSH_CONFIG" ] || return 1
    tmp_file=$(mktemp)

    awk -v target="$name" '
        /^[ \t]*Host[ \t]+/ {
            skip = 0
            for (i = 2; i <= NF; i++) {
                if ($i == target) { skip = 1; found = 1; break }
            }
        }
        skip == 0 { print }
        END { if (!found) exit 2 }
    ' "$PLAK_SSH_CONFIG" > "$tmp_file" || {
        local code=$?
        rm -f "$tmp_file"
        return "$code"
    }

    cat "$tmp_file" > "$PLAK_SSH_CONFIG"
    rm -f "$tmp_file"
}

plak_remote_replace_config() {
    local old_name="$1" new_name="$2" hostname="$3" user="$4" port="$5" identity_file="${6:-}" remote_path="${7:-}"
    local tmp_file
    tmp_file=$(mktemp)

    awk -v old="$old_name" -v new="$new_name" -v host="$hostname" -v usr="$user" -v prt="$port" -v idf="$identity_file" -v rp="$remote_path" '
        function emit_new() {
            print ""
            print "Host " new
            print "    HostName " host
            print "    User " usr
            print "    Port " prt
            if (idf != "") print "    IdentityFile " idf
            if (rp != "") print "    # plak-remote-path: " rp
            pending = 0
        }
        BEGIN { skip = 0; found = 0; pending = 0 }
        /^[ \t]*Host[ \t]+/ {
            if (skip == 1 && pending == 1) emit_new()
            skip = 0
            for (i = 2; i <= NF; i++) {
                if ($i == old) { skip = 1; found = 1; pending = 1; break }
            }
            if (skip == 0) print
            next
        }
        skip == 0 { print }
        END { if (pending == 1) emit_new() }
    ' "$PLAK_SSH_CONFIG" > "$tmp_file" || {
        local code=$?
        rm -f "$tmp_file"
        return "$code"
    }

    cat "$tmp_file" > "$PLAK_SSH_CONFIG"
    rm -f "$tmp_file"
}

plak_remote_list() {
    local entries managed_only=0 unmanaged_only=0 json=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --managed)   managed_only=1; shift 1 ;;
            --unmanaged) unmanaged_only=1; shift 1 ;;
            --json)      json=1; shift 1 ;;
            -*)
                plak_ui_error "Unknown list flag '$1'"
                exit 1
                ;;
            *) shift 1 ;;
        esac
    done

    entries=$(plak_remote_parse_hosts)
    if [ -z "$entries" ]; then
        if [ "$json" -eq 1 ]; then
            printf "[]\n"
        else
            plak_ui_warn "No SSH hosts found in $PLAK_SSH_CONFIG."
        fi
        return 0
    fi

    local filtered
    if [ "$managed_only" = 1 ]; then
        filtered=$(printf "%s\n" "$entries" | awk -F'|' '$6 != ""')
    elif [ "$unmanaged_only" = 1 ]; then
        filtered=$(printf "%s\n" "$entries" | awk -F'|' '$6 == ""')
    else
        filtered="$entries"
    fi

    if [ -z "$filtered" ]; then
        if [ "$json" -eq 1 ]; then
            printf "[]\n"
            return 0
        fi
        if [ "$managed_only" = 1 ]; then
            plak_ui_warn "No managed remotes (with plak-remote-path) found."
        else
            plak_ui_warn "No unmanaged remotes (without plak-remote-path) found."
        fi
        return 0
    fi

    if [ "$json" -eq 1 ]; then
        printf "%s\n" "$filtered" | awk -F'|' '
            function esc(s) {
                gsub(/\\/, "\\\\", s)
                gsub(/"/, "\\\"", s)
                gsub(/\n/, "\\n", s)
                return s
            }
            BEGIN { first = 1; printf "[" }
            {
                if (!first) printf ","
                first = 0
                printf "{\"name\":\"%s\",\"host\":\"%s\",\"user\":\"%s\",\"port\":\"%s\",\"identity\":\"%s\",\"path\":\"%s\"}",
                    esc($1), esc($2), esc($3), esc($4), esc($5), esc($6)
            }
            END { printf "]\n" }
        '
        return 0
    fi

    if plak_command_exists gum && [ -t 1 ]; then
        {
            echo "Name"$'\t'"Host"$'\t'"User"$'\t'"Port"$'\t'"Path"
            printf "%s\n" "$filtered" | awk -F'|' 'BEGIN { OFS="\t" } { print $1, $2, $3, $4, ($6 == "" ? "(no path)" : $6) }'
        } | gum table --columns "Name,Host,User,Port,Path" --widths "16,28,12,6,22" --border rounded --padding "0 1"
    else
        printf "%-16s %-28s %-12s %-6s %s\n" "Name" "Host" "User" "Port" "Path"
        printf "%-16s %-28s %-12s %-6s %s\n" "----------------" "----------------------------" "------------" "------" "----------------------"
        printf "%s\n" "$filtered" | awk -F'|' '{ p = ($6 == "" ? "(no path)" : $6); printf "%-16s %-28s %-12s %-6s %s\n", $1, $2, $3, $4, p }'
    fi
}

plak_remote_pick_identity() {
    local identity_file=""
    local identity_choice
    identity_choice=$(find "$HOME/.ssh" -maxdepth 1 -type f \
        ! -name '.*' \
        ! -name '*.pub' \
        ! -name 'authorized_keys' \
        ! -name 'known_hosts*' \
        ! -name '*_known_hosts' \
        ! -name 'config' \
        -exec sh -c 'head -n 1 "$1" 2>/dev/null | grep -q "PRIVATE KEY"' sh {} \; \
        -print 2>/dev/null | sort || true)
    if [ -n "$identity_choice" ]; then
        identity_file=$(echo "$identity_choice" | gum filter --placeholder "Choose identity file or press Esc") || identity_file=""
    fi
    if [ -z "$identity_file" ]; then
        identity_file=$(gum input --prompt "IdentityFile: " --placeholder "~/.ssh/id_ed25519")
    fi
    printf '%s\n' "$identity_file"
}

plak_remote_prompt_path() {
    local default="${1:-public/}"
    local current="${2:-}"
    local value
    if [ -n "$current" ]; then
        value=$(gum input --width 0 --value "$current" --prompt "Remote path (WordPress root): ")
    else
        value=$(gum input --width 0 --value "$default" --prompt "Remote path (WordPress root): ")
    fi
    printf '%s\n' "$value"
}

plak_remote_add() {
    local name="" host="" user="" port="22" identity_file="" remote_path="public/"
    local set_identity=0
    local positional=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --host) host="$2"; shift 2 ;;
            --user) user="$2"; shift 2 ;;
            --port) port="$2"; shift 2 ;;
            --path) remote_path="$2"; shift 2 ;;
            --identity) identity_file="$2"; set_identity=1; shift 2 ;;
            --no-identity) identity_file=""; set_identity=1; shift 1 ;;
            -*)
                plak_ui_error "Unknown flag: $1"
                plak_display_command_help remote
                exit 1
                ;;
            *) positional+=("$1"); shift 1 ;;
        esac
    done

    if [ ${#positional[@]} -gt 0 ]; then
        name="${positional[0]}"
    fi

    local have_all=1
    [ -z "$name" ] && have_all=0
    [ -z "$host" ] && have_all=0
    [ -z "$user" ] && have_all=0

    if [ "$have_all" -eq 0 ]; then
        plak_require_gum
        plak_ui_title "Add Plak remote"
    fi

    if [ -z "$name" ]; then
        while true; do
            name=$(gum input --prompt "Name: " --placeholder "prod")
            [ -n "$name" ] || return 0

            if ! plak_validate_hostname_alias "$name"; then
                plak_ui_error "Use only letters, numbers, dots, underscores and hyphens."
                continue
            fi

            if plak_remote_host_exists "$name"; then
                plak_ui_error "Remote '$name' already exists."
                continue
            fi
            break
        done
    else
        if ! plak_validate_hostname_alias "$name"; then
            plak_ui_error "Invalid name '$name'. Use only letters, numbers, dots, underscores and hyphens."
            exit 1
        fi
        if plak_remote_host_exists "$name"; then
            plak_ui_error "Remote '$name' already exists."
            exit 1
        fi
    fi

    if [ -z "$host" ]; then
        host=$(gum input --prompt "Hostname/IP: " --placeholder "example.com")
        [ -n "$host" ] || return 0
    fi

    if [ -z "$user" ]; then
        user=$(gum input --prompt "User: " --placeholder "ubuntu")
        [ -n "$user" ] || return 0
    fi

    if ! plak_validate_port "$port"; then
        plak_ui_error "Invalid port '$port'. Use a number from 1 to 65535."
        exit 1
    fi

    if [ "$have_all" -eq 0 ] && [ "$set_identity" -eq 0 ]; then
        if gum confirm "Use an identity file?"; then
            identity_file=$(plak_remote_pick_identity)
            set_identity=1
        fi
    fi

    if [ "$have_all" -eq 0 ] && [ -z "$remote_path" -o "$remote_path" = "public/" ]; then
        local prompted_path
        prompted_path=$(plak_remote_prompt_path "public/")
        [ -n "$prompted_path" ] || return 0
        remote_path="$prompted_path"
    fi

    if [ "$have_all" -eq 0 ]; then
        echo ""
        gum style --border normal --margin "1 0" --padding "1 2" --border-foreground 212 \
            "Host $name" \
            "HostName $host" \
            "User $user" \
            "Port $port" \
            "IdentityFile ${identity_file:-none}" \
            "RemotePath ${remote_path}"

        if ! gum confirm "Save this remote?"; then
            plak_ui_warn "Cancelled."
            return 0
        fi
    fi

    if [ "$set_identity" -eq 0 ]; then
        identity_file=""
    fi

    plak_remote_append_config "$name" "$host" "$user" "$port" "$identity_file" "$remote_path"
    plak_ui_success "Remote '$name' added to $PLAK_SSH_CONFIG."
}

plak_remote_edit() {
    local name="" newname="" host="" user="" port="" remote_path="" identity_file=""
    local identity_mode="unchanged"
    local positional=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --newname) newname="$2"; shift 2 ;;
            --host) host="$2"; shift 2 ;;
            --user) user="$2"; shift 2 ;;
            --port) port="$2"; shift 2 ;;
            --path) remote_path="$2"; shift 2 ;;
            --identity) identity_file="$2"; identity_mode="set"; shift 2 ;;
            --no-identity) identity_file=""; identity_mode="cleared"; shift 1 ;;
            -*)
                plak_ui_error "Unknown flag: $1"
                plak_display_command_help remote
                exit 1
                ;;
            *) positional+=("$1"); shift 1 ;;
        esac
    done

    if [ ${#positional[@]} -gt 0 ]; then
        name="${positional[0]}"
    fi

    local have_any=0
    [ -n "$newname" ] && have_any=1
    [ -n "$host" ] && have_any=1
    [ -n "$user" ] && have_any=1
    [ -n "$port" ] && have_any=1
    [ -n "$remote_path" ] && have_any=1
    [ "$identity_mode" != "unchanged" ] && have_any=1

    if [ -z "$name" ]; then
        plak_require_gum
        local entries
        entries=$(plak_remote_parse_hosts)
        if [ -z "$entries" ]; then
            plak_ui_warn "No SSH hosts found in $PLAK_SSH_CONFIG."
            return 0
        fi
        name=$(printf "%s\n" "$entries" | awk -F'|' '{print $1}' | gum filter --placeholder "Choose remote to edit")
        [ -n "$name" ] || return 0
    fi

    local current
    current=$(plak_remote_get_host "$name")
    if [ -z "$current" ]; then
        plak_ui_error "Remote '$name' does not exist."
        exit 1
    fi

    local cur_host cur_user cur_port cur_idf cur_path
    IFS='|' read -r _ cur_host cur_user cur_port cur_idf cur_path <<< "$current"

    if [ "$have_any" -eq 0 ]; then
        plak_require_gum
        plak_ui_title "Edit remote: $name"

        newname=$(gum input --prompt "Name: " --value "$name")
        [ -n "$newname" ] || return 0

        host=$(gum input --prompt "Hostname/IP: " --value "$cur_host")
        [ -n "$host" ] || return 0

        user=$(gum input --prompt "User: " --value "$cur_user")
        [ -n "$user" ] || return 0

        while true; do
            port=$(gum input --prompt "Port: " --value "${cur_port:-22}")
            if plak_validate_port "$port"; then
                break
            fi
            plak_ui_error "Invalid port. Use a number from 1 to 65535."
        done

        if gum confirm "Use an identity file?" --affirmative "Yes" --negative "Keep current"; then
            identity_file=$(plak_remote_pick_identity)
            identity_mode="set"
        else
            identity_file="$cur_idf"
            identity_mode="unchanged"
        fi

        remote_path=$(plak_remote_prompt_path "public/" "$cur_path")
        [ -n "$remote_path" ] || return 0

        echo ""
        gum style --border normal --margin "1 0" --padding "1 2" --border-foreground 212 \
            "Host $newname" \
            "HostName $host" \
            "User $user" \
            "Port $port" \
            "IdentityFile ${identity_file:-none}" \
            "RemotePath ${remote_path}"

        if ! gum confirm "Save these changes?"; then
            plak_ui_warn "Cancelled."
            return 0
        fi
    fi

    [ -z "$newname" ] && newname="$name"
    [ -z "$host" ] && host="$cur_host"
    [ -z "$user" ] && user="$cur_user"
    [ -z "$port" ] && port="${cur_port:-22}"
    [ -z "$remote_path" ] && remote_path="$cur_path"
    case "$identity_mode" in
        unchanged) identity_file="$cur_idf" ;;
        cleared)   identity_file="" ;;
        set)       : ;;
    esac

    if [ "$newname" != "$name" ]; then
        if ! plak_validate_hostname_alias "$newname"; then
            plak_ui_error "Invalid new name '$newname'."
            exit 1
        fi
        if plak_remote_host_exists "$newname"; then
            plak_ui_error "Remote '$newname' already exists."
            exit 1
        fi
    fi

    if ! plak_validate_port "$port"; then
        plak_ui_error "Invalid port '$port'."
        exit 1
    fi

    plak_remote_replace_config "$name" "$newname" "$host" "$user" "$port" "$identity_file" "$remote_path"
    plak_ui_success "Remote '$newname' updated."
}

plak_remote_delete() {
    local name="" yes=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --yes|-y) yes=1; shift 1 ;;
            -*)
                plak_ui_error "Unknown flag: $1"
                exit 1
                ;;
            *) name="$1"; shift 1 ;;
        esac
    done

    if [ -z "$name" ]; then
        plak_require_gum
        local entries
        entries=$(plak_remote_parse_hosts)
        if [ -z "$entries" ]; then
            plak_ui_warn "No SSH hosts found in $PLAK_SSH_CONFIG."
            return 0
        fi
        name=$(printf "%s\n" "$entries" | awk -F'|' '{print $1}' | gum filter --placeholder "Choose remote to delete")
        [ -n "$name" ] || return 0
    fi

    if [ -z "$(plak_remote_get_host "$name")" ]; then
        plak_ui_error "Remote '$name' does not exist."
        exit 1
    fi

    if [ "$yes" -eq 0 ]; then
        if [ -t 0 ] && plak_command_exists gum; then
            if ! gum confirm "Delete remote '$name'?"; then
                plak_ui_warn "Cancelled."
                return 0
            fi
        else
            plak_ui_error "Refusing to delete '$name' without --yes in non-interactive mode."
            exit 1
        fi
    fi

    if plak_remote_remove_config "$name"; then
        plak_ui_success "Remote '$name' deleted."
    else
        plak_ui_error "Could not delete remote '$name'."
        exit 1
    fi
}

plak_remote_connect() {
    local name="${1:-}"
    local entries
    entries=$(plak_remote_parse_hosts)

    if [ -z "$entries" ]; then
        plak_ui_warn "No SSH hosts found in $PLAK_SSH_CONFIG."
        return 0
    fi

    if [ -z "$name" ]; then
        plak_require_gum
        name=$(printf "%s\n" "$entries" | awk -F'|' '{print $1}' | gum filter --placeholder "Choose remote")
        [ -n "$name" ] || return 0
    fi

    if ! plak_validate_hostname_alias "$name"; then
        plak_ui_error "Invalid remote alias: $name"
        exit 1
    fi

    if [ -z "$(plak_remote_get_host "$name")" ]; then
        plak_ui_error "Remote '$name' does not exist in $PLAK_SSH_CONFIG."
        exit 1
    fi

    local remote_path
    remote_path=$(plak_remote_get_host "$name" | awk -F'|' '{print $6}')

    plak_ui_success "Connecting to $name..."
    if [ -n "$remote_path" ]; then
        ssh -t "$name" "cd $(shell_quote "$remote_path") && exec \$SHELL"
    else
        ssh "$name"
    fi
}

plak_remote_attach() {
    local remote_name="" site_name="" yes=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --yes|-y) yes=1; shift 1 ;;
            -*)
                plak_ui_error "Unknown flag: $1"
                exit 1
                ;;
            *)
                if [ -z "$remote_name" ]; then
                    remote_name="$1"
                elif [ -z "$site_name" ]; then
                    site_name="$1"
                fi
                shift 1
                ;;
        esac
    done

    if [ -n "$remote_name" ] && [ -n "$site_name" ]; then
        plak_remote_attach_to "$remote_name" "$site_name" "$yes"
        return $?
    fi

    plak_require_gum

    local entries sites site_dirs
    entries=$(plak_remote_parse_hosts)
    if [ -z "$entries" ]; then
        plak_ui_warn "No SSH hosts found in $PLAK_SSH_CONFIG. Add one with 'plak remote add'."
        return 0
    fi

    if [ -z "$site_name" ]; then
        site_dirs=$(find "$SITES_DIR" -maxdepth 1 -mindepth 1 -type d -name '*.localhost' 2>/dev/null | sort)
        if [ -z "$site_dirs" ]; then
            plak_ui_warn "No Plak sites found under $SITES_DIR."
            return 0
        fi
        sites=$(printf "%s\n" "$site_dirs" | awk -F/ '{print $NF}' | sed 's/\.localhost$//')
        site_name=$(printf "%s\n" "$sites" | gum filter --placeholder "Choose site to attach")
        [ -n "$site_name" ] || return 0
    fi

    if [ -z "$remote_name" ]; then
        remote_name=$(printf "%s\n" "$entries" | awk -F'|' '{print $1}' | gum filter --placeholder "Choose remote to attach")
        [ -n "$remote_name" ] || return 0
    fi

    plak_remote_attach_to "$remote_name" "$site_name" "$yes"
}

plak_remote_attach_to() {
    local remote_name="$1" site_name="$2" yes="${3:-0}"
    local site_dir="$SITES_DIR/$site_name.localhost"
    local binding_file="$site_dir/.remote"

    if [ ! -d "$site_dir" ]; then
        plak_ui_error "Site '$site_name' does not exist under $SITES_DIR."
        exit 1
    fi

    if [ -z "$(plak_remote_get_host "$remote_name")" ]; then
        plak_ui_error "Remote '$remote_name' does not exist in $PLAK_SSH_CONFIG."
        exit 1
    fi

    local remote_path
    remote_path=$(plak_remote_get_host "$remote_name" | awk -F'|' '{print $6}')
    if [ -z "$remote_path" ]; then
        plak_ui_warn "Remote '$remote_name' has no remote_path set. Run 'plak remote edit $remote_name' to set one — push/pull will still ask for the path until then."
    fi

    if [ -f "$binding_file" ]; then
        local current_binding
        current_binding=$(cat "$binding_file")
        if [ "$current_binding" = "$remote_name" ]; then
            plak_ui_warn "Site '$site_name' is already attached to '$remote_name'."
            return 0
        fi
        if [ "$yes" -eq 0 ]; then
            if [ -t 0 ] && plak_command_exists gum; then
                if ! gum confirm "Site '$site_name' is already attached to '$current_binding'. Replace with '$remote_name'?"; then
                    plak_ui_warn "Cancelled."
                    return 0
                fi
            else
                plak_ui_error "Site '$site_name' is already attached to '$current_binding'. Use --yes to replace in non-interactive mode."
                exit 1
            fi
        fi
    fi

    printf '%s\n' "$remote_name" > "$binding_file"
    plak_ui_success "Attached '$remote_name' to site '$site_name'."
}

plak_remote_detach() {
    local site_name="" yes=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --yes|-y) yes=1; shift 1 ;;
            -*)
                plak_ui_error "Unknown flag: $1"
                exit 1
                ;;
            *) site_name="$1"; shift 1 ;;
        esac
    done

    if [ -z "$site_name" ]; then
        plak_require_gum

        local site_dirs sites binding_files
        site_dirs=$(find "$SITES_DIR" -maxdepth 1 -mindepth 1 -type d -name '*.localhost' 2>/dev/null | sort)
        if [ -z "$site_dirs" ]; then
            plak_ui_warn "No Plak sites found under $SITES_DIR."
            return 0
        fi

        binding_files=$(printf "%s\n" "$site_dirs" | while read -r d; do
            f="$d/.remote"
            if [ -f "$f" ]; then
                printf "%s\n" "${d##*/}" | sed 's/\.localhost$//'
            fi
        done)

        if [ -z "$binding_files" ]; then
            plak_ui_warn "No attached remotes found."
            return 0
        fi

        site_name=$(printf "%s\n" "$binding_files" | gum filter --placeholder "Choose site to detach")
        [ -n "$site_name" ] || return 0
    fi

    local site_dir="$SITES_DIR/$site_name.localhost"
    local binding_file="$site_dir/.remote"

    if [ ! -d "$site_dir" ]; then
        plak_ui_error "Site '$site_name' does not exist under $SITES_DIR."
        exit 1
    fi

    if [ ! -f "$binding_file" ]; then
        plak_ui_warn "Site '$site_name' has no remote attached."
        return 0
    fi

    local current_binding
    current_binding=$(cat "$binding_file")

    if [ "$yes" -eq 0 ]; then
        if [ -t 0 ] && plak_command_exists gum; then
            if ! gum confirm "Detach site '$site_name' from remote '$current_binding'?"; then
                plak_ui_warn "Cancelled."
                return 0
            fi
        else
            plak_ui_error "Site '$site_name' is attached to '$current_binding'. Use --yes to detach in non-interactive mode."
            exit 1
        fi
    fi

    rm -f "$binding_file"
    plak_ui_success "Detached '$site_name' from '$current_binding'."
}

plak_remote_get_binding() {
    local site_name="$1"
    local binding_file="$SITES_DIR/$site_name.localhost/.remote"

    [ -f "$binding_file" ] || return 1
    local remote_name
    remote_name=$(cat "$binding_file")
    [ -n "$remote_name" ] || return 1

    local host_data
    host_data=$(plak_remote_get_host "$remote_name")
    [ -n "$host_data" ] || return 2

    local remote_path
    remote_path=$(printf "%s\n" "$host_data" | awk -F'|' '{print $6}')
    [ -n "$remote_path" ] || return 3

    printf '%s|%s\n' "$remote_name" "$remote_path"
    return 0
}

plak_remote() {
    local action="${1:-help}"
    if [ "$#" -gt 0 ]; then
        shift
    fi

    case "$action" in
        list|view)
            plak_remote_list "$@"
            ;;
        connect)
            plak_remote_connect "$@"
            ;;
        add|create)
            plak_remote_add "$@"
            ;;
        edit|update)
            plak_remote_edit "$@"
            ;;
        delete|remove)
            plak_remote_delete "$@"
            ;;
        attach)
            plak_remote_attach "$@"
            ;;
        detach)
            plak_remote_detach "$@"
            ;;
        help|--help|-h)
            plak_display_command_help remote
            ;;
        *)
            plak_ui_error "Unknown remote action '$action'"
            plak_display_command_help remote
            exit 1
            ;;
    esac
}

# Source: commands/site/add
# Runs only inside plak_site_add's subshell. The directory and database flags
# are set after exclusive creation succeeds; an existing resource is never ours.
plak_site_add_cleanup() {
    local rc="$1" site_dir="$2" db_name="$3" db_created="$4"
    if [ "$db_created" = true ]; then
        if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
            -e "DROP DATABASE \`$db_name\`;"; then
            echo "Error: could not clean up newly created database '$db_name'; remove it manually before retrying." >&2
        fi
    fi
    if ! rm -rf -- "$site_dir"; then
        echo "Error: could not clean up newly created directory '$site_dir'." >&2
    fi
    return "$rc"
}

plak_site_add() (
    # Isolate cwd and cleanup traps from callers such as pull and the dashboard.
    # Every mandatory step is checked explicitly: main disables errexit for
    # legacy site commands, and an outer conditional can disable it too.
    local site_name="" site_type="wordpress" no_reload_flag=false agent_mode=""
    local agent_flag="" arg wp_version="latest" version_flag=false multisite=""
    while [ "$#" -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --multisite)
                [ "$#" -ge 2 ] || { echo 'Error: --multisite requires subdomains or subdirectories.' >&2; exit 1; }
                multisite="$2"; shift
                [[ "$multisite" = subdomains || "$multisite" = subdirectories ]] || { echo 'Error: invalid multisite mode.' >&2; exit 1; } ;;
            --wp-version)
                [ "$#" -ge 2 ] || { echo 'Error: --wp-version requires latest, nightly or a release number.' >&2; exit 1; }
                wp_version="$2"; version_flag=true; shift ;;
            --plain) site_type="plain" ;;
            --no-reload) no_reload_flag=true ;;
            --agent) agent_mode=true agent_flag="true" ;;
            --no-agent) agent_mode=false agent_flag="false" ;;
            --help|-h) plak_display_command_help add; exit 0 ;;
            -*) echo "Error: unknown option '$arg'." >&2; exit 1 ;;
            *)
                if [ -n "$site_name" ]; then
                    echo "Error: unexpected argument '$arg'." >&2
                    exit 1
                fi
                site_name="$arg"
                ;;
        esac
        shift
    done
    if [ -n "$multisite" ] && [ "$site_type" = plain ]; then
        echo 'Error: --multisite cannot be combined with --plain.' >&2; exit 1
    fi
    if [ -n "$multisite" ]; then
        if [ "$agent_flag" = true ]; then echo 'Error: automatic agent preparation has no multisite scope; use explicit network/subsite WP-CLI commands.' >&2; exit 1; fi
        agent_flag=false; agent_mode=false
    fi
    plak_core_version_valid "$wp_version" || { echo "Error: invalid WordPress version '$wp_version'; use latest, nightly or a release such as 6.8.1." >&2; exit 1; }
    if [ "$version_flag" = true ] && [ "$site_type" = plain ]; then
        echo 'Error: --wp-version applies only to WordPress sites; omit it with --plain.' >&2
        exit 1
    fi
    if [ "$agent_flag" = "true" ] && [ "$site_type" = plain ]; then
        echo "Error: --agent prepares a WordPress site for WP-MCP and cannot be combined with --plain." >&2
        exit 1
    fi
    # Default: a new WordPress site becomes agent-ready when wp-mcp-cli is
    # available, without anyone having to remember --agent. --no-agent opts out.
    if [ -z "$agent_flag" ] && [ "$site_type" = wordpress ]; then
        if plak_agent_wpmcp_available; then
            agent_mode=true
        else
            agent_mode=false
        fi
    fi
    if ! plak_validate_site_name "$site_name"; then
        echo "Error: a site name of 1–63 lowercase letters, numbers or hyphens is required; it cannot start or end with a hyphen." >&2
        plak_display_command_help add >&2
        exit 1
    fi
    local protected_name
    for protected_name in $PROTECTED_NAMES; do
        if [ "$site_name" = "$protected_name" ]; then
            echo "Error: '$site_name' is a reserved name." >&2
            exit 1
        fi
    done

    local site_dir="$SITES_DIR/$site_name.localhost"
    local full_hostname="$site_name.localhost"
    local db_name="" db_created=false
    local admin_user="admin" admin_pass="" one_time_login_url=""
    local PLAK_WP_COMMAND=()

    if [ -e "$site_dir" ] || [ -L "$site_dir" ]; then
        echo "Error: site '$full_hostname' already exists." >&2
        exit 1
    fi
    if [ "$site_type" = wordpress ]; then
        source_config
        plak_wp_resolve_command || exit 1
        admin_pass=$(plak_site_random_password 12) || exit 1
        [ -n "$admin_pass" ] || { echo "Error: could not generate an admin password." >&2; exit 1; }
        # Preserve the established database naming convention, including its
        # trailing underscore, but never reuse an existing database.
        db_name=$(echo "plak_site_$site_name" | tr -c '[:alnum:]_' '_')
        if [ "${#db_name}" -gt 64 ]; then
            echo "Error: site name is too long for its WordPress database name." >&2
            exit 1
        fi
    fi

    mkdir -p "$SITES_DIR" || exit 1
    # mkdir without -p claims this directory exclusively, including races.
    mkdir "$site_dir" || exit 1
    trap 'plak_site_add_cleanup "$?" "$site_dir" "$db_name" "$db_created"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    mkdir "$site_dir/public" "$site_dir/logs" || exit 1
    echo "➕ Creating $site_type site: $full_hostname"

    if [ "$site_type" = plain ]; then
        write_plain_site_landing "$site_dir/public" || exit 1
    else
        echo "🗄️ Creating database: $db_name"
        if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
            -e "CREATE DATABASE \`$db_name\`;"; then
            echo "Error: could not create database '$db_name'; an existing database is never reused or deleted." >&2
            exit 1
        fi
        db_created=true
        echo "Installing WordPress..."

        # Filter known vendor deprecations only for provisioning. plak wp
        # itself passes stderr through unchanged. Explicit checks preserve
        # each failure instead of returning only the last command's status.
        if ! (
            cd "$site_dir/public" || exit 1
            "${PLAK_WP_COMMAND[@]}" core download --version="$wp_version" --quiet || {
                echo "Error: WordPress '$wp_version' download failed; verify the release exists and network access is available." >&2
                exit 1
            }
            if [ ! -s wp-includes/version.php ] || [ ! -s wp-settings.php ]; then
                echo "Error: WP-CLI reported a download but WordPress core files are missing." >&2
                exit 1
            fi
            "${PLAK_WP_COMMAND[@]}" config create --dbname="$db_name" --dbuser="$DB_USER" --dbpass="$DB_PASSWORD" --dbhost="${DB_HOST}:${DB_PORT}" --extra-php <<'PHP' || exit 1
define( 'WP_ENVIRONMENT_TYPE', 'local' );
define( 'WP_DEBUG', true );
define( 'WP_DEBUG_LOG', true );
define( 'WP_DEBUG_DISPLAY', false );
PHP
            [ -s wp-config.php ] || { echo "Error: WP-CLI did not create wp-config.php." >&2; exit 1; }
            "${PLAK_WP_COMMAND[@]}" core install --url="$(url_for "$full_hostname")" --title="Welcome to $site_name" --admin_user="$admin_user" --admin_password="$admin_pass" --admin_email="admin@$full_hostname" --skip-email || exit 1
            "${PLAK_WP_COMMAND[@]}" core is-installed --skip-plugins --skip-themes || exit 1
            if [ -n "$multisite" ]; then
                local network_flags=()
                [ "$multisite" != subdomains ] || network_flags+=(--subdomains)
                "${PLAK_WP_COMMAND[@]}" core multisite-convert "${network_flags[@]}" || exit 1
                printf '%s\n' "$multisite" > "$site_dir/.multisite-mode" || exit 1
            fi
            echo "   - Deleting default plugins (Hello Dolly, Akismet)..."
            "${PLAK_WP_COMMAND[@]}" plugin delete hello akismet --quiet || exit 1
        ) 2> >(grep -v -E '^(PHP )?Deprecated:' >&2); then
            echo "Error: WordPress installation failed; cleaning up the new site and database." >&2
            exit 1
        fi

        inject_mu_plugin "$site_dir/public" || exit 1
        one_time_login_url=$("${PLAK_WP_COMMAND[@]}" user login "$admin_user" --path="$site_dir/public/") || exit 1
        if [[ "$one_time_login_url" != https://* ]]; then
            echo "Error: WP-CLI did not return a one-time login URL." >&2
            exit 1
        fi
    fi

    # Provisioning is complete. A server reload failure keeps the valid site
    # for retry rather than dropping data after Caddy may have begun serving it.
    trap - EXIT INT TERM
    if [ "$no_reload_flag" = false ]; then
        if ! regenerate_caddyfile; then
            echo "Error: site '$full_hostname' was created, but server reload failed. Run 'plak reload' to retry." >&2
            exit 1
        fi
        local warm_url
        warm_url=$(url_for "$full_hostname")
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            if curl -ks --max-time 1 -o /dev/null "$warm_url/" 2>/dev/null; then
                break
            fi
            sleep 0.2
        done
    fi

    # The site is valid at this point, so a failed preparation is a retry, not
    # a cleanup: never drop a working site because an agent plugin or the
    # wp-mcp profile could not be finished.
    if [ "$agent_mode" = true ]; then
        if ! plak_agent_prepare "$site_name"; then
            echo "Error: site '$full_hostname' was created, but agent preparation did not finish. Retry with: plak agent $site_name" >&2
            exit 1
        fi
    fi

    echo "✅ Site '$full_hostname' created successfully!"
    if [ "$site_type" = wordpress ]; then
        local admin_url
        admin_url="$(url_for "$full_hostname")/wp-admin"
        gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "✅ WordPress Installed" "URL: $(plak_terminal_link "$admin_url")" "User: $admin_user" "Pass: $admin_pass" "One-time login URL: $(plak_terminal_link "$one_time_login_url")"
    fi
)

# Source: commands/site/agent
# Retry/repair entry point for the agent preparation done by `plak add --agent`.
# Idempotent: re-running installs/activates the plugins, rotates the scoped
# Application Password, refreshes the wp-mcp profile and re-verifies abilities.
plak_site_agent() {
    local site_name="" json_mode=false arg
    for arg in "$@"; do
        case "$arg" in
            --json) json_mode=true ;;
            --help|-h) plak_display_command_help agent; return 0 ;;
            -*) echo "Error: unknown option '$arg'." >&2; return 1 ;;
            *)
                if [ -n "$site_name" ]; then
                    echo "Error: unexpected argument '$arg'." >&2
                    return 1
                fi
                site_name="$arg"
                ;;
        esac
    done

    if ! plak_validate_site_name "$site_name"; then
        echo "Error: a site name is required." >&2
        plak_display_command_help agent >&2
        return 1
    fi

    if [ "$json_mode" = true ]; then
        # Keep the human progress on stderr so stdout stays a single envelope.
        if plak_agent_prepare "$site_name" >&2; then
            printf '{"success":true,"site":"%s","profile":"%s","url":"%s"}\n' \
                "$site_name" "$site_name" "$(url_for "$site_name.localhost")"
        else
            printf '{"success":false,"site":"%s"}\n' "$site_name"
            return 1
        fi
    else
        plak_agent_prepare "$site_name"
    fi
}

# Source: commands/site/clone
plak_site_clone_usage() {
    cat <<'HELP'
Usage:
  plak clone <source> <destination> [--yes] [--no-reload]

Duplicate a local site into an independent copy for testing changes. Works with
WordPress and static sites. Files and database are copied independently; URLs and
serialized content are rewritten to the destination. Exclusive domains and remote
bindings are not carried over, so the copy never deploys to the source's remote.
HELP
}

# Remove resources created by a failed clone. Only the destination directory and
# database (when this invocation created them) are touched; the source is never
# modified.
plak_site_clone_cleanup() {
    trap - EXIT
    local site_dir="${1:-}" db_name="${2:-}" db_created="${3:-false}"
    [ -n "$site_dir" ] || return 0
    if [ "$db_created" = true ]; then
        if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
            -e "DROP DATABASE IF EXISTS \`$db_name\`;"; then
            echo "Error: could not remove the cloned database '$db_name'; remove it manually." >&2
        fi
    fi
    if ! rm -rf -- "$site_dir"; then
        echo "Error: could not remove the cloned directory '$site_dir'." >&2
    fi
}

# Resolve the source database name from its real configuration rather than a
# naming convention, so custom DB names and SQLite-style configs are handled.
plak_clone_source_db_name() {
    local public_dir="$1" wp_cmd="$2"
    (cd "$public_dir" && "$wp_cmd" config get DB_NAME --skip-plugins --skip-themes 2>/dev/null)
}

plak_site_clone() {
    local source="" destination="" yes=0 no_reload=false arg
    for arg in "$@"; do
        case "$arg" in
            --yes|-y) yes=1 ;;
            --no-reload) no_reload=true ;;
            --help|-h) plak_site_clone_usage; return 0 ;;
            -*) echo "Error: unknown option '$arg'." >&2; return 1 ;;
            *)
                if [ -z "$source" ]; then
                    source="$arg"
                elif [ -z "$destination" ]; then
                    destination="$arg"
                else
                    echo "Error: unexpected argument '$arg'." >&2
                    return 1
                fi
                ;;
        esac
    done

    if [ -z "$source" ] || [ -z "$destination" ]; then
        plak_site_clone_usage >&2
        return 1
    fi
    if ! plak_validate_site_name "$source" || ! plak_validate_site_name "$destination"; then
        echo "Error: invalid source or destination site name." >&2
        return 1
    fi
    if [ "$source" = "$destination" ]; then
        echo "Error: source and destination must differ." >&2
        return 1
    fi

    local source_dir="$SITES_DIR/$source.localhost"
    local dest_dir="$SITES_DIR/$destination.localhost"
    local full_hostname="$destination.localhost"

    if [ ! -d "$source_dir" ]; then
        echo "Error: source site '$source.localhost' not found." >&2
        return 1
    fi
    if [ -e "$dest_dir" ]; then
        echo "Error: destination '$full_hostname' already exists." >&2
        return 1
    fi

    local is_wordpress=false
    [ -f "$source_dir/public/wp-config.php" ] && is_wordpress=true

    if [ "$yes" -eq 0 ] && [ -t 0 ] && plak_command_exists gum; then
        if ! gum confirm "Clone '$source.localhost' into '$full_hostname'?"; then
            echo "Clone cancelled."
            return 0
        fi
    fi

    source_config
    local wp_cmd=""
    if [ "$is_wordpress" = true ]; then
        wp_cmd=$(get_wp_cmd) || return 1
    fi
    local network_mode=single
    if [ "$is_wordpress" = true ]; then
        network_mode=$(plak_multisite_mode "$source_dir/public") || return 1
        if [ "$network_mode" != single ]; then
            plak_multisite_validate_local "$source_dir/public" "$source" || return 1
            local source_host source_user source_pass
            source_host=$(plak_multisite_wp "$source_dir/public" config get DB_HOST) || return 1
            source_user=$(plak_multisite_wp "$source_dir/public" config get DB_USER) || return 1
            source_pass=$(plak_multisite_wp "$source_dir/public" config get DB_PASSWORD) || return 1
            if [ "$source_host" != "$DB_HOST:$DB_PORT" ] && { [ "$source_host" != "$DB_HOST" ] || [ "$DB_PORT" != 3306 ]; }; then
                plak_ui_error 'Network cloning currently requires the configured local Plak database server.'; return 1
            fi
            if [ "$source_user" != "$DB_USER" ] || [ "$source_pass" != "$DB_PASSWORD" ]; then
                plak_ui_error 'Network cloning currently requires the configured local Plak database credentials.'; return 1
            fi
        fi
    fi

    # mkdir without -p claims the destination exclusively, including races.
    mkdir -p "$SITES_DIR" || return 1
    if ! mkdir "$dest_dir"; then
        echo "Error: could not create '$dest_dir' (it may have appeared concurrently)." >&2
        return 1
    fi

    local dest_db="" source_db="" db_created=false
    # On failure, remove only what this invocation created and return non-zero
    # so callers (and the original site) are unaffected.
    trap 'plak_site_clone_cleanup "$dest_dir" "$dest_db" "$db_created"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    echo "➕ Cloning '$source.localhost' to '$full_hostname'..."

    # --- Files: copy-on-write clone when available, portable copy otherwise ---
    if cp -Rc "$source_dir/." "$dest_dir/" 2>/dev/null; then
        echo "   - Files copied (copy-on-write)."
    elif cp -R "$source_dir/." "$dest_dir/"; then
        echo "   - Files copied."
    else
        echo "Error: failed to copy site files." >&2
        plak_site_clone_cleanup "$dest_dir" "$dest_db" "$db_created"
        return 1
    fi

    if [ "$is_wordpress" = true ]; then
        source_db=$(plak_clone_source_db_name "$source_dir/public" "$wp_cmd")
        if [ -z "$source_db" ]; then
            echo "Error: could not read the source database configuration." >&2
            plak_site_clone_cleanup "$dest_dir" "$dest_db" "$db_created"
            return 1
        fi

        dest_db=$(echo "plak_site_$destination" | tr -c '[:alnum:]_' '_')
        if [ "${#dest_db}" -gt 64 ]; then
            echo "Error: destination name is too long for its database." >&2
            plak_site_clone_cleanup "$dest_dir" "$dest_db" "$db_created"
            return 1
        fi
        echo "   - Creating database: $dest_db"
        if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
            -e "CREATE DATABASE \`$dest_db\`;"; then
            echo "Error: could not create the destination database." >&2
            plak_site_clone_cleanup "$dest_dir" "$dest_db" "$db_created"
            return 1
        fi
        db_created=true

        local dump
        dump=$(mktemp) || { plak_site_clone_cleanup "$dest_dir" "$dest_db" "$db_created"; return 1; }
        if ! mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" \
            --single-transaction --quick --lock-tables=false "$source_db" > "$dump"; then
            rm -f "$dump"
            echo "Error: could not dump the source database '$source_db'." >&2
            plak_site_clone_cleanup "$dest_dir" "$dest_db" "$db_created"
            return 1
        fi
        if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$dest_db" < "$dump"; then
            rm -f "$dump"
            echo "Error: could not import into the destination database." >&2
            plak_site_clone_cleanup "$dest_dir" "$dest_db" "$db_created"
            return 1
        fi
        rm -f "$dump"

        echo "   - Updating configuration and URLs..."
        if ! (cd "$dest_dir/public" && "$wp_cmd" config set DB_NAME "$dest_db" --skip-plugins --skip-themes --quiet); then
            plak_site_clone_cleanup "$dest_dir" "$dest_db" "$db_created"
            return 1
        fi

        if [ "$network_mode" != single ]; then
            if ! plak_multisite_rewrite "$dest_dir/public" "$source" "$destination"; then
                plak_site_clone_cleanup "$dest_dir" "$dest_db" "$db_created"
                return 1
            fi
            printf '%s\n' "$network_mode" > "$dest_dir/.multisite-mode" || return 1
        else
            rm -f "$dest_dir/.multisite-mode"
            # Preserve distinct home/siteurl values and local ports: read them from
            # the copied database, then map the source hostname to the destination.
            local source_home source_siteurl dest_home dest_siteurl
            source_home=$( (cd "$dest_dir/public" && "$wp_cmd" option get home --skip-plugins --skip-themes 2>/dev/null) )
            source_siteurl=$( (cd "$dest_dir/public" && "$wp_cmd" option get siteurl --skip-plugins --skip-themes 2>/dev/null) )
            dest_home=$(printf '%s' "$source_home" | sed "s|$source\.localhost|$destination.localhost|g")
            dest_siteurl=$(printf '%s' "$source_siteurl" | sed "s|$source\.localhost|$destination.localhost|g")
            [ -n "$dest_home" ] || dest_home=$(url_for "$full_hostname")
            [ -n "$dest_siteurl" ] || dest_siteurl=$(url_for "$full_hostname")

            if ! (cd "$dest_dir/public" && "$wp_cmd" search-replace "$source_siteurl" "$dest_siteurl" --all-tables --report-changed-only --skip-plugins --skip-themes &&
                  "$wp_cmd" search-replace "$source_home" "$dest_home" --all-tables --report-changed-only --skip-plugins --skip-themes &&
                  "$wp_cmd" option update home "$dest_home" --skip-plugins --skip-themes &&
                  "$wp_cmd" option update siteurl "$dest_siteurl" --skip-plugins --skip-themes); then
                echo "Error: failed to rewrite the cloned site URLs." >&2
                plak_site_clone_cleanup "$dest_dir" "$dest_db" "$db_created"
                return 1
            fi
        fi
    fi
    # --- Independent state: no remote binding, no exclusive domains, empty logs ---
    # A cloned mappings file would repoint the source's exclusive domains at the
    # copy and collide, so it is intentionally dropped.
    rm -f "$dest_dir/.remote" "$dest_dir/mappings"
    rm -rf "$dest_dir/logs"
    mkdir -p "$dest_dir/logs"

    # --- Copy relevant custom Caddy directives (not exclusive domains) ---
    local source_directive="$CUSTOM_CADDY_DIR/$source.localhost"
    if [ -f "$source_directive" ]; then
        # Rewrite the source hostname so a cloned directive does not answer for
        # or proxy to the original site.
        sed "s|$source\.localhost|$destination.localhost|g" "$source_directive" > "$CUSTOM_CADDY_DIR/$destination.localhost"
        echo "   - Custom directives copied."
    fi

    # Provisioning is complete; a reload failure keeps the valid clone.
    trap - EXIT INT TERM

    if [ "$no_reload" = false ]; then
        if ! regenerate_caddyfile; then
            echo "Error: clone '$full_hostname' was created, but server reload failed. Run 'plak reload' to retry." >&2
            return 1
        fi
    fi

    # A clone of an agent-ready site should stay agent-ready; prepare when
    # possible and otherwise say how, without failing the clone.
    if [ "$is_wordpress" = true ] && [ "$network_mode" = single ]; then
        plak_agent_maybe_prepare "$destination"
    fi

    echo "✅ Site '$full_hostname' cloned successfully!"
    gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 \
        "✅ Clone created" "URL: $(plak_terminal_link "$(url_for "$full_hostname")")"
}

# Source: commands/site/core
# shellcheck disable=SC2030,SC2031 # Per-site child subshells inherit the resolved argv array from plak_core.
# Compare numeric releases without sort -V (not available in macOS sort).
plak_core_version_compare() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        split(a,x,"."); split(b,y,".");
        for(i=1;i<=3;i++) {if(x[i]+0>y[i]+0){print 1;exit} if(x[i]+0<y[i]+0){print -1;exit}}
        print 0
    }'
}

# Bounded remote query; failures are explicit and do not prevent local inspection.
plak_core_latest() {
    local response version
    response=$(curl --connect-timeout 3 --max-time 10 -fsS 'https://api.wordpress.org/core/version-check/1.7/' 2>/dev/null) || return 1
    # shellcheck disable=SC2016 # PHP code, not shell variable expansion.
    version=$(printf '%s' "$response" | "$CADDY_CMD" php-cli -r '
        $data=json_decode(stream_get_contents(STDIN),true);
        foreach (($data["offers"] ?? []) as $offer) {
            if (($offer["response"] ?? "") === "upgrade") {echo $offer["version"]; exit;}
        }
        exit(1);
    ' 2>/dev/null) || return 1
    plak_core_version_valid "$version" && [[ "$version" != latest && "$version" != nightly ]] || return 1
    printf '%s\n' "$version"
}

plak_core_usage() {
    echo 'Usage: plak core [list|<site>] [--check]'
    echo '       plak core update <site>|--all [--version latest|nightly|<version>] [--allow-downgrade]'
}

plak_core() (
    local action=show site="" all=false check=false target=latest allow=false arg latest="" result=0 path
    case "${1:-}" in
        -h|--help) plak_core_usage; return 0 ;;
        update) action=update; shift ;;
        list) all=true; shift ;;
    esac
    while [ "$#" -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --all) all=true ;;
            --check) check=true ;;
            --allow-downgrade) allow=true ;;
            --version)
                [ "$#" -ge 2 ] || { plak_ui_error '--version requires a value.'; return 1; }
                target="$2"; shift ;;
            -*) plak_ui_error "Unknown option: $arg"; return 1 ;;
            *) [ -z "$site" ] || { plak_core_usage >&2; return 1; }; site="${arg%.localhost}" ;;
        esac
        shift
    done
    if [ -n "$site" ] && [ "$all" = true ]; then
        plak_ui_error 'Choose one site or --all, not both.'; return 1
    fi
    if [ "$action" = update ] && [ -z "$site" ] && [ "$all" = false ]; then
        plak_ui_error 'Updating requires a site or explicit --all.'; return 1
    fi
    plak_core_version_valid "$target" || { plak_ui_error "Invalid version '$target': use latest, nightly or a release number."; return 1; }
    local -a sites=() PLAK_WP_COMMAND=()
    if [ -n "$site" ]; then
        plak_validate_site_name "$site" || { plak_ui_error 'Invalid site name.'; return 1; }
        sites+=("$site")
    else
        for path in "$SITES_DIR"/*.localhost/public/wp-includes/version.php; do
            [ -f "$path" ] || continue
            path=${path%/public/wp-includes/version.php}; sites+=("$(basename "$path" .localhost)")
        done
    fi
    [ "${#sites[@]}" -gt 0 ] || { echo 'No WordPress sites found.'; return 0; }
    plak_wp_resolve_command || return 1
    if [ "$check" = true ] || { [ "$action" = update ] && [ "$target" = latest ]; }; then
        latest=$(plak_core_latest) || latest=""
        if [ -z "$latest" ]; then
            echo 'WordPress.org status unknown: remote query unavailable (10-second timeout).' >&2
            if [ "$action" = update ] && [ "$target" = latest ]; then return 1; fi
        elif [ "$action" = update ] && [ "$target" = latest ]; then target="$latest"; fi
    fi
    echo "Affected WordPress sites (${#sites[@]}): ${sites[*]}"
    for site in "${sites[@]}"; do
        if ! plak_core_one "$site" "$action" "$target" "$allow" "$latest"; then
            echo "$site.localhost: FAILED" >&2
            result=1
        fi
    done
    return "$result"
)

plak_core_one() (
    local site="$1" action="$2" target="$3" allow="$4" latest="$5" installed effective force=false multisite="" status=unknown comparison
    local public="$SITES_DIR/$site.localhost/public"
    if [ ! -f "$public/wp-config.php" ] || [ ! -f "$public/wp-includes/version.php" ]; then
        plak_ui_error "WordPress site '$site.localhost' not found or incomplete."; return 1
    fi
    cd "$public" || return 1
    installed=$("${PLAK_WP_COMMAND[@]}" core version) || return 1
    [ -n "$installed" ] || { plak_ui_error 'Installed version unavailable.'; return 1; }
    if [ -n "$latest" ]; then
        comparison=$(plak_core_version_compare "$installed" "$latest")
        case "$comparison" in -1) status="update available ($latest)" ;; 0) status="current ($latest)" ;; 1) status="ahead of published $latest" ;; esac
    fi
    echo "$site.localhost: installed=$installed; published=$status"
    [ "$action" = update ] || return 0
    if [ "$target" = nightly ] || ! [[ "$installed" =~ ^[1-9][0-9]*\.[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$site.localhost: development build transition ($installed -> $target); direction may be unknown."
        [ "$allow" = true ] || { plak_ui_error 'Use --allow-downgrade to explicitly authorize this transition.'; return 1; }
        force=true
    elif [ "$(plak_core_version_compare "$target" "$installed")" = -1 ]; then
        echo "$site.localhost: DOWNGRADE $installed -> $target"
        [ "$allow" = true ] || { plak_ui_error 'Downgrade requires --allow-downgrade; snapshot first.'; return 1; }
        force=true
    fi
    local -a flags=("--version=$target")
    [ "$force" = false ] || flags+=(--force)
    echo "$site.localhost: updating core to $target (wp-content and wp-config.php retained)."
    "${PLAK_WP_COMMAND[@]}" core update "${flags[@]}" || return 1
    multisite=$("${PLAK_WP_COMMAND[@]}" eval 'echo is_multisite() ? "1" : "0";' --skip-plugins --skip-themes) || return 1
    [[ "$multisite" = 0 || "$multisite" = 1 ]] || { plak_ui_error 'Could not determine single-site/network schema mode.'; return 1; }
    flags=()
    [[ "$multisite" != 1 && "$multisite" != true ]] || flags+=(--network)
    "${PLAK_WP_COMMAND[@]}" core update-db "${flags[@]}" || return 1
    effective=$("${PLAK_WP_COMMAND[@]}" core version) || return 1
    [ -n "$effective" ] || { plak_ui_error 'Effective version unavailable after update.'; return 1; }
    echo "$site.localhost: effective=$effective"
    if [ "$target" != nightly ] && { ! [[ "$effective" =~ ^[1-9][0-9]*\.[0-9]+(\.[0-9]+)?$ ]] || [ "$(plak_core_version_compare "$target" "$effective")" != 0 ]; }; then
        plak_ui_error "Effective version '$effective' does not match requested '$target'."; return 1
    fi
)

# Source: commands/site/db
plak_site_db_backup() {
    echo "🚀 Starting database backup for all WordPress sites..."

    if [ ! -d "$SITES_DIR" ] || [ -z "$(ls -A "$SITES_DIR")" ]; then
        gum style --foreground yellow "ℹ️ No sites found to back up."
        exit 0
    fi

    local dump_command
    if command -v mariadb-dump &> /dev/null; then
        dump_command="mariadb-dump"
    elif command -v mysqldump &> /dev/null; then
        dump_command="mysqldump"
    else
        gum style --foreground red "❌ Error: Neither mariadb-dump nor mysqldump could be found. Please install MariaDB or MySQL."
        return 1
    fi
    echo "ℹ️ Using '$dump_command' for backups."

    local overall_success=true
    for site_path in "$SITES_DIR"/*; do
        if [ -d "$site_path" ] && [ -f "$site_path/public/wp-config.php" ]; then
            local site_name
            site_name=$(basename "$site_path")
            echo "-----------------------------------------------------"
            echo "➡️ Backing up site: $site_name"

            local public_dir="$site_path/public"
            local private_dir="$site_path/private"
            mkdir -p "$private_dir"

            # Use a subshell to avoid manual cd back and forth
            (
                cd "$public_dir" || return 1
                
                # Get WP-CLI command (adds --allow-root if running as root)
                local wp_cmd
                wp_cmd=$(get_wp_cmd)
                
                # Check if wp-cli can connect
                if ! $wp_cmd core is-installed --skip-plugins --skip-themes &> /dev/null; then
                    echo "   ❌ Error: wp-cli cannot connect to the database for this site. Skipping."
                    return 1 # This exits the subshell, not the main script
                fi

                local db_name db_user db_pass db_host db_port
                db_name=$($wp_cmd config get DB_NAME --skip-plugins --skip-themes)
                db_user=$($wp_cmd config get DB_USER --skip-plugins --skip-themes)
                db_pass=$($wp_cmd config get DB_PASSWORD --skip-plugins --skip-themes)
                db_host=$($wp_cmd config get DB_HOST --skip-plugins --skip-themes 2>/dev/null || echo "127.0.0.1")
                db_port="3306"
                if [[ "$db_host" == *:* ]]; then
                    db_port="${db_host##*:}"
                    db_host="${db_host%:*}"
                fi

                if [ -z "$db_name" ] || [ -z "$db_user" ]; then
                    echo "   ❌ Error: Could not retrieve database credentials from wp-config.php. Skipping."
                    return 1
                fi
                
                local backup_timestamp
                backup_timestamp=$(date +%Y%m%d-%H%M%S)
                local backup_file="../private/database-backup-${backup_timestamp}.sql"
                echo "   Saving backup to: $(basename "$site_path")/private/$(basename "$backup_file")"

                # Execute the dump command
                if ! "${dump_command}" -h"${db_host}" -P"${db_port}" -u"${db_user}" -p"${db_pass}" --max_allowed_packet=512M --default-character-set=utf8mb4 --add-drop-table --single-transaction --quick --lock-tables=false "${db_name}" > "${backup_file}"; then
                    echo "   ❌ Error: Database dump failed for '${db_name}'."
                    rm -f "${backup_file}" # Clean up failed backup file
                    return 1
                fi
                
                chmod 600 "$backup_file"
                echo "   ✅ Backup successful."
            )
            
            # Check the exit code of the subshell
            if [ $? -ne 0 ]; then
                overall_success=false
            fi
        fi
    done
    
    echo "-----------------------------------------------------"
    if $overall_success; then
        gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "🎉 All WordPress database backups completed successfully!"
    else
        gum style --foreground red "⚠️ Some database backups failed. Please review the output above."
    fi
}
plak_site_db_list() {
    source_config # To get DB_USER and DB_PASSWORD for mysql command

    local json_mode=false
    for arg in "$@"; do
        case "$arg" in
            --json) json_mode=true ;;
            -h|--help)
                echo "Usage: plak db list [--json]"
                exit 0
                ;;
        esac
    done

    if [ "$json_mode" = false ]; then
        echo "🔎 Gathering database information for all WordPress sites..."
    fi

    if ! command -v wp &> /dev/null; then
        gum style --foreground red "❌ wp-cli is not installed or not in your PATH. Please run 'plak install'."
        exit 1
    fi

    if [ ! -d "$SITES_DIR" ] || [ -z "$(ls -A "$SITES_DIR" 2>/dev/null)" ]; then
        if [ "$json_mode" = true ]; then
            echo "[]"
        else
            gum style --padding "1 2" "ℹ️ No sites found."
        fi
        exit 0
    fi

    # Determine if we need --allow-root for wp-cli (running as root in WSL/Docker)
    local wp_root_flag=""
    if [ "$(id -u)" -eq 0 ]; then
        wp_root_flag="--allow-root"
    fi

    # This heredoc contains a PHP script to find, connect, and format the database list.
    # We invoke it via frankenphp php-cli -r so we don't depend on a standalone php binary.
    local wp_path
    wp_path=$(plak_wp_resolve_phar) || return 1
    local frank
    frank=$(command -v frankenphp) || return 1
    local php_output
    php_output=$(DB_USER="$DB_USER" DB_PASSWORD="$DB_PASSWORD" DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" SITES_DIR="$SITES_DIR" JSON_MODE="$json_mode" WP_ROOT_FLAG="$wp_root_flag" WP_PATH="$wp_path" FRANK_BIN="$frank" frankenphp php-cli -r '
        function formatSize(int $bytes): string {
            if ($bytes === 0) return "0 B";
            $units = ["B", "KB", "MB", "GB", "TB"];
            $i = floor(log($bytes, 1024));
            return round($bytes / (1024 ** $i), 2) . " " . $units[$i];
        }

        $sites_dir = getenv("SITES_DIR");
        $db_user = getenv("DB_USER");
        $db_pass = getenv("DB_PASSWORD");
        $db_host = getenv("DB_HOST") ?: "127.0.0.1";
        $db_port = getenv("DB_PORT") ?: "3306";
        $wp_root_flag = getenv("WP_ROOT_FLAG");
        $wp_path = getenv("WP_PATH");
        $frank_bin = getenv("FRANK_BIN");
        $json_mode = getenv("JSON_MODE") === "true";
        if (!is_dir($sites_dir)) {
            if ($json_mode) echo "[]\n";
            exit;
        }

        function wpConfig(string $key, string $public): string {
            global $frank_bin, $wp_path, $wp_root_flag;
            $args = [$frank_bin, "php-cli", $wp_path];
            if ($wp_root_flag) $args[] = $wp_root_flag;
            array_push($args, "config", "get", $key, "--skip-plugins", "--skip-themes", "--quiet");
            $pipes = [];
            $proc = proc_open($args, [0 => ["pipe", "r"], 1 => ["pipe", "w"], 2 => ["pipe", "w"]], $pipes, $public);
            if (!is_resource($proc)) throw new RuntimeException("Cannot execute WP-CLI for " . basename(dirname($public)));
            fclose($pipes[0]);
            $out = stream_get_contents($pipes[1]); fclose($pipes[1]);
            stream_get_contents($pipes[2]); fclose($pipes[2]);
            if (proc_close($proc) !== 0) throw new RuntimeException("Cannot read $key for " . basename(dirname($public)));
            return trim($out);
        }
        try {

        $sites_info = [];
        foreach (scandir($sites_dir) as $item) {
            $public_dir = $sites_dir . "/" . $item . "/public";
            if (is_file($public_dir . "/wp-config.php")) {
                $site_name = str_replace(".localhost", "", $item);
                $site_db_name = wpConfig("DB_NAME", $public_dir);
                if ($site_db_name === "") throw new RuntimeException("Empty DB_NAME for $site_name");

                $site_db_user = "N/A";
                $site_db_pass = "N/A";
                $size_str = "N/A";

                if (!str_contains(strtolower($site_db_name), "sqlite")) {
                    if (!class_exists("mysqli")) throw new RuntimeException("mysqli is unavailable; reinstall FrankenPHP with MySQL support.");
                    $site_db_user = wpConfig("DB_USER", $public_dir);
                    $site_db_pass = wpConfig("DB_PASSWORD", $public_dir);
                    $site_db_host = wpConfig("DB_HOST", $public_dir);
                    $host = $site_db_host ?: $db_host; $port = (int)$db_port; $socket = null;
                    if (preg_match("/^\\[([^]]+)\\](?::([0-9]+))?(?::(.*))?$/", $host, $parts)) {
                        $host = $parts[1]; $port = empty($parts[2]) ? $port : (int)$parts[2]; $socket = $parts[3] ?? null;
                    } elseif (str_contains($host, ":")) {
                        $parts = explode(":", $host, 3); $host = $parts[0];
                        if (ctype_digit($parts[1])) { $port = (int)$parts[1]; $socket = $parts[2] ?? null; }
                        else $socket = $parts[1];
                    }
                    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
                    $db = mysqli_init();
                    $db->options(MYSQLI_OPT_CONNECT_TIMEOUT, 3);
                    try {
                        $db->real_connect($host, $site_db_user, $site_db_pass, null, $port, $socket);
                        $stmt = $db->prepare("SELECT COALESCE(SUM(data_length + index_length), 0) FROM information_schema.TABLES WHERE table_schema = ?");
                        $stmt->bind_param("s", $site_db_name); $stmt->execute();
                        $size_bytes = 0; $stmt->bind_result($size_bytes); $stmt->fetch();
                        $stmt->close(); $db->close();
                    } catch (Throwable $error) {
                        throw new RuntimeException("Database connection/query failed for $site_name ($host:$port), code " . $error->getCode());
                    }
                    $size_str = formatSize((int)$size_bytes);
                }

                $sites_info[] = [
                    "name" => $site_name,
                    "db_name" => $site_db_name,
                    "db_user" => $site_db_user,
                    "db_pass" => $site_db_pass,
                    "size" => $size_str,
                ];
            }
        }

        if (empty($sites_info)) {
            if ($json_mode) echo "[]\n";
            exit;
        }

        array_multisort(array_column($sites_info, "name"), SORT_ASC, $sites_info);

        if ($json_mode) {
            echo json_encode($sites_info, JSON_UNESCAPED_SLASHES) . "\n";
            exit;
        }

        $output = [];
        $w = ["name" => 20, "db_name" => 25, "db_user" => 20, "db_pass" => 25, "size" => 15];
        $header = str_pad("Name", $w["name"]) . " " . str_pad("DB Name", $w["db_name"]) . " " . str_pad("DB User", $w["db_user"]) . " " . str_pad("DB Pass", $w["db_pass"]) . " " . str_pad("Size", $w["size"]);
        $separator = str_repeat("-", $w["name"]) . " " . str_repeat("-", $w["db_name"]) . " " . str_repeat("-", $w["db_user"]) . " " . str_repeat("-", $w["db_pass"]) . " " . str_repeat("-", $w["size"]);
        $output[] = $header;
        $output[] = $separator;

        foreach ($sites_info as $site) {
            $row = str_pad($site["name"], $w["name"]) . " " . str_pad($site["db_name"], $w["db_name"]) . " " . str_pad($site["db_user"], $w["db_user"]) . " " . str_pad($site["db_pass"], $w["db_pass"]) . " " . str_pad($site["size"], $w["size"]);
            $output[] = $row;
        }
        echo implode("\n", $output);
        } catch (Throwable $error) {
            fwrite(STDERR, "Error: " . $error->getMessage() . "\n"); exit(1);
        }
    ') || return 1

    if [ -z "$php_output" ]; then
        if [ "$json_mode" = true ]; then
            echo "[]"
        else
            gum style --padding "1 2" "ℹ️ No WordPress sites with readable database configurations found."
        fi
    else
        if [ "$json_mode" = true ]; then
            echo "$php_output"
        else
            echo "$php_output" | gum style --border normal --margin "1" --padding "1 2" --border-foreground 212
        fi
    fi
}

# Source: commands/site/delete
plak_site_delete() {
    source_config
    local site_name="$1"
    for protected_name in $PROTECTED_NAMES; do
        if [ "$site_name" == "$protected_name" ]; then
            gum style --foreground red "❌ Error: '$site_name' is a reserved name and cannot be deleted."
            exit 1
        fi
    done

    local force_delete=false
    local no_reload=false
    for arg in "$@"; do
        case "$arg" in
            --force|--yes|-y) force_delete=true ;;
            --no-reload) no_reload=true ;;
        esac
    done
    # Non-interactive callers (dashboard shell_exec, scripted cleanup) have no
    # TTY; gum confirm aborts there. Auto-promote so the delete doesn't hang.
    [ -t 0 ] || force_delete=true

    local site_dir="$SITES_DIR/$site_name.localhost"
    if [ ! -d "$site_dir" ]; then
        echo "⚠️ Site '$site_name.localhost' not found."
        exit 1
    fi

    if ! $force_delete; then
        if ! gum confirm "🚨 Are you sure you want to delete '$site_name.localhost'? This will remove its files and potentially its database."; then
            echo "🚫 Deletion cancelled."
            exit 0
        fi
    fi

    # Collect hostnames to strip from /etc/hosts BEFORE we rm -rf the site dir
    local hosts_to_remove=("$site_name.localhost")
    if [ -f "$site_dir/mappings" ]; then
        while IFS= read -r mapping || [ -n "$mapping" ]; do
            if [ -n "$mapping" ]; then
                hosts_to_remove+=("$mapping")
            fi
        done < "$site_dir/mappings"
    fi

    echo "🔥 Deleting site: $site_name.localhost"
    if [ -f "$site_dir/public/wp-config.php" ]; then
        local db_name
        db_name=$(echo "plak_site_$site_name" | tr -c '[:alnum:]_' '_')
        echo "🗄️ Deleting database: $db_name"
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "DROP DATABASE IF EXISTS \`$db_name\`;"
    fi

    # Don't trust the bare rm — a pre-1.10 dashboard-created site would be
    # root-owned (sudo-started FrankenPHP), and a silent rm failure would
    # previously still report "removed" while leaving the dir on disk. Try
    # sudo -n as a fallback, then surface the failure to the caller.
    if ! rm -rf "$site_dir" 2>/dev/null; then
        if ! $SUDO_CMD -n rm -rf "$site_dir" 2>/dev/null; then
            gum style --foreground red "❌ Failed to delete '$site_dir' — permission denied."
            gum style --foreground yellow "   Run: sudo rm -rf '$site_dir'"
            exit 1
        fi
    fi
    echo "✅ Directory deleted."

    # --- Delete Custom Caddy Directives ---
    local custom_conf_file="$CUSTOM_CADDY_DIR/$site_name.localhost"
    if [ -f "$custom_conf_file" ]; then
        rm "$custom_conf_file"
        echo "⚙️ Custom directives deleted."
    fi

    # --- Clean /etc/hosts entries ---
    local entries_exist=false
    local host
    for host in "${hosts_to_remove[@]}"; do
        if grep -qE "^127\.0\.0\.1[[:space:]]+${host//./\\.}[[:space:]]*$" /etc/hosts 2>/dev/null; then
            entries_exist=true
            break
        fi
    done

    if $entries_exist; then
        echo "🧹 Removing /etc/hosts entries (requires sudo)..."
        local sed_args=()
        for host in "${hosts_to_remove[@]}"; do
            sed_args+=(-e "/^127\.0\.0\.1[[:space:]]+${host//./\\.}[[:space:]]*$/d")
        done
        # Use non-interactive sudo when we don't have a TTY (e.g., the dashboard's
        # PHP shell_exec). In that context an interactive sudo prompt can hang
        # the caller waiting for a password that will never arrive. From a real
        # terminal the flag is empty, so sudo prompts as normal.
        local sudo_flag=""
        [ -t 0 ] || sudo_flag="-n"
        if sudo $sudo_flag sed -i.bak -E "${sed_args[@]}" /etc/hosts 2>/dev/null; then
            sudo $sudo_flag rm -f /etc/hosts.bak 2>/dev/null
            echo "   - ✅ /etc/hosts cleaned."
        else
            gum style --foreground yellow "   - ⚠️ Skipped /etc/hosts cleanup (sudo unavailable from this context). Run 'plak reload' from a terminal to sync."
        fi
    fi

    # Regenerate the Caddyfile so Caddy stops holding log file handles for
    # this site. Without this, a later Caddy restart would re-create the
    # deleted directory skeleton from the stale Caddyfile entry. The
    # dashboard passes --no-reload because it batches one reload per
    # delete queue drain.
    if [ "$no_reload" = false ]; then
        regenerate_caddyfile &>/dev/null
    fi

    echo "✅ Site '$site_name.localhost' has been removed."
}

# Source: commands/site/directive
plak_site_directive_add_or_update() {
    local site_name="$1"
    if [ -z "$site_name" ]; then
        gum style --foreground red "❌ Error: Please provide a site name."
        echo "Usage: plak directive <add|update> <name>"
        exit 1
    fi
    
    local site_hostname="${site_name}.localhost"
    local site_dir="$SITES_DIR/$site_hostname"
    local custom_conf_file="$CUSTOM_CADDY_DIR/$site_hostname"

    if [ ! -d "$site_dir" ]; then
        gum style --foreground red "❌ Error: Site '$site_hostname' not found."
        exit 1
    fi

    local existing_rules=""
    if [ -f "$custom_conf_file" ]; then
        existing_rules=$(cat "$custom_conf_file")
    fi
    
    local custom_rules
    # If stdin is a terminal (interactive), use gum. Otherwise, read from pipe.
    if [ -t 0 ]; then
        if [ -f "$custom_conf_file" ]; then
            echo "📝 Editing custom Caddy directives for $site_hostname..."
        else
            echo "📝 Adding new custom Caddy directives for $site_hostname..."
        fi
        echo "   Press Ctrl+D to save and exit, Ctrl+C to cancel."
        custom_rules=$(gum write --value "$existing_rules" --placeholder "Enter custom Caddy directives here...")
    else
        echo "📝 Reading custom directives from stdin for $site_hostname..."
        custom_rules=$(cat) # Read from standard input
    fi

    if [ -n "$custom_rules" ]; then
        mkdir -p "$CUSTOM_CADDY_DIR"
        echo "$custom_rules" > "$custom_conf_file"
        echo "✅ Custom directives saved for $site_hostname."
        regenerate_caddyfile
    else
        echo "🚫 No input provided. Action cancelled."
    fi
}

# This new function handles deleting directives
plak_site_directive_delete() {
    local site_name=""
    local force_delete=false
    for arg in "$@"; do
        case "$arg" in
            --force|--yes|-y) force_delete=true ;;
            -*)
                gum style --foreground red "❌ Unknown option: $arg"
                echo "Usage: plak directive delete <name> [--force]"
                exit 1
                ;;
            *) [ -z "$site_name" ] && site_name="$arg" ;;
        esac
    done

    if [ -z "$site_name" ]; then
        gum style --foreground red "❌ Error: Please provide a site name."
        echo "Usage: plak directive delete <name> [--force]"
        exit 1
    fi

    local site_hostname="${site_name}.localhost"
    local custom_conf_file="$CUSTOM_CADDY_DIR/$site_hostname"

    # Non-interactive callers (dashboard shell_exec, CI) have no TTY — gum
    # confirm aborts there. Auto-promote to --force so scripted deletes work.
    [ -t 0 ] || force_delete=true

    if [ -f "$custom_conf_file" ]; then
        if ! $force_delete; then
            if ! gum confirm "🚨 Are you sure you want to delete the custom directives for '$site_hostname'?"; then
                echo "🚫 Deletion cancelled."
                return 0
            fi
        fi
        rm "$custom_conf_file"
        echo "✅ Custom directives deleted for $site_hostname."
        regenerate_caddyfile
    else
        echo "ℹ️ No custom directives found for $site_hostname."
    fi
}

plak_site_directive_list() {
    local json_mode=false
    for arg in "$@"; do
        case "$arg" in
            --json) json_mode=true ;;
            -h|--help)
                echo "Usage: plak directive list [--json]"
                exit 0
                ;;
        esac
    done

    if [ "$json_mode" = false ]; then
        echo "🔎 Listing all custom Caddy directives..."
    fi

    if [ ! -d "$CUSTOM_CADDY_DIR" ] || [ -z "$(ls -A "$CUSTOM_CADDY_DIR" 2>/dev/null)" ]; then
        if [ "$json_mode" = true ]; then
            echo "[]"
        else
            echo ""
            gum style --foreground "yellow" "ℹ️ No custom directives found for any sites."
        fi
        exit 0
    fi

    local entries=()
    local found_one=false
    for conf_file in $(find "$CUSTOM_CADDY_DIR" -type f | sort); do
        found_one=true
        local site_name
        site_name=$(basename "$conf_file")

        local content
        content=$(cat "$conf_file")

        if [ "$json_mode" = true ]; then
            # JSON-escape content for inline emission
            local escaped
            escaped=$(printf '%s' "$content" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null \
                || printf '%s' "$content" | awk 'BEGIN { ORS="\\n" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); print }' | awk '{ printf "%s", $0 }')
            entries+=("{\"site\":\"$site_name\",\"content\":$escaped}")
        else
            gum style --border normal --margin "1 0" --padding "1 2" --border-foreground 212 "📄 $site_name" "" "$content"
        fi
    done

    if [ "$json_mode" = true ]; then
        if [ "$found_one" = true ]; then
            printf '[\n'
            local first=1
            for e in "${entries[@]}"; do
                if [ $first -eq 0 ]; then printf ',\n'; fi
                printf '  %s' "$e"
                first=0
            done
            printf '\n]\n'
        else
            echo "[]"
        fi
    elif [ "$found_one" = false ]; then
        echo ""
        gum style --foreground "yellow" "ℹ️ No custom directives found for any sites."
    fi
}
# Source: commands/site/disable
plak_site_disable() {
    echo "🛑 Disabling Plak services..."
    
    echo "   - Stopping Caddy/FrankenPHP..."

    # Stop services on MacOS
    if [ "$OS" == "macos" ]; then
        launchctl unload "$PLAK_SITE_DIR/com.plak.caddy.plist" &>/dev/null
        "$CADDY_CMD" stop --config "$CADDYFILE_PATH" &>/dev/null 2>&1
        echo "   - Stopping MariaDB..."
        brew services stop mariadb &>/dev/null
        echo "   - Stopping Mailpit..."
        launchctl unload "$PLAK_SITE_DIR/com.plak.mailpit.plist" &>/dev/null
    fi

    # Stop services on Linux
    if [ "$OS" == "linux" ]; then
        # v1.10+: FrankenPHP runs as plak.service under systemd. Try that
        # first; fall back to frankenphp stop in case a user skipped
        # plak_site_enable since the upgrade and still has an ad-hoc instance.
        $SUDO_CMD systemctl stop plak.service &>/dev/null \
            || "$CADDY_CMD" stop --config "$CADDYFILE_PATH" &>/dev/null \
            || $SUDO_CMD -n "$CADDY_CMD" stop --config "$CADDYFILE_PATH" &>/dev/null \
            || true

        # Get the correct MariaDB service name
        local mariadb_service
        mariadb_service=$(get_mariadb_service_name)

        echo "   - Stopping MariaDB ($mariadb_service)..."
        $SUDO_CMD systemctl stop "$mariadb_service" &>/dev/null
        echo "   - Stopping Mailpit..."
        $SUDO_CMD systemctl stop mailpit &>/dev/null
    fi
    
    echo "✅ Services stopped."
}
# Source: commands/site/enable
plak_site_enable() {
    echo "🚀 Enabling Plak services..."

    # Ensure log directory exists
    mkdir -p "$LOGS_DIR"

    if [ "$OS" == "macos" ]; then
        echo "   - Starting MariaDB..."
        brew services start mariadb

        local plist_path="$PLAK_SITE_DIR/com.plak.mailpit.plist"
        local mailpit_bin
        mailpit_bin=$(command -v mailpit)

        # Stop and unload any existing service to ensure our custom one is used.
        launchctl unload "$plist_path" &>/dev/null
        brew services stop mailpit &>/dev/null

        echo "   - Generating custom Mailpit service file..."
        cat > "$plist_path" << EOM
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>KeepAlive</key>
        <true/>
        <key>Label</key>
        <string>com.plak.mailpit</string>
        <key>ProgramArguments</key>
        <array>
                <string>$mailpit_bin</string>
                <string>--database</string>
                <string>$PLAK_SITE_DIR/mailpit.db</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>StandardErrorPath</key>
        <string>$LOGS_DIR/mailpit.log</string>
        <key>StandardOutPath</key>
        <string>$LOGS_DIR/mailpit.log</string>
</dict>
</plist>
EOM
        # Load and start the new service.
        launchctl load "$plist_path"
        launchctl start com.plak.mailpit
    fi

    if [ "$OS" == "linux" ]; then
        # Get the correct MariaDB service name for this distro
        local mariadb_service
        mariadb_service=$(get_mariadb_service_name)

        echo "   - Starting MariaDB ($mariadb_service)..."
        $SUDO_CMD systemctl enable "$mariadb_service" &>/dev/null
        $SUDO_CMD systemctl restart "$mariadb_service"

        local service_path="/etc/systemd/system/mailpit.service"
        local mailpit_bin
        mailpit_bin=$(command -v mailpit)
        local current_user
        current_user=$(whoami)

        echo "   - Generating custom Mailpit service file..."
        # Write the unit file directly to its destination via sudo tee.
        # Previously we used mktemp + sudo mv, but on Fedora/SELinux mv
        # preserves the source file's user_tmp_t context from /tmp, and
        # systemd refuses to load units outside the systemd_unit_file_t
        # type. Writing fresh into /etc/systemd/system/ picks up that
        # directory's type-transition rule automatically.
        $SUDO_CMD tee "$service_path" >/dev/null << EOM
[Unit]
Description=Mailpit Service for Plak
After=network.target

[Service]
ExecStart=$mailpit_bin --database $PLAK_SITE_DIR/mailpit.db
Restart=always
User=$current_user

[Install]
WantedBy=multi-user.target
EOM
        $SUDO_CMD chmod 644 "$service_path"

        # --- FrankenPHP / Plak systemd unit ---
        # Mirrors the mailpit pattern so the stack survives a reboot. The
        # apt frankenphp.service was masked during plak install so there
        # is no name conflict; we use plak.service to keep the scope
        # clear ("this is Plak's managed FrankenPHP").
        local plak_site_service_path="/etc/systemd/system/plak.service"
        local frankenphp_bin
        frankenphp_bin=$(command -v "$CADDY_CMD")

        # Capture the invoking PATH so the service can resolve gum/wp/frankenphp
        # for the dashboard's shell_exec of plak. systemd's default PATH omits
        # Homebrew-on-Linux (/home/linuxbrew/.linuxbrew/bin), which is not a
        # standard location the script prelude can hardcode reliably.
        local service_path_value="$PATH"

        echo "   - Generating Plak FrankenPHP service file..."
        # Same sudo-tee pattern as the mailpit unit above; see the note
        # there for why mktemp + sudo mv doesn't survive SELinux.
        $SUDO_CMD tee "$plak_site_service_path" >/dev/null << EOM
[Unit]
Description=FrankenPHP for Plak
After=network.target mariadb.service
Wants=mariadb.service

[Service]
Type=simple
ExecStart=$frankenphp_bin run --config $CADDYFILE_PATH --pidfile $PLAK_SITE_DIR/caddy.pid
ExecReload=$frankenphp_bin reload --config $CADDYFILE_PATH --address localhost:2019
Restart=on-failure
RestartSec=2s
User=$current_user
Environment=HOME=/home/$current_user
Environment=PHPRC=$PHP_INI_FILE
Environment=PATH=$service_path_value

[Install]
WantedBy=multi-user.target
EOM
        $SUDO_CMD chmod 644 "$plak_site_service_path"

        # Reload systemd, then enable and start both Plak-managed services
        $SUDO_CMD systemctl daemon-reload
        $SUDO_CMD systemctl enable mailpit &>/dev/null
        $SUDO_CMD systemctl restart mailpit
        $SUDO_CMD systemctl enable plak.service &>/dev/null
        # Stop any ad-hoc frankenphp started by a pre-1.10 plak_site_enable so
        # systemctl can take ownership of the listening sockets cleanly.
        "$CADDY_CMD" stop --config "$CADDYFILE_PATH" &>/dev/null \
            || $SUDO_CMD -n "$CADDY_CMD" stop --config "$CADDYFILE_PATH" &>/dev/null \
            || true
        $SUDO_CMD systemctl restart plak.service
    fi

    # Skip the ad-hoc Caddy start on Linux — systemd handles it now.
    if [ "$OS" != "linux" ]; then
        start_caddy_service
    fi

    if [ $? -eq 0 ]; then
        echo ""
        gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 \
            "✅ Services are running" \
            "Dashboard: $(url_for plak.localhost)" \
            "Adminer:   $(url_for db.plak.localhost)" \
            "Mailpit:   $(url_for mail.plak.localhost)"

        if [ "$HTTPS_PORT" != "443" ]; then
            echo ""
            gum style --foreground yellow \
                "Port note: Plak HTTPS is configured on ${HTTPS_PORT}." \
                "Use $(url_for plak.localhost), not https://plak.localhost/."
        fi

        # Show WSL-specific info
        if [ "$IS_WSL" = true ]; then
            local wsl_ip
            wsl_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
            echo ""
            gum style --foreground yellow "WSL Note: To access sites from Windows browser, update Windows hosts file."
            echo ""
            echo "  Run this in PowerShell (as Administrator):"
            echo ""
            echo "  Add-Content -Path C:\\Windows\\System32\\drivers\\etc\\hosts -Value \"\`n$wsl_ip plak.localhost db.plak.localhost mail.plak.localhost\""
            echo ""
            echo "  Or manually add this line to C:\\Windows\\System32\\drivers\\etc\\hosts:"
            echo "  $wsl_ip plak.localhost db.plak.localhost mail.plak.localhost"
            echo ""
            echo "  Note: WSL IP may change on restart. Run 'plak wsl-hosts' to get updated commands."
        fi
    else
        gum style --foreground red "❌ Caddy server failed to start. Check $LOGS_DIR/caddy-process.log for errors."
    fi
}

# Source: commands/site/help
plak_site_display_command_help() {
    local cmd="$1"
    case "$cmd" in
        directive)
            cat <<'HELP'
Usage:
  plak directive <add|update|delete|list> [site]

Manage custom Caddyfile rules for local sites.
HELP
            ;;
        proxy)
            cat <<'HELP'
Usage:
  plak proxy <add|list|delete>

Manage standalone reverse proxy entries in the Caddyfile.
HELP
            ;;
        tailscale)
            cat <<'HELP'
Usage:
  plak tailscale <enable|disable|status>

Expose local sites to your Tailscale network.
HELP
            ;;
        mappings)
            echo "Usage: plak mappings <site> [add|remove] [domain] [--json]"
            ;;
        lan)
            echo "Usage: plak lan <enable|disable|status|trust> [site]"
            ;;
        ports)
            echo "Usage: plak ports [--http PORT] [--https PORT] [--skip-urls] [--dry-run]"
            ;;
        memory)
            echo "Usage: plak memory [set <value>] [--yes]"
            ;;
        log)
            echo "Usage: plak log [site] [-f|--follow]"
            ;;
        share)
            echo "Usage: plak share [<site>] [--print-url] [--no-install]"
            ;;
        snapshot)
            plak_site_snapshot_usage
            ;;
        import)
            plak_site_import_usage
            ;;
        clone)
            plak_site_clone_usage
            ;;
        pull)
            echo "Usage: plak pull [<site>] [--yes] [--proxy-uploads]"
            ;;
        push)
            echo "Usage: plak push [<site>] [--yes]"
            ;;
        reload)
            echo "Usage: plak reload"
            ;;
        trust)
            echo "Usage: plak trust"
            ;;
        url)
            echo "Usage: plak url <site>"
            ;;
        upgrade)
            echo "Usage: plak upgrade [--yes]"
            ;;
        *)
            plak_show_help
            ;;
    esac
}

# Source: commands/site/history
plak_history_usage() {
    cat <<'HELP'
Usage:
  plak history <site> save [--note <text>] [--background]
  plak history <site> list
  plak history <site> show <id> [<path>]
  plak history <site> diff <from> <to|current> [<path>]
  plak history <site> restore <id> <path> --yes [--background]
  plak history <site> recover --yes
  plak history <site> jobs
  plak history <site> schedule hourly|daily --enable
  plak history <site> schedule --disable

Paths are relative to wp-content: plugins/<slug>, themes/<slug>, or
mu-plugins/<file-or-directory>. Output is JSON. Files only: no database or
activation-state restoration. Symlinks and Git checkouts cannot be restored.
HELP
}

plak_history() {
    case "${1:-}" in ''|-h|--help) plak_history_usage; return 0 ;; esac
    local site="${1%.localhost}" site_dir
    shift
    # main appends the global --json switch; this command always emits JSON.
    if [ "${*: -1}" = --json ]; then set -- "${@:1:$#-1}"; fi
    site_dir=$(plak_snapshot_require_site "$site") || return 1
    [ -f "$site_dir/public/wp-config.php" ] || { plak_ui_error 'History requires a WordPress site.'; return 1; }
    if [ "${1:-}" = schedule ]; then
        shift
        plak_history_schedule "$site" "$@"
        return $?
    fi
    local wp_path frank root_flag="" args_json='[' separator="" arg
    wp_path=$(plak_wp_resolve_phar) || return 1
    frank=$(type -P frankenphp) || { plak_ui_error 'FrankenPHP is required.'; return 1; }
    [ "$(id -u)" -ne 0 ] || root_flag=--allow-root
    if [ "${*: -1}" = --background ]; then
        local action="${1:-}"
        [[ "$action" = save || "$action" = restore ]] || { plak_ui_error '--background is only supported by save/restore.'; return 1; }
        set -- "${@:1:$#-1}"
        plak_history_background "$site" "$site_dir" "$@"
        return $?
    fi
    # FrankenPHP's -r mode does not populate argv on every supported build.
    for arg in "$@"; do args_json+="$separator$(plak_json_string "$arg")"; separator=','; done
    args_json+=']'
    PLAK_HISTORY_SITE="$site_dir" PLAK_HISTORY_WP="$wp_path" PLAK_HISTORY_FRANK="$frank" PLAK_HISTORY_ROOT_FLAG="$root_flag" PLAK_HISTORY_ARGS="$args_json" \
        "$frank" php-cli -r "$(plak_history_program)"
}

plak_history_background() {
    local site="$1" site_dir="$2" jobs id job executable
    shift 2
    jobs="$site_dir/private/history/jobs"
    for job in "$site_dir/private" "$site_dir/private/history" "$jobs"; do
        [ ! -L "$job" ] || { plak_ui_error 'Linked history storage is unsupported.'; return 1; }
    done
    mkdir -p "$jobs" || return 1
    chmod 700 "$jobs" || return 1
    executable=$(command -v "${PLAK_SITE_CMD:-$0}") || return 1
    executable=$(plak_wp_realpath "$executable") || return 1
    job=$(mktemp -d "$jobs/job.XXXXXXXXXX") || return 1
    id=$(basename "$job")
    # argv stays separate, including notes and selections containing spaces.
    # shellcheck disable=SC2016 # Expanded by the detached bash, not this shell.
    nohup bash -c '
        job="$1"; shift
        trap '\''rc=$?; printf "%s\n" "$rc" > "$job/exit.tmp"; mv "$job/exit.tmp" "$job/exit"'\'' EXIT
        trap '\''exit 130'\'' INT
        trap '\''exit 143'\'' TERM
        printf "%s\n" "$$" > "$job/pid"
        "$@"
    ' plak-history-job "$job" "$executable" history "$site" "$@" > "$job/log" 2>&1 < /dev/null &
    printf '{"job":"%s","status":"queued"}\n' "$id"
}

plak_history_schedule() (
    local site="$1" expression="" executable quoted home_quoted crontab_file marker
    shift
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "$(id -un)" ]; then
        plak_ui_error 'Configure history scheduling without sudo, as the intended user.'; return 1
    fi
    case "$*" in
        'hourly --enable') expression='17 * * * *' ;;
        'daily --enable') expression='17 3 * * *' ;;
        '--disable') ;;
        *) plak_ui_error 'Usage: schedule hourly|daily --enable, or schedule --disable'; return 1 ;;
    esac
    command -v crontab >/dev/null 2>&1 || { plak_ui_error 'crontab is required for opt-in scheduling.'; return 1; }
    executable=$(command -v "${PLAK_SITE_CMD:-$0}") || return 1
    executable=$(plak_wp_realpath "$executable") || return 1
    # Cron treats percent and newline specially even inside shell quotes.
    case "$HOME$executable" in *%*|*$'\n'*|*$'\r'*) plak_ui_error 'Cron-unsafe HOME/executable path.'; return 1 ;; esac
    quoted="'${executable//\'/\'\\\'\'}'"
    home_quoted="'${HOME//\'/\'\\\'\'}'"
    crontab_file=$(mktemp) || return 1
    trap 'rm -f "$crontab_file" "$crontab_file.current" "$crontab_file.error"' EXIT
    if ! crontab -l > "$crontab_file.current" 2> "$crontab_file.error"; then
        if [ -s "$crontab_file.current" ] || ! grep -qi 'no crontab' "$crontab_file.error"; then
            cat "$crontab_file.error" >&2; return 1
        fi
    fi
    marker="# plak-history:$site"
    # Match only our exact trailing marker; unrelated user jobs are preserved.
    awk -v marker="$marker" 'substr($0,length($0)-length(marker)+1) != marker' "$crontab_file.current" > "$crontab_file"
    if [ -n "$expression" ]; then
        printf '%s HOME=%s %s history %s save --note scheduled %s\n' "$expression" "$home_quoted" "$quoted" "$site" "$marker" >> "$crontab_file"
    fi
    crontab "$crontab_file" || return 1
    if [ -n "$expression" ]; then echo "History schedule enabled for $site as $(id -un); cron mails errors/output to that user.";
    else echo "History schedule disabled for $site as $(id -un)."; fi
)

# Source: commands/site/import
plak_site_import_usage() {
    cat <<'HELP'
Usage:
  plak import <name> <backup.zip> [--plain] [--yes] [--no-reload]

Create a local site from a WordPress backup ZIP or TAR. Accepts Plak exports,
Local exports, and hosting backups that contain a single-site WordPress tree
with a recognisable SQL dump. Multisite backups are rejected.
HELP
}

# Inspect an archive without extracting it: report how deep the WordPress tree
# and the SQL dump live, and refuse ambiguous or escaping structures.
plak_import_inspect() {
    local archive="$1"
    local listing
    if ! listing=$(plak_import_list_archive "$archive"); then
        echo "Error: could not read archive '$archive'." >&2
        return 1
    fi
    if [ -z "$listing" ]; then
        echo "Error: archive '$archive' is empty." >&2
        return 1
    fi

    # Reject absolute paths and parent-directory escapes.
    if grep -Eq '(^/)|(^|/)\.\.(/|$)' <<<"$listing"; then
        echo "Error: archive contains paths that escape the extraction directory." >&2
        return 1
    fi

    local sql_entries wp_config_entries
    sql_entries=$(grep -Ei '\.sql(\.gz|\.bz2)?$' <<<"$listing" || true)
    local sql_count
    sql_count=$(grep -c . <<<"$sql_entries" || true)
    if [ "$sql_count" -eq 0 ]; then
        echo "Error: archive does not contain an SQL dump." >&2
        return 1
    fi
    if [ "$sql_count" -gt 1 ]; then
        echo "Error: archive contains multiple SQL dumps; refusing an ambiguous import." >&2
        return 1
    fi

    # Multisite is explicitly out of scope for this first delivery. A network
    # is recognisable by its per-site uploads tree or a MULTISITE wp-config.
    if grep -Eqi '(^|/)wp-content/uploads/sites(/|$)' <<<"$listing"; then
        echo "Error: multisite backups are not supported." >&2
        return 1
    fi

    wp_config_entries=$(grep -E '(^|/)wp-content(/|$)' <<<"$listing" || true)
    if [ -z "$wp_config_entries" ]; then
        echo "Error: archive does not contain a wp-content directory." >&2
        return 1
    fi

    printf '%s\n' "$sql_entries"
}

plak_import_list_archive() {
    local archive="$1"
    case "$archive" in
        *.zip) unzip -Z1 "$archive" 2>/dev/null ;;
        *.tar.gz|*.tgz) tar tzf "$archive" 2>/dev/null ;;
        *.tar) tar tf "$archive" 2>/dev/null ;;
        *)
            echo "Error: unsupported archive format for '$archive'. Use zip, tar.gz, tgz or tar." >&2
            return 1
            ;;
    esac
}

plak_import_extract() {
    local archive="$1" dest="$2"
    case "$archive" in
        *.zip) unzip -q -o "$archive" -d "$dest" -x "__MACOSX/*" ;;
        *.tar.gz|*.tgz) tar xzf "$archive" -C "$dest" ;;
        *.tar) tar xf "$archive" -C "$dest" ;;
    esac
}

# Import a backup as a new site: create an empty site, then let the Go
# migration engine populate files and database with the destination URL.
plak_site_import() {
    local site_name="" archive="" site_type="wordpress" yes=0 no_reload=false arg
    for arg in "$@"; do
        case "$arg" in
            --plain) site_type="plain" ;;
            --yes|-y) yes=1 ;;
            --no-reload) no_reload=true ;;
            --help|-h) plak_site_import_usage; return 0 ;;
            -*) echo "Error: unknown option '$arg'." >&2; return 1 ;;
            *)
                if [ -z "$site_name" ]; then
                    site_name="$arg"
                elif [ -z "$archive" ]; then
                    archive="$arg"
                else
                    echo "Error: unexpected argument '$arg'." >&2
                    return 1
                fi
                ;;
        esac
    done

    if [ -z "$site_name" ] || [ -z "$archive" ]; then
        plak_site_import_usage >&2
        return 1
    fi
    if ! plak_validate_site_name "$site_name"; then
        echo "Error: invalid site name '$site_name'." >&2
        return 1
    fi
    if [ ! -f "$archive" ]; then
        echo "Error: backup file '$archive' not found." >&2
        return 1
    fi
    if [ -e "$SITES_DIR/$site_name.localhost" ]; then
        echo "Error: site '$site_name.localhost' already exists; refusing to overwrite it." >&2
        return 1
    fi

    # Inspection validates the archive shape and exits early on ambiguity; the
    # engine performs the actual extraction and SQL import.
    plak_import_inspect "$archive" >/dev/null || return 1

    if [ "$yes" -eq 0 ] && [ -t 0 ] && plak_command_exists gum; then
        if ! gum confirm "Create '$site_name.localhost' from $(basename "$archive")?"; then
            echo "Import cancelled."
            return 0
        fi
    fi

    echo "Creating site '$site_name.localhost'..."
    "$PLAK_SITE_CMD" add "$site_name" --plain --no-reload || {
        echo "Error: could not create the destination site." >&2
        return 1
    }

    # Resolve the Go transfer engine and migrate the extracted archive into the
    # new site. go_migrate handles extraction, SQL import, URL rewriting and
    # table-prefix adjustment.
    local import_tmp
    import_tmp=$(mktemp -d "${TMPDIR:-/tmp}/plak-import-XXXXXXXX")
    local helper="$import_tmp/plak-go.sh"
    local local_home local_siteurl
    local_home=$(url_for "$site_name.localhost")
    local_siteurl="$local_home"

    local rc=0
    if ! plak_fetch_go_runtime "$helper"; then
        echo "Error: could not obtain the Plak engine." >&2
        rc=1
    else
        if ! (cd "$SITES_DIR/$site_name.localhost/public" && bash "$helper" migrate \
            --url="$archive" \
            --update-urls \
            --destination-home="$local_home" \
            --destination-siteurl="$local_siteurl"); then
            echo "Error: the import engine failed." >&2
            rc=1
        fi
    fi
    rm -rf "$import_tmp"

    if [ "$rc" -ne 0 ]; then
        echo "Error: import failed. The partially created site '$site_name.localhost' was kept for inspection." >&2
        echo "Remove it with: plak delete $site_name --yes --no-reload" >&2
        return 1
    fi

    # Reinstall the local helper plugin and referenced site configuration.
    if [ "$site_type" != plain ]; then
        inject_mu_plugin "$SITES_DIR/$site_name.localhost/public" || true
    fi

    if [ "$no_reload" = false ]; then
        regenerate_caddyfile || {
            echo "Error: site imported, but server reload failed. Run 'plak reload' to retry." >&2
            return 1
        }
    fi

    # An imported WordPress site should be usable by agents too; prepare it when
    # possible and otherwise say how, without failing the import.
    if [ "$site_type" != plain ]; then
        plak_agent_maybe_prepare "$site_name"
    fi

    echo "Site '$site_name.localhost' imported successfully."
    gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 \
        "✅ Imported" "URL: $(plak_terminal_link "$local_home")"
}

# Source: commands/site/install
# A robust function to check, validate, and install a given dependency.
install_dependency() {
    local cmd_name="$1"      # The command to check for (e.g., "gum")
    local brew_pkg="$2"      # The package name for Homebrew (e.g., "gum")
    local apt_pkg="$3"       # The package name for apt (Debian/Ubuntu)
    local dnf_pkg="$4"       # The package name for dnf (Fedora/RHEL) - can differ from apt
    local binary_url="$5"    # Optional URL to a binary/tarball for fallback

    # If dnf_pkg not specified, default to apt_pkg
    if [ -z "$dnf_pkg" ]; then
        dnf_pkg="$apt_pkg"
    fi

    # 1. Validate the command. If it runs, we're done.
    if command -v "$cmd_name" &>/dev/null; then
        # Special cases: mariadb doesn't support --version, and wp's shebang
        # uses /usr/bin/env php which won't resolve since Plak no longer
        # installs a standalone php (wp-cli is invoked through frankenphp
        # php-cli at runtime — see get_wp_cmd in main).
        if [[ "$cmd_name" == "mariadb" || "$cmd_name" == "wp" ]] || "$cmd_name" --version &>/dev/null 2>&1; then
            echo "✅ $cmd_name is already installed and valid."
            return 0
        fi
    fi

    # If gum isn't installed yet, we can't use it for styling this first message.
    if ! command -v gum &>/dev/null; then
        echo "--- Installing Dependency: $cmd_name ---"
    else
        gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "Installing Dependency: $cmd_name"
    fi

    local installed_successfully=false
    local pkg_name=""

    # 2. Attempt installation with the native package manager.
    if [ "$OS" == "macos" ]; then
        if brew install "$brew_pkg"; then
            installed_successfully=true
        fi
    else # For Linux (apt/dnf)
        # Determine the correct package name for this distro
        if [ "$PKG_MANAGER" == "apt" ]; then
            pkg_name="$apt_pkg"
        else
            pkg_name="$dnf_pkg"
        fi

        # Only try native package manager if a name is provided
        if [ -n "$pkg_name" ]; then
            echo "   - Updating package cache..."
            if [ "$PKG_MANAGER" == "apt" ]; then
                $SUDO_CMD apt-get update -qq >/dev/null 2>&1
            else
                $SUDO_CMD dnf makecache -q >/dev/null 2>&1 || true
            fi

            echo "   - Installing $pkg_name via $PKG_MANAGER..."
            if [ "$PKG_MANAGER" == "apt" ]; then
                if $SUDO_CMD apt-get install -y "$pkg_name" >/dev/null 2>&1; then
                    installed_successfully=true
                fi
            else
                if $SUDO_CMD dnf install -y "$pkg_name" >/dev/null 2>&1; then
                    installed_successfully=true
                fi
            fi
        fi

        # 3. If native package fails or isn't specified, and a binary URL is provided, try that.
        if [ "$installed_successfully" = false ] && [ -n "$binary_url" ]; then
            if ! command -v gum &>/dev/null; then
                 echo "   - Native package not available. Falling back to binary download."
            else
                gum style --foreground "yellow" "   - Native package not available. Falling back to binary download."
            fi

            local temp_dir
            temp_dir=$(mktemp -d)

            # Check if URL is a tarball or direct binary
            if [[ "$binary_url" == *.tar.gz ]] || [[ "$binary_url" == *.tgz ]]; then
                echo "   - Downloading and extracting tarball..."
                if curl -sL "$binary_url" | tar -xz -C "$temp_dir" 2>/dev/null; then
                    # Find the binary in extracted contents
                    local binary_file
                    binary_file=$(find "$temp_dir" -name "$cmd_name" -type f -executable 2>/dev/null | head -1)
                    if [ -z "$binary_file" ]; then
                        # Try without executable flag (might need chmod)
                        binary_file=$(find "$temp_dir" -name "$cmd_name" -type f 2>/dev/null | head -1)
                    fi
                    if [ -n "$binary_file" ]; then
                        chmod +x "$binary_file"
                        if $SUDO_CMD mv "$binary_file" "$BIN_DIR/$cmd_name"; then
                            installed_successfully=true
                        fi
                    fi
                fi
            else
                # Direct binary download
                echo "   - Downloading binary..."
                if curl -sL "$binary_url" -o "$temp_dir/$cmd_name"; then
                    chmod +x "$temp_dir/$cmd_name"
                    if $SUDO_CMD mv "$temp_dir/$cmd_name" "$BIN_DIR/$cmd_name"; then
                        installed_successfully=true
                    fi
                fi
            fi
            rm -rf "$temp_dir"
        fi
    fi

    # 4. Final verification and cache clearing.
    if [ "$installed_successfully" = true ]; then
        hash -r # Clear the shell's command cache for this script session.
        if command -v "$cmd_name" &>/dev/null; then
            echo "✅ $cmd_name installed successfully."
            return 0
        else
            echo "⚠️  $cmd_name installed but not found in PATH. You may need to restart your shell."
            return 0
        fi
    else
        if command -v gum &>/dev/null; then
            gum style --foreground red "❌ Failed to install $cmd_name."
        else
            echo "❌ Failed to install $cmd_name."
        fi
        exit 1
    fi
}

plak_site_install() {
    local auto_yes=false
    local url_migration_failed=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --yes|-y|--force)
                auto_yes=true
                shift
                ;;
            *)
                echo "❌ Unknown argument: $1" >&2
                echo "Usage: plak install [--yes]" >&2
                exit 1
                ;;
        esac
    done

    # Non-interactive callers (CI, installer piping, dashboards) have no TTY;
    # gum confirm / gum choose abort there. Auto-promote so the install doesn't
    # hang.
    [ -t 0 ] || auto_yes=true

    echo "🚀 Starting Plak installation..."

    # --- WSL/Systemd Check ---
    if [ "$OS" == "linux" ]; then
        if [ "$IS_WSL" = true ]; then
            echo "🐧 WSL environment detected."
            # Check if systemd is running
            if ! pidof systemd >/dev/null 2>&1; then
                echo ""
                echo "⚠️  WARNING: systemd is not running in WSL."
                echo "   Plak requires systemd for service management."
                echo ""
                echo "   To enable systemd in WSL2, add to /etc/wsl.conf:"
                echo "   [boot]"
                echo "   systemd=true"
                echo ""
                echo "   Then restart WSL with: wsl --shutdown"
                echo ""
                if $auto_yes; then
                    echo "   (--yes set — continuing anyway.)"
                else
                    read -p "Do you want to continue anyway? (y/N) " -n 1 -r
                    echo
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        echo "🚫 Installation cancelled."
                        exit 0
                    fi
                fi
            fi
        fi
    fi

    # --- Gum (required for the port-selection UI that follows) ---
    # Note: gum releases use format: gum_VERSION_Linux_x86_64.tar.gz
    local gum_arch="x86_64"
    if [ "$(uname -m)" == "aarch64" ] || [ "$(uname -m)" == "arm64" ]; then
        gum_arch="arm64"
    fi
    local gum_url="https://github.com/charmbracelet/gum/releases/download/v0.14.1/gum_0.14.1_Linux_${gum_arch}.tar.gz"
    install_dependency "gum" "gum" "gum" "gum" "$gum_url"

    # --- Port Selection ---
    # Two paths can run here:
    #   1. Reconfigure path — saved config already has non-default ports; the
    #      user gets a menu to keep, switch to defaults, or pick new values.
    #   2. Conflict path — the target ports (post-reconfigure) are occupied
    #      by a non-Plak process; the user gets the conflict menu.
    # On a fresh install with free 80/443, both paths are skipped silently.
    # If the chosen ports differ from the starting values, a DB URL update
    # step runs after install services come up (same code path as plak ports).
    local original_http="$HTTP_PORT"
    local original_https="$HTTPS_PORT"
    local port_choice_made=false

    # --- Reconfigure path ---
    if [ "$HTTP_PORT" != "80" ] || [ "$HTTPS_PORT" != "443" ]; then
        echo ""
        gum style --foreground "212" \
            "Plak is currently configured for custom ports: ${HTTP_PORT} / ${HTTPS_PORT}"
        echo ""

        local default_label="Switch to default ports (80 / 443)"
        if port_has_conflict 80 || port_has_conflict 443; then
            default_label="Switch to default ports (80 / 443) — currently in use"
        fi

        local choice
        if $auto_yes; then
            choice="Keep current ports (${HTTP_PORT} / ${HTTPS_PORT})"
        else
            choice=$(gum choose \
                "Keep current ports (${HTTP_PORT} / ${HTTPS_PORT})" \
                "$default_label" \
                "Pick different custom ports")
        fi

        case "$choice" in
            "Keep current"*)
                : # no change
                ;;
            "Switch to default"*)
                HTTP_PORT=80
                HTTPS_PORT=443
                ;;
            "Pick different"*)
                prompt_custom_ports "$(next_free_port 8090)" "$(next_free_port 8453)"
                ;;
        esac
        port_choice_made=true
    fi

    # --- Conflict path (for target ports post-reconfigure) ---
    local http_busy=false
    local https_busy=false
    port_has_conflict "$HTTP_PORT"  && http_busy=true
    port_has_conflict "$HTTPS_PORT" && https_busy=true

    if $http_busy || $https_busy; then
        echo ""
        echo "⚠️  Port Conflict Detected"
        echo ""
        if $http_busy; then
            local app
            app=$(port_listening_app "$HTTP_PORT")
            echo "   Port ${HTTP_PORT} is in use by: ${app:-another process}"
        fi
        if $https_busy; then
            local app
            app=$(port_listening_app "$HTTPS_PORT")
            echo "   Port ${HTTPS_PORT} is in use by: ${app:-another process}"
        fi
        echo ""
        echo "Plak needs an HTTP and HTTPS port. How would you like to proceed?"
        echo ""

        local choice
        if $auto_yes; then
            # Non-interactive: pick the safest default that avoids the conflict.
            choice="Use alternative ports (8090 / 8453) — run alongside other tools"
        else
            choice=$(gum choose \
                "Use alternative ports (8090 / 8453) — run alongside other tools" \
                "Pick custom ports" \
                "Proceed with ${HTTP_PORT}/${HTTPS_PORT} anyway" \
                "Cancel installation")
        fi

        case "$choice" in
            "Use alternative ports"*)
                HTTP_PORT=8090
                HTTPS_PORT=8453
                if port_has_conflict "$HTTP_PORT" || port_has_conflict "$HTTPS_PORT"; then
                    if ! $auto_yes; then
                        gum style --foreground yellow \
                            "⚠️  8090 or 8453 is also in use — please pick custom ports."
                    fi
                    if $auto_yes; then
                        # Auto-pick next free port
                        HTTP_PORT=$(next_free_port 8090)
                        HTTPS_PORT=$(next_free_port 8453)
                    else
                        prompt_custom_ports "$(next_free_port 8090)" "$(next_free_port 8453)"
                    fi
                fi
                ;;
            "Pick custom ports")
                prompt_custom_ports "$(next_free_port 8090)" "$(next_free_port 8453)"
                ;;
            "Proceed with"*)
                gum style --foreground yellow \
                    "⚠️  Services may fail to bind on ${HTTP_PORT}/${HTTPS_PORT}."
                ;;
            "Cancel installation")
                echo "🚫 Installation cancelled."
                exit 1
                ;;
        esac
        port_choice_made=true
    fi

    if $port_choice_made; then
        gum style --foreground green \
            "✅ Using ports ${HTTP_PORT} (HTTP) / ${HTTPS_PORT} (HTTPS)"
    fi

    # Persist the final choice — regenerate_caddyfile and get_wp_cmd both
    # pick up the globals directly.
    config_set HTTP_PORT "$HTTP_PORT"
    config_set HTTPS_PORT "$HTTPS_PORT"

    # --- Pre-install Checks ---
    # $PLAK_SITE_DIR alone isn't a reliable "previous install" marker — config_set
    # above creates it just to persist HTTP_PORT/HTTPS_PORT. Check for a
    # directory that only a completed install writes (Adminer), so the prompt
    # only fires when it's actually meaningful.
    if [ -d "$ADMINER_DIR" ]; then
        if ! $auto_yes && ! gum confirm "⚠️ Plak already appears to be installed at ~/Plak. Proceeding may overwrite some configurations. Continue?"; then
            echo "🚫 Installation cancelled."
            exit 0
        fi
    fi

    # FrankenPHP uses its own universal installer.
    # The upstream installer tries to write to /usr/local/bin and silently
    # falls back to CWD when that fails — which happens on a fresh Apple
    # Silicon Mac (Homebrew lives at /opt/homebrew/bin). To handle both,
    # we run the installer from a tempdir and, if the binary ends up there
    # instead of on PATH, move it into $BIN_DIR ourselves.
    if ! command -v frankenphp &> /dev/null; then
        gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "Installing Dependency: frankenphp"
        echo "   - Using the official FrankenPHP installer..."
        local fp_tmpdir
        fp_tmpdir=$(mktemp -d)
        if (cd "$fp_tmpdir" && curl -sL https://frankenphp.dev/install.sh | $SUDO_CMD bash); then
            hash -r
            if ! command -v frankenphp &> /dev/null && [ -x "$fp_tmpdir/frankenphp" ]; then
                $SUDO_CMD mv "$fp_tmpdir/frankenphp" "$BIN_DIR/frankenphp"
                $SUDO_CMD chmod +x "$BIN_DIR/frankenphp"
                hash -r
            fi
            rm -rf "$fp_tmpdir"
            if command -v frankenphp &> /dev/null; then
                echo "✅ FrankenPHP installed successfully."
            else
                gum style --foreground red "❌ FrankenPHP installer ran but the binary is not on PATH."
                exit 1
            fi
        else
            rm -rf "$fp_tmpdir"
            gum style --foreground red "❌ The FrankenPHP download script failed."
            exit 1
        fi
    else
        echo "✅ FrankenPHP is already installed."
    fi

    # On Linux with apt/dnf, FrankenPHP needs additional PHP extensions installed
    # The DEB/RPM packages don't include all extensions by default
    if [ "$OS" = "linux" ]; then
        echo "📦 Installing FrankenPHP PHP extensions for WordPress..."
        if [ "$PKG_MANAGER" = "apt" ]; then
            # Install required PHP extensions for WordPress via apt
            $SUDO_CMD apt install -y php-zts-mysqli php-zts-curl php-zts-gd php-zts-xml php-zts-mbstring php-zts-zip php-zts-intl php-zts-bcmath 2>/dev/null || true
            echo "✅ FrankenPHP PHP extensions installed."
        elif [ "$PKG_MANAGER" = "dnf" ]; then
            # Install required PHP extensions for WordPress via dnf
            $SUDO_CMD dnf install -y php-zts-mysqli php-zts-curl php-zts-gd php-zts-xml php-zts-mbstring php-zts-zip php-zts-intl php-zts-bcmath 2>/dev/null || true
            echo "✅ FrankenPHP PHP extensions installed."
        fi

        # Verify mysqli is available
        if ! frankenphp php-cli -r "echo implode(',', get_loaded_extensions());" 2>/dev/null | grep -qi mysqli; then
            gum style --foreground yellow "⚠️ Warning: mysqli extension not found in FrankenPHP."
            gum style --foreground yellow "   WordPress may not work correctly."
            gum style --foreground yellow "   Try: sudo apt install php-zts-mysqli (for apt)"
            gum style --foreground yellow "   Or:  sudo dnf install php-zts-mysqli (for dnf)"
        fi

        # Let FrankenPHP bind ports 80/443 as the user. Without this cap,
        # Plak would need to sudo-start the server, which makes every
        # dashboard-triggered file (sites, lock dirs, pidfile) root-owned.
        if command -v setcap &>/dev/null; then
            local fp_bin
            fp_bin=$(command -v frankenphp)
            if [ -n "$fp_bin" ]; then
                echo "🔐 Granting FrankenPHP cap_net_bind_service..."
                $SUDO_CMD setcap 'cap_net_bind_service=+ep' "$fp_bin" 2>/dev/null || \
                    gum style --foreground yellow "⚠️ setcap failed — Plak may fall back to needing sudo."
            fi
        fi

        # The apt frankenphp package ships a systemd unit that runs as
        # user frankenphp reading /etc/frankenphp/Caddyfile. That contends
        # with Plak for ports 80/443. Mask it so it stays out of our way.
        if systemctl list-unit-files frankenphp.service &>/dev/null \
            && systemctl cat frankenphp.service 2>/dev/null | grep -q '^\[Unit\]'; then
            echo "🚫 Masking conflicting apt frankenphp.service..."
            $SUDO_CMD systemctl stop frankenphp.service &>/dev/null || true
            $SUDO_CMD systemctl disable frankenphp.service &>/dev/null || true
            $SUDO_CMD systemctl mask frankenphp.service &>/dev/null || true
        fi
    fi

    # MariaDB - Database server
    install_dependency "mariadb" "mariadb" "mariadb-server" "mariadb-server" ""

    # --- MariaDB Port Selection ---
    local original_db_port="$DB_PORT"
    local db_port_choice_made=false
    local db_busy=false
    db_port_has_conflict "$DB_PORT" && db_busy=true

    if $db_busy; then
        echo ""
        echo "⚠️  MariaDB Port Conflict Detected"
        echo ""
        local app
        app=$(port_listening_app "$DB_PORT")
        echo "   Port ${DB_PORT} is in use by: ${app:-another process}"
        echo ""
        # Plak does not move an existing MariaDB server, so a port is only
        # useful to it when a MariaDB already answers there. Offering a free-but
        # empty port would just make the readiness loop time out (see CLI-29).
        if ! db_port_is_mariadb "$DB_PORT"; then
            gum style --foreground red "❌ No MariaDB answers on port ${DB_PORT}."
            gum style --foreground yellow "   That port is held by another service. Plak does not reconfigure an existing MariaDB server."
            gum style --foreground yellow "   Free port ${DB_PORT} or point MariaDB at it, then re-run 'plak install'."
            gum style --foreground yellow "   Configure MariaDB for a different port manually if you need to keep ${DB_PORT} busy."
            exit 1
        fi
        echo "Plak found MariaDB reachable on ${DB_PORT}. How would you like to proceed?"
        echo ""

        local db_choice
        if $auto_yes; then
            db_choice="Proceed with"
        else
            db_choice=$(gum choose \
                "Proceed with ${DB_PORT} anyway" \
                "Cancel installation")
        fi

        case "$db_choice" in
            "Proceed with"*)
                : # MariaDB already answers here; keep the configured port.
                ;;
            *)
                echo "🚫 Installation cancelled."
                exit 1
                ;;
        esac
        db_port_choice_made=true
    elif [ "$DB_PORT" != "3306" ] && ! $auto_yes; then
        echo ""
        gum style --foreground "212" \
            "Plak is currently configured for MariaDB port: ${DB_PORT}"
        echo ""

        local db_choice
        db_choice=$(gum choose \
            "Keep current MariaDB port (${DB_PORT})" \
            "Switch to default port (3306)")

        case "$db_choice" in
            "Keep current"*)
                : # no change
                ;;
            "Switch to default"*)
                DB_PORT=3306
                if db_port_has_conflict "$DB_PORT"; then
                    gum style --foreground red "❌ Port 3306 is in use and no MariaDB answers there."
                    gum style --foreground yellow "   Free port 3306 or set MariaDB to use it, then re-run 'plak install'."
                    exit 1
                fi
                ;;
        esac
        db_port_choice_made=true
    fi

    if $db_port_choice_made || [ "$original_db_port" != "$DB_PORT" ]; then
        gum style --foreground green \
            "✅ Using MariaDB port ${DB_PORT}"
    fi

    # Note: Don't call plak_site_configure_mariadb_port here — it creates
    # plak.cnf which conflicts with Homebrew's MariaDB default config.

    # No standalone PHP install — wp-cli is invoked through frankenphp php-cli
    # (see get_wp_cmd in main), so FrankenPHP's bundled PHP is the single PHP
    # runtime for both web and CLI. On Linux the php-zts-* extensions installed
    # above provide WordPress's required extensions to FrankenPHP.

    # Mailpit - Email testing tool.
    # On macOS we use the Homebrew formula. On Linux we use the upstream
    # installer because mailpit isn't packaged in apt/dnf.
    # Why: the upstream installer hardcodes /usr/local/bin, which doesn't
    # exist on a fresh Apple Silicon Mac (Homebrew lives at /opt/homebrew).
    if [ "$OS" == "macos" ]; then
        install_dependency "mailpit" "mailpit" "" "" ""
    elif ! command -v mailpit &> /dev/null; then
        gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "Installing Dependency: mailpit"
        echo "   - Using the official Mailpit installer..."
        if curl -sL https://raw.githubusercontent.com/axllent/mailpit/develop/install.sh | $SUDO_CMD bash; then
            echo "✅ Mailpit installed successfully."
        else
            gum style --foreground red "❌ The Mailpit download script failed."
            exit 1
        fi
    else
        echo "✅ Mailpit is already installed."
    fi

    # WP-CLI - WordPress command line tool
    # Not in default Linux repos, so we use the phar download as fallback
    install_dependency "wp" "wp-cli" "" "" "https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"

    # wp-mcp-cli - the WP-MCP companion CLI used by `plak add --agent` to
    # register sites. Installed from a pinned release for reproducibility.
    plak_agent_install_cli

    # --- Directory and Service Setup (Copied from original file) ---
    echo "📁 Creating Plak directory structure..."
    mkdir -p "$SITES_DIR" "$LOGS_DIR" "$GUI_DIR" "$ADMINER_DIR" "$CUSTOM_CADDY_DIR"

    # Write the PHP ini that wp-cli (via frankenphp php-cli) will load.
    # See the comment on $PHPRC export in main for the rationale.
    # error_reporting=6143 is E_ALL minus E_DEPRECATED/E_USER_DEPRECATED/E_STRICT
    # so wp-cli's bundled vendor code (react/promise, php-cli-tools/Colors.php)
    # doesn't flood every command on PHP 8.5+.
    echo "⚙️ Writing Plak PHP ini..."
    cat > "$PHP_INI_FILE" <<'INI'
memory_limit = 1G
display_errors = 0
error_reporting = 6143
; OPcache for the web process. enable_cli stays 0 so wp-cli and one-off PHP
; runs are never served a stale cache; tune with `plak health opcache set`.
opcache.enable = 1
opcache.enable_cli = 0
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.validate_timestamps = 1
opcache.revalidate_freq = 2
INI
    echo "🗃️ Downloading Adminer 5.4.2..."
    curl -sL "https://github.com/vrana/adminer/releases/download/v5.4.2/adminer-5.4.2.php" -o "$ADMINER_DIR/adminer-core.php"
    # Entry point + theme assets. Keep in sync with plak_site_upgrade so upgraders
    # pick up index.php/head() and CSS/JS changes without a full reinstall.
    deploy_adminer_theme

    echo "✨ Downloading Whoops error handler..."
    rm -rf "$APP_DIR/whoops" # Remove any old versions first
    mkdir -p "$APP_DIR/whoops"
    curl -sL "https://github.com/filp/whoops/archive/refs/tags/2.15.3.tar.gz" | tar -xz -C "$APP_DIR/whoops" --strip-components=1

    # --- Fedora/RHEL SELinux labeling ---
    # The upstream FrankenPHP installer tags /usr/bin/frankenphp with the
    # httpd_exec_t file context. On Fedora/RHEL that triggers an exec-time
    # domain transition into httpd_t — a confined web-server domain that:
    #   - can't read files labeled user_home_t (fails to open ~/Plak/Caddyfile
    #     and ~/.local/share/caddy/pki/.../root.crt with "permission denied")
    #   - silently RSTs TLS connections under some configs (TCP accepts but
    #     the TLS ClientHello gets no response)
    # Neither failure logs an AVC — both are dontaudit'd. Retagging the binary
    # as bin_t keeps systemd running it in unconfined_service_t, which can
    # read user files normally. On non-SELinux distros (Debian/Ubuntu)
    # semanage isn't in $PATH and this block is a no-op.
    if [ "$OS" = "linux" ] && command -v semanage &>/dev/null; then
        local fp_bin
        fp_bin=$(command -v "$CADDY_CMD")
        if [ -n "$fp_bin" ]; then
            echo "🔐 Relabeling FrankenPHP for SELinux..."
            $SUDO_CMD semanage fcontext -a -t bin_t "$fp_bin" &>/dev/null \
                || $SUDO_CMD semanage fcontext -m -t bin_t "$fp_bin" &>/dev/null \
                || true
            $SUDO_CMD restorecon "$fp_bin" &>/dev/null || true
        fi
    fi

    echo "⚙️ Starting services..."
    if [ "$OS" == "macos" ]; then
        if ! brew services restart mariadb; then
            gum style --foreground red "❌ Failed to start MariaDB via Homebrew."
            exit 1
        fi
    else # Linux
        if ! $SUDO_CMD systemctl restart mariadb; then
            gum style --foreground red "❌ Failed to start MariaDB via systemctl."
            exit 1
        fi
    fi

    # --- Database Configuration ---
    # Reuse saved DB creds if present. $CONFIG_FILE always exists at this
    # point (config_set above wrote HTTP_PORT/HTTPS_PORT), so probe for the
    # DB keys specifically rather than just the file.
    local has_db_config=false
    if [ -f "$CONFIG_FILE" ] && grep -q '^DB_USER=' "$CONFIG_FILE" 2>/dev/null; then
        has_db_config=true
    fi
    if $has_db_config && { $auto_yes || gum confirm "Existing Plak database config found. Use it and skip database setup?"; }; then
        echo "✅ Using existing database configuration."
    else
        gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "Configuring MariaDB"
        echo "   - Waiting for MariaDB service..."
        i=0
        while ! mysqladmin -h "$DB_HOST" -P "$DB_PORT" ping --silent 2>/dev/null; do
            sleep 1;
            i=$((i+1))
            if [ $i -ge 20 ]; then
                gum style --foreground red "❌ MariaDB did not become available on ${DB_HOST}:${DB_PORT} in time."
                # Show the real connection error, not the SSL warning the
                # --silent flag otherwise leaves as the only visible output.
                local db_err
                db_err=$(mysqladmin -h "$DB_HOST" -P "$DB_PORT" ping 2>&1 | grep -v 'ssl-verify-server-cert' | tail -1)
                [ -n "$db_err" ] && gum style --foreground red "   ${db_err}"
                gum style --foreground yellow "   Check that MariaDB is listening on port ${DB_PORT}: ss -tlnp | grep ${DB_PORT}"
                exit 1
            fi
        done
        echo "   - ✅ MariaDB is ready."
        local db_user="plak_cli_user"
        local db_pass
        db_pass=$(plak_site_random_password 16)
        local sql_command="DROP USER IF EXISTS '$db_user'@'localhost'; DROP USER IF EXISTS '$db_user'@'127.0.0.1'; CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass'; CREATE USER '$db_user'@'127.0.0.1' IDENTIFIED BY '$db_pass'; GRANT ALL PRIVILEGES ON *.* TO '$db_user'@'localhost' WITH GRANT OPTION; GRANT ALL PRIVILEGES ON *.* TO '$db_user'@'127.0.0.1' WITH GRANT OPTION; FLUSH PRIVILEGES;"
        local user_created_successfully=false
        local mariadb_socket="$PLAK_SITE_DIR/mariadb.sock"

        echo "   - Attempting automatic setup..."
        if echo "$sql_command" | $SUDO_CMD mysql &> /dev/null; then
            echo "   - ✅ Automatic database user creation successful."
            user_created_successfully=true
        elif $auto_yes; then
            echo "   - ❌ Automatic database setup failed and --yes is set. Cannot prompt for root credentials."
            exit 1
        else
            echo "   - ⚠️ Automatic setup failed. Falling back to manual credential entry..."
            local root_user
            root_user=$(gum input --value "root" --prompt "MariaDB Root Username: ")
            local root_pass
            root_pass=$(gum input --password --placeholder "Password for '$root_user'")

            if echo "$sql_command" | mysql -u "$root_user" -p"$root_pass"; then
                echo "   - ✅ Manual database user creation successful."
                user_created_successfully=true
            fi
        fi
        if $user_created_successfully; then
            echo "   - 📝 Saving new configuration..."
            config_set DB_USER "$db_user"
            config_set DB_PASSWORD "$db_pass"
            config_set DB_HOST "$DB_HOST"
            config_set DB_PORT "$DB_PORT"
        else
            gum style --foreground red "❌ Database user creation failed. Please check credentials and MariaDB logs."
            exit 1
        fi
    fi

    # --- Finalize ---
    create_whoops_bootstrap
    create_gui_file
    regenerate_caddyfile

    echo "✅ Initial configuration complete. Starting services..."
    plak_site_enable

    # Install the local CA into the system trust store and any browser NSS
    # databases we can find. Needs Caddy up (for the admin API trust call)
    # and the root cert to exist (Caddy generated it during the initial
    # plak_site_enable above). Idempotent — users can re-run via plak trust.
    echo ""
    plak_site_trust

    # Let the central helper discover existing WordPress sites. With no sites,
    # this is a silent no-op and avoids duplicating site detection here.
    if [ "$original_https" != "$HTTPS_PORT" ]; then
        echo ""
        echo "🔄 Updating WordPress site URLs to new HTTPS port..."
        if ! update_wp_site_urls_for_port_change "$original_https" "$HTTPS_PORT"; then
            url_migration_failed=true
            gum style --foreground yellow \
                "⚠️  Ports changed, but some WordPress URLs could not be migrated."
        fi
    fi

    # Show post-install guidance
    echo ""
    if [ "$HTTPS_PORT" != "443" ]; then
        gum style --border normal --margin "1" --padding "1 2" --border-foreground "yellow" \
            "📋 First-Time Setup Notes" \
            "Plak is running on custom ports: HTTP ${HTTP_PORT} / HTTPS ${HTTPS_PORT}" \
            "Access the dashboard at: $(url_for plak.localhost)"
    else
        gum style --border normal --margin "1" --padding "1 2" --border-foreground "yellow" \
            "📋 First-Time Setup Notes"
    fi
    echo ""
    echo "  Your browser will show a certificate warning when accessing Plak sites."
    echo "  This is normal for local development with self-signed certificates."
    echo ""
    echo "  Options to resolve:"
    echo "    1. Click 'Advanced' and 'Proceed' to accept the certificate"
    echo "    2. Or trust Caddy's root CA certificate system-wide (recommended)"
    echo ""
    if [ "$OS" == "macos" ]; then
        echo "  On macOS, Caddy typically auto-trusts its CA. If not, the CA cert is at:"
        echo "    ~/Library/Application Support/Caddy/pki/authorities/local/root.crt"
    else
        echo "  On Linux, the CA certificate is located at:"
        echo "    ~/.local/share/caddy/pki/authorities/local/root.crt"
        echo ""
        echo "  To trust it system-wide (Ubuntu/Debian):"
        echo "    sudo cp ~/.local/share/caddy/pki/authorities/local/root.crt /usr/local/share/ca-certificates/caddy.crt"
        echo "    sudo update-ca-certificates"
        echo ""
        echo "  For browser-only trust, import the certificate in your browser settings."
    fi

    if [ "$IS_WSL" = true ]; then
        echo ""
        gum style --foreground yellow "  WSL: Run 'plak wsl-hosts' for Windows hosts file setup instructions."
    fi

    if $url_migration_failed; then
        return 1
    fi
}

# Source: commands/site/lan
# --- LAN Access Commands ---
# Enables local network access to Plak sites for mobile app sync

LAN_PORTS_FILE="$PLAK_SITE_DIR/lan_ports"
LAN_START_PORT=8443

# Get the next available LAN port
get_next_lan_port() {
    local port=$LAN_START_PORT
    if [ -f "$LAN_PORTS_FILE" ]; then
        # Find the highest port in use and add 1
        local max_port
        max_port=$(cut -d'=' -f2 "$LAN_PORTS_FILE" | sort -n | tail -1)
        if [ -n "$max_port" ]; then
            port=$((max_port + 1))
        fi
    fi
    echo "$port"
}

# Get the assigned port for a site
get_site_lan_port() {
    local site_name="$1"
    if [ -f "$LAN_PORTS_FILE" ]; then
        grep "^${site_name}=" "$LAN_PORTS_FILE" | cut -d'=' -f2
    fi
}

# Get local network IP address
get_lan_ip() {
    if [ "$OS" == "macos" ]; then
        ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "unknown"
    else
        hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown"
    fi
}

# Create Bonjour advertisement LaunchAgent
create_bonjour_service() {
    local site_name="$1"
    local port="$2"
    local service_name="com.plak.${site_name}.lan"
    local plist_path="$HOME/Library/LaunchAgents/${service_name}.plist"
    
    # Only supported on macOS
    if [ "$OS" != "macos" ]; then
        echo "   - Bonjour advertisement not supported on Linux (skipping)"
        return 0
    fi
    
    echo "   - Creating Bonjour advertisement for ${site_name}..."
    
    mkdir -p "$HOME/Library/LaunchAgents"
    
    cat > "$plist_path" << EOM
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${service_name}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/dns-sd</string>
        <string>-R</string>
        <string>${site_name}</string>
        <string>_beckon._tcp</string>
        <string>local</string>
        <string>${port}</string>
        <string>path=/</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOM
    
    # Load and start the service
    launchctl unload "$plist_path" &>/dev/null
    launchctl load "$plist_path"
    launchctl start "$service_name"
    
    echo "   - Bonjour service started: _beckon._tcp (${site_name})"
}

# Remove Bonjour advertisement LaunchAgent
remove_bonjour_service() {
    local site_name="$1"
    local service_name="com.plak.${site_name}.lan"
    local plist_path="$HOME/Library/LaunchAgents/${service_name}.plist"
    
    if [ "$OS" != "macos" ]; then
        return 0
    fi
    
    if [ -f "$plist_path" ]; then
        echo "   - Stopping Bonjour advertisement..."
        launchctl unload "$plist_path" &>/dev/null
        rm -f "$plist_path"
    fi
}

plak_site_lan_enable() {
    local site_name="$1"
    
    if [ -z "$site_name" ]; then
        gum style --foreground red "Error: Site name is required."
        echo "Usage: plak lan enable <site>"
        exit 1
    fi
    
    # Normalize site name (remove .localhost suffix if present)
    site_name="${site_name%.localhost}"
    
    local site_dir="$SITES_DIR/${site_name}.localhost"
    
    if [ ! -d "$site_dir" ]; then
        gum style --foreground red "Error: Site '${site_name}' not found."
        exit 1
    fi
    
    local lan_config="$site_dir/lan_config"
    plak_multisite_require_single "$site_dir/public" 'IP-based LAN access' || return 1
    
    if [ -f "$lan_config" ]; then
        local existing_port
        existing_port=$(grep "^port=" "$lan_config" | cut -d'=' -f2)
        gum style --foreground yellow "Site '${site_name}' already has LAN access enabled on port ${existing_port}."
        exit 0
    fi
    
    echo "Enabling LAN access for ${site_name}..."
    
    # Assign a port
    local port
    port=$(get_next_lan_port)
    
    # Save to lan_ports file
    echo "${site_name}=${port}" >> "$LAN_PORTS_FILE"
    
    # Create lan_config file in site directory
    echo "port=${port}" > "$lan_config"
    echo "enabled_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$lan_config"
    
    # Create Bonjour advertisement
    create_bonjour_service "$site_name" "$port"
    
    # Regenerate Caddyfile to include LAN binding
    regenerate_caddyfile
    
    local lan_ip
    lan_ip=$(get_lan_ip)
    
    echo ""
    gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 \
        "LAN Access Enabled for ${site_name}" \
        "" \
        "Port: ${port}" \
        "Local URL: $(display_url_for "${site_name}.localhost")" \
        "LAN URL: $(plak_terminal_link "https://${lan_ip}:${port}")" \
        "" \
        "Bonjour: _beckon._tcp (displakrable by iOS apps)" \
        "" \
        "Note: Mobile devices need to trust Caddy's CA certificate." \
        "Run 'plak lan trust' for instructions."
}

plak_site_lan_disable() {
    local site_name="$1"
    
    if [ -z "$site_name" ]; then
        gum style --foreground red "Error: Site name is required."
        echo "Usage: plak lan disable <site>"
        exit 1
    fi
    
    # Normalize site name
    site_name="${site_name%.localhost}"
    
    local site_dir="$SITES_DIR/${site_name}.localhost"
    local lan_config="$site_dir/lan_config"
    
    if [ ! -f "$lan_config" ]; then
        gum style --foreground yellow "Site '${site_name}' does not have LAN access enabled."
        exit 0
    fi
    
    echo "Disabling LAN access for ${site_name}..."
    
    # Remove Bonjour service
    remove_bonjour_service "$site_name"
    
    # Remove from lan_ports file
    if [ -f "$LAN_PORTS_FILE" ]; then
        grep -v "^${site_name}=" "$LAN_PORTS_FILE" > "${LAN_PORTS_FILE}.tmp"
        mv "${LAN_PORTS_FILE}.tmp" "$LAN_PORTS_FILE"
    fi
    
    # Remove lan_config file
    rm -f "$lan_config"
    
    # Regenerate Caddyfile
    regenerate_caddyfile
    
    gum style --foreground green "LAN access disabled for ${site_name}."
}

plak_site_lan_status() {
    echo "LAN Access Status"
    echo "================="
    echo ""
    
    local lan_ip
    lan_ip=$(get_lan_ip)
    echo "Your LAN IP: ${lan_ip}"
    echo ""
    
    local found_any=false
    
    if [ -d "$SITES_DIR" ]; then
        for site_path in "$SITES_DIR"/*; do
            if [ -d "$site_path" ]; then
                local site_name
                site_name=$(basename "$site_path")
                site_name="${site_name%.localhost}"
                
                local lan_config="$site_path/lan_config"
                if [ -f "$lan_config" ]; then
                    found_any=true
                    local port
                    port=$(grep "^port=" "$lan_config" | cut -d'=' -f2)
                    echo "  ${site_name}"
                    echo "    Port: ${port}"
                    echo "    LAN URL: $(plak_terminal_link "https://${lan_ip}:${port}")"
                    echo "    Bonjour: _beckon._tcp (${site_name})"
                    echo ""
                fi
            fi
        done
    fi
    
    if [ "$found_any" = false ]; then
        echo "  No sites have LAN access enabled."
        echo ""
        echo "  Enable LAN access for a site with:"
        echo "    plak lan enable <site>"
    fi
}

plak_site_lan_trust() {
    echo "Trusting Caddy's CA Certificate on Mobile Devices"
    echo "================================================="
    echo ""
    
    local ca_cert=""
    
    # Find Caddy's root CA certificate
    if [ "$OS" == "macos" ]; then
        ca_cert="$HOME/Library/Application Support/Caddy/pki/authorities/local/root.crt"
    else
        ca_cert="$HOME/.local/share/caddy/pki/authorities/local/root.crt"
    fi
    
    if [ ! -f "$ca_cert" ]; then
        gum style --foreground red "Error: Caddy's root CA certificate not found."
        echo "Expected location: $ca_cert"
        echo ""
        echo "Make sure Caddy has been started at least once with 'plak enable'."
        exit 1
    fi
    
    echo "Caddy's root CA certificate is located at:"
    echo "  $ca_cert"
    echo ""
    
    if [ "$OS" == "macos" ]; then
        echo "To trust this certificate on your iPhone/iPad:"
        echo ""
        echo "  1. AirDrop the certificate to your device:"
        gum style --foreground cyan "     Opening certificate location in Finder..."
        open -R "$ca_cert"
        echo ""
        echo "  2. On your iOS device, go to:"
        echo "     Settings > General > VPN & Device Management"
        echo "     Tap the certificate profile and install it."
        echo ""
        echo "  3. Then go to:"
        echo "     Settings > General > About > Certificate Trust Settings"
        echo "     Enable full trust for the Caddy root certificate."
        echo ""
    else
        echo "To trust this certificate on your mobile device:"
        echo ""
        echo "  1. Copy the certificate to your device (email, file transfer, etc.)"
        echo "  2. Install and trust the certificate in your device's settings"
        echo ""
    fi
    
    echo "Alternative: The Beckon iOS app can be configured to accept"
    echo "the self-signed certificate without system-wide trust."
}

plak_site_lan() {
    local action="$1"
    shift
    
    case "$action" in
        enable)
            plak_site_lan_enable "$@"
            ;;
        disable)
            plak_site_lan_disable "$@"
            ;;
        status)
            plak_site_lan_status "$@"
            ;;
        trust)
            plak_site_lan_trust "$@"
            ;;
        *)
            echo "Usage: plak lan <subcommand>"
            echo ""
            echo "Manage LAN access to Plak sites for mobile app sync."
            echo ""
            echo "Subcommands:"
            echo "  enable <site>    Enable LAN access for a site"
            echo "  disable <site>   Disable LAN access for a site"
            echo "  status           Show which sites have LAN access enabled"
            echo "  trust            Instructions for trusting Caddy's CA on mobile"
            exit 0
            ;;
    esac
}

# Source: commands/site/list
plak_site_list() {
    local show_totals=false json_mode=false
    for arg in "$@"; do
        case "$arg" in
            --totals) show_totals=true ;;
            --json) json_mode=true ;;
            -h|--help)
                echo "Usage: plak list [--totals] [--json]"
                exit 0
                ;;
        esac
    done

    # PHP script to find, sort, and format the site list
    local php_output
    php_output=$(SITES_DIR="$SITES_DIR" SHOW_TOTALS="$show_totals" JSON_MODE="$json_mode" HTTPS_PORT_SUFFIX="$(https_port_suffix)" frankenphp php-cli -r '
        function getDirectorySize(string $path): int {
            if (!is_dir($path)) return 0;
            $total_size = 0;
            $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($path, FilesystemIterator::SKIP_DOTS));
            foreach ($iterator as $file) {
                if ($file->isFile()) {
                    $total_size += $file->getSize();
                }
            }
            return $total_size;
        }

        function formatSize(int $bytes): string {
            if ($bytes === 0) return "0 B";
            $units = ["B", "KB", "MB", "GB", "TB"];
            $i = floor(log($bytes, 1024));
            return round($bytes / (1024 ** $i), 2) . " " . $units[$i];
        }

        $sites_dir = getenv("SITES_DIR");
        $show_totals = getenv("SHOW_TOTALS") === "true";
        $json_mode = getenv("JSON_MODE") === "true";
        $port_suffix = getenv("HTTPS_PORT_SUFFIX") ?: "";

        if (!is_dir($sites_dir)) {
            if ($json_mode) echo "[]\n";
            exit;
        }

        $sites = [];
        $items = scandir($sites_dir);

        foreach ($items as $item) {
            if ($item === "." || $item === "..") continue;
            $site_path = $sites_dir . "/" . $item;
            if (is_dir($site_path)) {
                $public_path = $site_path . "/public";
                $size = $show_totals && is_dir($public_path) ? formatSize(getDirectorySize($public_path)) : null;
                $network = null;
                if (is_file($site_path . "/.multisite-mode")) {
                    $cmd = escapeshellarg(getenv("PLAK_SITE_CMD") ?: "plak") . " network " . escapeshellarg(str_replace(".localhost", "", $item)) . " --json";
                    exec($cmd . " 2>/dev/null", $network_lines, $network_code);
                    if ($network_code === 0) $network = json_decode(implode("\n", $network_lines), true);
                    $network_lines = [];
                }
                $sites[] = [
                    "name" => str_replace(".localhost", "", $item),
                    "domain" => "https://" . $item . $port_suffix,
                    "type" => file_exists($site_path . "/public/wp-config.php") ? "WordPress" : "Plain",
                    "size" => $size,
                    "agent_ready" => file_exists($site_path . "/agent-ready"),
                    "multisite_mode" => is_file($site_path . "/.multisite-mode") ? trim(file_get_contents($site_path . "/.multisite-mode")) : null,
                    "network" => $network,
                ];
            }
        }

        if (empty($sites)) {
            if ($json_mode) echo "[]\n";
            exit;
        }

        // Sort the array: first by type, then by name
        array_multisort(
            array_column($sites, "type"), SORT_ASC,
            array_column($sites, "name"), SORT_ASC,
            $sites
        );

        // JSON output branch — machine-parseable
        if ($json_mode) {
            echo json_encode($sites, JSON_UNESCAPED_SLASHES) . "\n";
            exit;
        }

        // Column padding/gap
        $gap = 3;
        
        // Calculate column widths
        $name_width = max(array_map(fn($s) => strlen($s["name"]), $sites));
        $name_width = max($name_width, 4) + $gap;
        
        $domain_width = max(array_map(fn($s) => strlen($s["domain"]), $sites));
        $domain_width = max($domain_width, 6) + $gap;
        
        $type_width = 22 + $gap;

        $agent_width = 7 + $gap; // "Agent" column

        $size_width = $show_totals ? 11 : 0;

        // ANSI colors
        $pink = "\033[38;5;212m";
        $dim = "\033[2m";
        $reset = "\033[0m";

        // Box drawing characters
        $tl = "╭"; $tr = "╮"; $bl = "╰"; $br = "╯";
        $h = "─"; $v = "│";

        // Calculate total width
        $inner_width = $name_width + $domain_width + $type_width + $agent_width;
        if ($show_totals) {
            $inner_width += $size_width;
        }

        // Build horizontal lines
        $top_line = $pink . $tl . str_repeat($h, $inner_width) . $tr . $reset;
        $mid_line = $pink . $v . $reset . $dim . " " . str_repeat("-", $inner_width - 2) . " " . $reset . $pink . $v . $reset;
        $bot_line = $pink . $bl . str_repeat($h, $inner_width) . $br . $reset;

        // Header row (white text)
        $header = $pink . $v . $reset . " " . str_pad("Name", $name_width - 1) . str_pad("Domain", $domain_width) . str_pad("Type", $type_width) . str_pad("Agent", $agent_width);
        if ($show_totals) {
            $header .= str_pad("Size", $size_width);
        }
        $header .= $pink . $v . $reset;

        // Output
        echo $top_line . "\n";
        echo $header . "\n";
        echo $mid_line . "\n";

        foreach ($sites as $site) {
            $row = $pink . $v . $reset . " " . str_pad($site["name"], $name_width - 1);
            $row .= str_pad($site["domain"], $domain_width);
            $row .= str_pad($site["multisite_mode"] ? "Multisite (" . $site["multisite_mode"] . ")" : $site["type"], $type_width);
            $row .= str_pad($site["agent_ready"] ? "ready" : "-", $agent_width);
            if ($show_totals) {
                $row .= str_pad($site["size"] ?? "N/A", $size_width);
            }
            $row .= $pink . $v . $reset;
            echo $row . "\n";
        }

        echo $bot_line . "\n";
    ')

    if [ -z "$php_output" ]; then
        if [ "$json_mode" = true ]; then
            echo "[]"
        else
            gum style --padding "1 2" "No sites found. Add one with 'plak add <name>'."
        fi
    else
        if [ "$json_mode" = true ]; then
            echo "$php_output"
        else
            echo ""
            gum style --faint "Sites are located in ~/Plak/Sites/"
            echo ""
            echo "$php_output"
        fi
    fi
}

# Source: commands/site/log
plak_site_log() {
    local site_name=""
    local follow_flag=""

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            -f|--follow)
                follow_flag="-f"
                ;;
            *)
                if [[ -z "$site_name" ]]; then
                    site_name="$arg"
                fi
                ;;
        esac
    done

    # If no site specified, show the global error log
    if [[ -z "$site_name" ]]; then
        local log_file="$LOGS_DIR/errors.log"
        if [[ ! -f "$log_file" ]]; then
            echo "No global error log found at $log_file"
            exit 1
        fi

        if [[ -n "$follow_flag" ]]; then
            echo "Following global error log (Ctrl+C to stop)..."
            tail -f "$log_file"
        else
            echo "Global error log (last 50 lines):"
            echo ""
            tail -50 "$log_file"
        fi
        exit 0
    fi

    # Normalize site name
    local site_dir
    if [[ "$site_name" == *.localhost ]]; then
        site_dir="$SITES_DIR/$site_name"
    else
        site_dir="$SITES_DIR/${site_name}.localhost"
        site_name="${site_name}.localhost"
    fi

    if [[ ! -d "$site_dir" ]]; then
        echo "Site '$site_name' not found."
        exit 1
    fi

    local logs_dir="$site_dir/logs"
    if [[ ! -d "$logs_dir" ]]; then
        echo "No logs directory found for '$site_name'."
        exit 1
    fi

    # Find available log files
    local caddy_log="$logs_dir/caddy.log"
    local caddy_lan_log="$logs_dir/caddy-lan.log"

    # Determine which logs exist
    local available_logs=()
    [[ -f "$caddy_log" ]] && available_logs+=("$caddy_log")
    [[ -f "$caddy_lan_log" ]] && available_logs+=("$caddy_lan_log")

    if [[ ${#available_logs[@]} -eq 0 ]]; then
        echo "No log files found for '$site_name'."
        exit 1
    fi

    if [[ -n "$follow_flag" ]]; then
        echo "Following logs for $site_name (Ctrl+C to stop)..."
        tail -f "${available_logs[@]}"
    else
        echo "Logs for $site_name (last 50 lines each):"
        for log in "${available_logs[@]}"; do
            echo ""
            echo "--- $(basename "$log") ---"
            tail -50 "$log"
        done
    fi
}

# Source: commands/site/login
plak_site_login() {
    local raw_mode=false
    local positional=()
    local subsite="" arg

    while [ "$#" -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --subsite) [ "$#" -ge 2 ] || { plak_ui_error '--subsite requires an ID.'; return 1; }; subsite="$2"; shift ;;
            --raw|-r) raw_mode=true ;;
            -h|--help)
                echo "Usage: plak login <site> [<user>] [--subsite <id>] [--raw]"
                exit 0
                ;;
            *) positional+=("$arg") ;;
        esac
        shift
    done

    local site_name="${positional[0]:-}"
    local user_identifier="${positional[1]:-}"
    [ "${#positional[@]}" -le 2 ] || { plak_ui_error 'Unexpected login arguments.'; return 1; }
    if [ -n "$subsite" ]; then
        plak_multisite_login "$site_name" "$subsite" "$user_identifier" "$raw_mode"
        return $?
    fi

    # 1. Validate that a site name was provided.
    if [ -z "$site_name" ]; then
        gum style --foreground red "❌ Error: A site name is required."
        echo "Usage: plak login <site> [<user>]"
        exit 1
    fi

    local site_dir="$SITES_DIR/$site_name.localhost"
    local public_dir="$site_dir/public"

    # Get WP-CLI command (adds --allow-root if running as root)
    local wp_cmd
    wp_cmd=$(get_wp_cmd)

    # 2. Check if the site exists and is a WordPress installation.
    if [ ! -d "$site_dir" ] || [ ! -f "$public_dir/wp-config.php" ]; then
        gum style --foreground red "❌ Error: WordPress site '$site_name.localhost' not found."
        exit 1
    fi

    local user_to_login
    if [ -n "$user_identifier" ]; then
        echo "🔎 Verifying user '$user_identifier' for '$site_name.localhost'..."
        local user_roles
        user_roles=$( (cd "$public_dir" && $wp_cmd user get "$user_identifier" --field=roles --format=json --skip-plugins --skip-themes 2>/dev/null) )

        if [ -z "$user_roles" ]; then
            gum style --foreground red "❌ Error: User '$user_identifier' not found on this site."
            exit 1
        fi

        # Any role is allowed: the dashboard uses this to hand out links to
        # editors, authors and other non-administrator accounts.
        user_to_login="$user_identifier"
        echo "✅ User '$user_to_login' verified."
    else
        echo "🔎 Finding an administrator for '$site_name.localhost'..."
        user_to_login=$( (cd "$public_dir" && $wp_cmd user list --role=administrator --field=user_login --format=csv --skip-plugins --skip-themes | head -n 1) )

        if [ -z "$user_to_login" ]; then
            gum style --foreground red "❌ Error: Could not find any administrator users for this site."
            exit 1
        fi
        echo "✅ Found admin: '$user_to_login'."
    fi

    # 3. Refresh the MU-plugin before generating the URL. Always overwrite
    # the file so sites created with older Plak versions pick up changes to
    # the plugin (token format, query-arg name, etc.) without needing a
    # re-add. The file is small and idempotent to regenerate.
    inject_mu_plugin "$public_dir"

    # 4. Generate the login URL.
    echo "   Generating login link..."
    local login_url
    login_url=$( (cd "$public_dir" && $wp_cmd user login "$user_to_login" --skip-plugins --skip-themes) )

    # 5. Display the final URL or an error message.
    if [ -n "$login_url" ]; then
        if [ "$raw_mode" = true ]; then
            printf '%s\n' "$login_url"
        else
            gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "🔗 One-Time Login URL for '$user_to_login'" "$login_url"
        fi
    else
        gum style --foreground red "❌ Error: Failed to generate the login link after all checks."
        exit 1
    fi
}

# Source: commands/site/mappings
plak_site_mappings() {
    local json_mode=false
    local positional=()

    # Filter --json from positional args first
    for arg in "$@"; do
        case "$arg" in
            --json) json_mode=true ;;
            -h|--help)
                echo "Usage: plak mappings <site> [add|remove] [domain] [--json]"
                exit 0
                ;;
            *) positional+=("$arg") ;;
        esac
    done

    local site_name="${positional[0]:-}"
    local action="${positional[1]:-}"
    local domain="${positional[2]:-}"

    # --- 1. Validation ---
    if [ -z "$site_name" ]; then
        gum style --foreground red "❌ Error: A site name is required."
        echo "Usage: plak mappings <site> [add|remove] [domain] [--json]"
        exit 1
    fi

    local site_dir="$SITES_DIR/$site_name.localhost"
    local mappings_file="$site_dir/mappings"

    if [ ! -d "$site_dir" ]; then
        gum style --foreground red "❌ Error: Site '$site_name.localhost' not found."
        exit 1
    fi

    # --- 2. List Mappings (Default Action) ---
    if [ -z "$action" ] || [ "$action" == "list" ]; then
        if [ "$json_mode" = false ]; then
            echo "🔎 Checking domain mappings for $site_name..."
        fi

        if [ ! -f "$mappings_file" ] || [ ! -s "$mappings_file" ]; then
            if [ "$json_mode" = true ]; then
                printf '{"site":"%s","main":"%s.localhost","mappings":[]}\n' "$site_name" "$site_name"
            else
                gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "ℹ️  No additional mappings found." "Main domain: $site_name.localhost"
            fi
        else
            if [ "$json_mode" = true ]; then
                local escaped
                escaped=$(python3 -c 'import json,sys; print(json.dumps([l for l in sys.stdin.read().splitlines() if l]))' < "$mappings_file" 2>/dev/null \
                    || awk 'BEGIN{ printf "["; first=1 } NF { if (!first) printf ","; first=0; gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "\"%s\"", $0 } END{ print "]" }' "$mappings_file")
                printf '{"site":"%s","main":"%s.localhost","mappings":%s}\n' "$site_name" "$site_name" "$escaped"
            else
                local content
                content=$(cat "$mappings_file")
                gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "📂 Domain Mappings ($site_name)" "" "$content"
            fi
        fi
        return 0
    fi

    # --- 3. Add Mapping ---
    if [ "$action" == "add" ]; then
        if [ -z "$domain" ]; then
            gum style --foreground red "❌ Error: Please specify a domain to add."
            exit 1
        fi

        # Simple validation: prevent duplicates
        if [ -f "$mappings_file" ] && grep -Fxq "$domain" "$mappings_file"; then
            gum style --foreground yellow "⚠️  Domain '$domain' is already mapped to this site."
            exit 0
        fi

        # Create file if not exists and append
        echo "$domain" >> "$mappings_file"
        echo "✅ Added mapping: $domain"
        
        regenerate_caddyfile
        update_etc_hosts
        return 0
    fi

    # --- 4. Remove Mapping ---
    if [ "$action" == "remove" ]; then
        if [ -z "$domain" ]; then
            gum style --foreground red "❌ Error: Please specify a domain to remove."
            exit 1
        fi

        if [ -f "$mappings_file" ]; then
            # Use grep to filter out the domain and write to a temp file
            if grep -Fxq "$domain" "$mappings_file"; then
                grep -Fxv "$domain" "$mappings_file" > "${mappings_file}.tmp"
                mv "${mappings_file}.tmp" "$mappings_file"
                echo "✅ Removed mapping: $domain"
                
                regenerate_caddyfile
                update_etc_hosts
            else
                gum style --foreground red "❌ Error: Mapping '$domain' not found."
            fi
        else
             gum style --foreground red "❌ Error: No mappings exist for this site."
        fi
        return 0
    fi

    # --- 5. Unknown Action ---
    gum style --foreground red "❌ Error: Unknown action '$action'."
    echo "Usage: plak mappings <site> [add|remove] [domain]"
    exit 1
}
# Source: commands/site/memory
plak_site_memory() {
    # -----------------------------------------------------------------
    #  plak memory [set <value>]
    #  Show or tweak PHP memory_limit across every ini Plak or the
    #  user's Homebrew PHPs load. Plak's own ini lives at
    #  ~/Plak/php.ini and is read by FrankenPHP (both CLI via PHPRC and
    #  the web server via the php_ini directive in the Caddyfile, which
    #  reads its values from the same file through plak_site_ini_get).
    # -----------------------------------------------------------------

    local action="show"
    local new_value=""
    local auto_yes=false

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                display_command_help memory
                exit 0
                ;;
            set)
                action="set"
                new_value="$2"
                shift 2 || { gum style --foreground red "❌ 'set' requires a value (e.g. 2G)"; exit 1; }
                ;;
            --yes|-y|--force|--all)
                auto_yes=true
                shift
                ;;
            *)
                gum style --foreground red "❌ Unknown argument: $1"
                echo "Usage: plak memory [set <value>] [--yes]"
                exit 1
                ;;
        esac
    done

    if [ "$action" = "set" ]; then
        plak_site_memory_set "$new_value" "$auto_yes"
    else
        plak_site_memory_show
    fi
}

# Resolves the canonical path of a binary. Falls back to the original path
# if neither GNU readlink nor BSD-era greadlink is available.
plak_site_memory_realpath() {
    local p="$1"
    if readlink -f "$p" >/dev/null 2>&1; then
        readlink -f "$p"
    elif command -v greadlink >/dev/null 2>&1; then
        greadlink -f "$p"
    else
        echo "$p"
    fi
}

# Prints the php.ini path a given php binary loads, with surrounding
# whitespace and quotes trimmed (php --ini quotes the path when it
# contains special chars). PHPRC is unset so we see the ini each binary
# loads by default — without Plak's CLI override leaking in.
plak_site_memory_ini_for() {
    local php="$1"
    env -u PHPRC "$php" --ini 2>/dev/null \
        | awk -F': ' '/^Loaded Configuration File:/ {sub(/^[[:space:]]+/,"",$2); print $2}' \
        | sed -E 's/^"(.*)"$/\1/'
}

# Runs an inline PHP snippet against $1 without Plak's PHPRC, so the
# returned ini values reflect what the binary sees when the user invokes
# it from their own shell.
plak_site_memory_php_probe() {
    env -u PHPRC "$1" -r "$2" 2>/dev/null
}

plak_site_memory_show() {
    gum style --foreground "212" --bold "PHP memory_limit audit"
    echo ""

    # 1) Plak CLI ini
    local plak_site_mem
    plak_site_mem=$(plak_site_ini_get memory_limit "")
    echo "📁 Plak CLI  ($PHP_INI_FILE)"
    if [ -f "$PHP_INI_FILE" ]; then
        echo "   memory_limit         = ${plak_site_mem:-(unset — FrankenPHP default applies)}"
        echo "   upload_max_filesize  = $(plak_site_ini_get upload_max_filesize '(unset)')"
        echo "   post_max_size        = $(plak_site_ini_get post_max_size '(unset)')"
    else
        echo "   (file missing — run 'plak install')"
    fi

    # 2) Plak web server (Caddyfile frankenphp block)
    echo ""
    echo "🌐 Plak web ($CADDYFILE_PATH, frankenphp block)"
    if [ -f "$CADDYFILE_PATH" ]; then
        local caddy_mem
        caddy_mem=$(awk '/^[[:space:]]*php_ini[[:space:]]+memory_limit[[:space:]]+/ {print $3; exit}' "$CADDYFILE_PATH")
        if [ -n "$caddy_mem" ]; then
            echo "   memory_limit = $caddy_mem"
        else
            echo "   (no explicit memory_limit — inherits from ~/Plak/php.ini)"
        fi
    else
        echo "   (Caddyfile missing)"
    fi

    # 3) PHPs on PATH (dedup by canonical binary path)
    echo ""
    echo "🔍 PHP binaries on PATH"
    local seen_paths=""
    local php_path found=false
    while IFS= read -r php_path; do
        [ -z "$php_path" ] && continue
        local real_path
        real_path=$(plak_site_memory_realpath "$php_path")
        case ",$seen_paths," in *",$real_path,"*) continue ;; esac
        seen_paths="$seen_paths,$real_path"

        local php_ver php_ini php_mem
        php_ver=$(plak_site_memory_php_probe "$php_path" 'echo PHP_VERSION;')
        php_ini=$(plak_site_memory_ini_for "$php_path")
        php_mem=$(plak_site_memory_php_probe "$php_path" 'echo ini_get("memory_limit");')

        echo "   • $php_path"
        echo "       version       = ${php_ver:-unknown}"
        echo "       php.ini       = ${php_ini:-<none>}"
        echo "       memory_limit  = ${php_mem:-unknown}"
        found=true
    done < <(which -a php 2>/dev/null)
    if ! $found; then
        echo "   (no 'php' binary on PATH)"
    fi

    # 4) wp-cli's effective memory_limit (uses whichever php its shebang resolves)
    echo ""
    echo "🧰 wp-cli"
    local wp_bin
    wp_bin=$(command -v wp 2>/dev/null)
    if [ -n "$wp_bin" ]; then
        local wp_info wp_php wp_ver wp_mem
        wp_info=$(env -u PHPRC "$wp_bin" cli info 2>/dev/null)
        wp_php=$(echo "$wp_info" | awk -F':\t' '/^PHP binary:/ {sub(/^[[:space:]]+/,"",$2); print $2; exit}')
        wp_ver=$(echo "$wp_info" | awk -F':\t' '/^PHP version:/ {sub(/^[[:space:]]+/,"",$2); print $2; exit}')
        if [ -n "$wp_php" ] && [ -x "$wp_php" ]; then
            wp_mem=$(plak_site_memory_php_probe "$wp_php" 'echo ini_get("memory_limit");')
        fi
        echo "   wp             = $wp_bin"
        echo "   php binary     = ${wp_php:-unknown}"
        echo "   php version    = ${wp_ver:-unknown}"
        echo "   memory_limit   = ${wp_mem:-unknown}"
    else
        echo "   (wp-cli not found on PATH)"
    fi

    echo ""
    gum style --faint "To raise the limit everywhere: plak memory set 2G"
}

plak_site_memory_set() {
    local value="$1"
    local auto_yes="${2:-false}"

    if [ -z "$value" ]; then
        gum style --foreground red "❌ Missing value. Usage: plak memory set <value> (e.g. 2G)"
        exit 1
    fi

    # Non-interactive callers have no TTY; gum confirm aborts there. Auto-yes
    # so scripted fleet updates can bump every writable ini without hanging.
    [ -t 0 ] || auto_yes=true
    if [ "$value" != "-1" ] && [[ ! "$value" =~ ^[0-9]+[KMG]?$ ]]; then
        gum style --foreground red "❌ Invalid value '$value'. Use e.g. 512M, 2G, or -1 for unlimited."
        exit 1
    fi

    echo ""
    gum style --foreground "212" --bold "Setting memory_limit = $value"
    echo ""

    # 1) Plak CLI ini — source of truth for Plak
    mkdir -p "$(dirname "$PHP_INI_FILE")"
    touch "$PHP_INI_FILE"
    echo "📁 Updating $PHP_INI_FILE"
    local k
    for k in memory_limit upload_max_filesize post_max_size; do
        if grep -qE "^[[:space:]]*${k}[[:space:]]*=" "$PHP_INI_FILE"; then
            sed -i.bak -E "s|^[[:space:]]*${k}[[:space:]]*=.*|${k} = ${value}|" "$PHP_INI_FILE"
        else
            echo "${k} = ${value}" >> "$PHP_INI_FILE"
        fi
        echo "   ✓ ${k} = ${value}"
    done
    rm -f "${PHP_INI_FILE}.bak"

    # 2) Regenerate Caddyfile so FrankenPHP web server picks up the new values
    echo ""
    regenerate_caddyfile

    # 3) External PHP inis (Homebrew, distro-packaged) — opt-in per file.
    # Reads 'which -a php' on fd 3 so gum confirm inside the loop body can
    # read from the real stdin without swallowing the remaining PHP paths.
    echo ""
    echo "🔍 Scanning Homebrew / system PHP inis on PATH…"
    local seen_paths="" seen_inis=""
    local php_path
    while IFS= read -r php_path <&3; do
        [ -z "$php_path" ] && continue
        local real_path
        real_path=$(plak_site_memory_realpath "$php_path")
        case ",$seen_paths," in *",$real_path,"*) continue ;; esac
        seen_paths="$seen_paths,$real_path"

        local ini
        ini=$(plak_site_memory_ini_for "$php_path")
        [ -z "$ini" ] && continue
        # Skip Plak's ini (already handled) and duplicates
        [ "$(plak_site_memory_realpath "$ini")" = "$(plak_site_memory_realpath "$PHP_INI_FILE")" ] && continue
        case ",$seen_inis," in *",$ini,"*) continue ;; esac
        seen_inis="$seen_inis,$ini"

        local current
        current=$(grep -E "^[[:space:]]*memory_limit[[:space:]]*=" "$ini" 2>/dev/null \
            | tail -1 \
            | sed -E 's|^[[:space:]]*memory_limit[[:space:]]*=[[:space:]]*||' \
            | tr -d ' "')
        echo ""
        echo "   • $ini (current: ${current:-unset})"

        if ! [ -w "$ini" ]; then
            gum style --faint "     (not writable by this user — skipping. Run: sudo sed -i.bak -E 's|^[[:space:]]*memory_limit[[:space:]]*=.*|memory_limit = ${value}|' \"$ini\")"
            continue
        fi

        local do_update=false
        if [ "$auto_yes" = true ]; then
            do_update=true
        elif gum confirm "     Update this ini's memory_limit to ${value}?"; then
            do_update=true
        fi

        if $do_update; then
            if grep -qE "^[[:space:]]*memory_limit[[:space:]]*=" "$ini"; then
                sed -i.bak -E "s|^[[:space:]]*memory_limit[[:space:]]*=.*|memory_limit = ${value}|" "$ini"
            else
                echo "memory_limit = ${value}" >> "$ini"
            fi
            rm -f "${ini}.bak"
            gum style --foreground green "     ✓ Updated"
        else
            gum style --faint "     (skipped)"
        fi
    done 3< <(which -a php 2>/dev/null)

    echo ""
    gum style --foreground green "✅ Done. Run 'plak memory' to verify."
}

# Source: commands/site/network
# shellcheck disable=SC2016 # WordPress eval programs are literal PHP.
plak_network_usage() {
    echo 'Usage: plak network <site> [--json]'
    echo '       plak network create <site> <slug> [--title <title>]'
    echo '       plak login <site> [<user>] --subsite <id> [--raw]'
}

plak_network() {
    local action=inspect site slug="" title="" json=false
    [ "${1:-}" != create ] || { action=create; shift; }
    case "${1:-}" in -h|--help|"") plak_network_usage; return 0 ;; esac
    site="${1%.localhost}"; shift
    plak_validate_site_name "$site" || { plak_ui_error 'Invalid site name.'; return 1; }
    local public="$SITES_DIR/$site.localhost/public" mode
    [ -f "$public/wp-config.php" ] || { plak_ui_error 'WordPress site not found.'; return 1; }
    mode=$(plak_multisite_mode "$public") || return 1
    [ "$mode" != single ] || { plak_ui_error 'This site is not a multisite network.'; return 1; }
    if [ "$action" = create ]; then
        slug="${1:-}"; [ "$#" -eq 0 ] || shift
        plak_validate_site_name "$slug" || { plak_ui_error 'A valid lowercase subsite slug is required.'; return 1; }
        if [ "${1:-}" = --title ] && [ "$#" -ge 2 ]; then title="$2"; shift 2; fi
        [ "$#" -eq 0 ] || { plak_network_usage >&2; return 1; }
        plak_multisite_validate_local "$public" "$site" || return 1
        local created
        created=$(plak_multisite_wp "$public" site create "--slug=$slug" "--title=${title:-$slug}" --porcelain) || return 1
        [[ "$created" =~ ^[1-9][0-9]*$ ]] || { plak_ui_error 'WordPress did not return a subsite ID.'; return 1; }
        # WordPress initializes new multisite home/siteurl options with http
        # even when the parent uses HTTPS. Normalize only this new subsite.
        PLAK_MS_ID="$created" plak_multisite_wp "$public" eval '
            switch_to_blog((int)getenv("PLAK_MS_ID"));
            foreach(["home","siteurl"] as $key) {
                $url=set_url_scheme(get_option($key),"https");
                update_option($key,$url);
                if(get_option($key)!==$url) WP_CLI::error("Subsite HTTPS configuration failed.");
            }
            restore_current_blog();
        ' --skip-plugins --skip-themes || return 1
        echo "Created subsite #$created."
        if [ "$(cat "$public/../.multisite-mode" 2>/dev/null || true)" != "$mode" ]; then
            printf '%s\n' "$mode" > "$public/../.multisite-mode" || return 1
            regenerate_caddyfile || return 1
        fi
    else
        if [ "${1:-}" = --json ]; then json=true; shift; fi
        [ "$#" -eq 0 ] || { plak_network_usage >&2; return 1; }
    fi
    PLAK_MS_JSON="$json" plak_multisite_wp "$public" eval '
        $network=get_network(); $sites=[];
        foreach(get_sites(["number"=>0,"network_id"=>$network->id]) as $site) {
            $sites[]=["id"=>(int)$site->blog_id,"url"=>get_site_url($site->blog_id),"domain"=>$site->domain,"path"=>$site->path];
        }
        $report=["multisite"=>true,"mode"=>is_subdomain_install()?"subdomains":"subdirectories","network_id"=>(int)$network->id,"domain"=>$network->domain,"path"=>$network->path,"sites"=>$sites];
        if(getenv("PLAK_MS_JSON")==="true") echo wp_json_encode($report);
        else {echo "Network: ".$report["mode"]."\n"; foreach($sites as $site) echo $site["id"]."\t".$site["url"]."\n";}
    ' --skip-plugins --skip-themes
}

plak_multisite_login() {
    local site="$1" id="$2" user="$3" raw="$4" public="$SITES_DIR/$1.localhost/public" url login
    if ! plak_validate_site_name "$site" || ! [[ "$id" =~ ^[1-9][0-9]*$ ]]; then
        plak_ui_error 'Invalid network site or subsite ID.'; return 1
    fi
    [ -f "$public/wp-config.php" ] || { plak_ui_error 'WordPress network not found.'; return 1; }
    plak_multisite_validate_local "$public" "$site" || return 1
    url=$(PLAK_MS_ID="$id" PLAK_MS_HOST="$site.localhost" PLAK_MS_HTTPS_PORT="$HTTPS_PORT" plak_multisite_wp "$public" eval '
        $site=get_site((int)getenv("PLAK_MS_ID"));
        if(!$site || (int)$site->site_id !== get_current_network_id()) WP_CLI::error("Unknown subsite in this network.");
        $url=untrailingslashit(get_site_url($site->blog_id)); $parts=wp_parse_url($url); $host=getenv("PLAK_MS_HOST");
        if(($parts["scheme"]??"")!=="https" || (($parts["host"]??"")!==$host && !str_ends_with($parts["host"]??"",".".$host))
            || ($parts["host"]??"")!==explode(":",$site->domain)[0]
            || (int)($parts["port"]??443)!==(int)getenv("PLAK_MS_HTTPS_PORT")
            || untrailingslashit($parts["path"]??"/")!==untrailingslashit($site->path)) WP_CLI::error("External or mismatched subsite URL rejected.");
        echo $url;
    ' --skip-plugins --skip-themes) || return 1
    # URL is derived and validated in WordPress, not accepted from the caller.
    if [ -z "$user" ]; then
        user=$(plak_multisite_wp "$public" user list --role=administrator --field=user_login --url="$url" --skip-plugins --skip-themes | head -1) || return 1
    fi
    [ -n "$user" ] || { plak_ui_error 'No administrator found for this subsite.'; return 1; }
    PLAK_MS_USER="$user" PLAK_MS_ID="$id" plak_multisite_wp "$public" eval '
        $value=getenv("PLAK_MS_USER"); $user=is_numeric($value)?get_user_by("id",$value):(is_email($value)?get_user_by("email",$value):get_user_by("login",$value));
        if(!$user || (!is_super_admin($user->ID) && !is_user_member_of_blog($user->ID,(int)getenv("PLAK_MS_ID")))) WP_CLI::error("User is not a member of the selected subsite.");
    ' --url="$url" --skip-plugins --skip-themes || return 1
    inject_mu_plugin "$public" >/dev/null || return 1
    login=$(plak_multisite_wp "$public" user login "$user" --url="$url" --skip-plugins --skip-themes) || return 1
    [[ "$login" = "$url/"* ]] || { plak_ui_error 'Unexpected subsite login URL.'; return 1; }
    if [ "$raw" = true ]; then printf '%s\n' "$login"; else plak_terminal_link "$login"; fi
}

# Source: commands/site/path
plak_site_path() {
    local site_name="$1"

    if [ -z "$site_name" ]; then
        gum style --foreground red "❌ Error: A site name is required."
        echo "Usage: plak path <name>"
        exit 1
    fi

    local site_dir="$SITES_DIR/$site_name.localhost/public"

    if [ ! -d "$site_dir" ]; then
        gum style --foreground red "❌ Error: Site '$site_name.localhost' not found."
        exit 1
    fi

    echo "$site_dir"
}

# Source: commands/site/ports
plak_site_ports() {
    # -----------------------------------------------------------------
    #  plak ports
    #  Reconfigure the HTTP / HTTPS ports Plak listens on and (by
    #  default) migrate every WordPress site's stored URLs via
    #  wp search-replace so they match the new port.
    #
    #  Flags:
    #    --http PORT     Non-interactive: set HTTP port
    #    --https PORT    Non-interactive: set HTTPS port
    #    --skip-urls     Change ports without touching WordPress databases
    #    --dry-run       Preview changes (including search-replace counts)
    #                    without committing anything
    # -----------------------------------------------------------------

    local explicit_http=""
    local explicit_https=""
    local skip_urls=false
    local dry_run=false
    local auto_yes=false
    local url_migration_failed=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --http)
                explicit_http="$2"
                shift 2
                ;;
            --https)
                explicit_https="$2"
                shift 2
                ;;
            --skip-urls)
                skip_urls=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --yes|-y|--force)
                auto_yes=true
                shift
                ;;
            -h|--help)
                display_command_help ports
                exit 0
                ;;
            *)
                gum style --foreground red "❌ Unknown option: $1"
                echo "Usage: plak ports [--http PORT] [--https PORT] [--skip-urls] [--dry-run] [--yes]"
                exit 1
                ;;
        esac
    done

    # Non-interactive shells (PHP shell_exec, ssh piped stdin, systemd) have
    # no TTY; gum confirm aborts there with "could not open a new TTY". Auto-
    # promote to --yes so the caller's flags are respected.
    if [ ! -t 0 ]; then
        auto_yes=true
    fi

    local original_http="$HTTP_PORT"
    local original_https="$HTTPS_PORT"

    # --- Determine target ports ---
    if [ -n "$explicit_http" ] || [ -n "$explicit_https" ]; then
        # Non-interactive path — validate and apply.
        local target_http="${explicit_http:-$HTTP_PORT}"
        local target_https="${explicit_https:-$HTTPS_PORT}"

        if [[ ! "$target_http" =~ ^[0-9]+$ ]] || [ "$target_http" -lt 1 ] || [ "$target_http" -gt 65535 ]; then
            gum style --foreground red "❌ Invalid HTTP port: $target_http"
            exit 1
        fi
        if [[ ! "$target_https" =~ ^[0-9]+$ ]] || [ "$target_https" -lt 1 ] || [ "$target_https" -gt 65535 ]; then
            gum style --foreground red "❌ Invalid HTTPS port: $target_https"
            exit 1
        fi
        if [ "$target_http" = "$target_https" ]; then
            gum style --foreground red "❌ HTTP and HTTPS ports must differ."
            exit 1
        fi

        HTTP_PORT="$target_http"
        HTTPS_PORT="$target_https"
    else
        # Interactive menu
        echo ""
        gum style --foreground "212" \
            "Plak is currently on ports: HTTP ${HTTP_PORT} / HTTPS ${HTTPS_PORT}"
        echo ""

        local default_label="Switch to default ports (80 / 443)"
        if [ "$HTTP_PORT" != "80" ] || [ "$HTTPS_PORT" != "443" ]; then
            if port_has_conflict 80 || port_has_conflict 443; then
                default_label="Switch to default ports (80 / 443) — currently in use"
            fi
        fi

        local alt_label="Use alternative ports (8090 / 8453)"
        if [ "$HTTP_PORT" = "8090" ] && [ "$HTTPS_PORT" = "8453" ]; then
            alt_label=""
        elif port_has_conflict 8090 || port_has_conflict 8453; then
            alt_label="Use alternative ports (8090 / 8453) — currently in use"
        fi

        local -a menu_opts
        menu_opts=("Keep current ports (${HTTP_PORT} / ${HTTPS_PORT})")
        if [ "$HTTP_PORT" != "80" ] || [ "$HTTPS_PORT" != "443" ]; then
            menu_opts+=("$default_label")
        fi
        if [ -n "$alt_label" ]; then
            menu_opts+=("$alt_label")
        fi
        menu_opts+=("Pick custom ports" "Cancel")

        local choice
        choice=$(gum choose "${menu_opts[@]}")

        case "$choice" in
            "Keep current"*)
                echo "ℹ️  No changes."
                exit 0
                ;;
            "Switch to default"*)
                HTTP_PORT=80
                HTTPS_PORT=443
                ;;
            "Use alternative"*)
                if ! port_has_conflict 8090 && ! port_has_conflict 8453; then
                    HTTP_PORT=8090
                    HTTPS_PORT=8453
                else
                    gum style --foreground yellow \
                        "⚠️  8090 or 8453 is in use — please pick custom ports."
                    prompt_custom_ports "$(next_free_port 8090)" "$(next_free_port 8453)"
                fi
                ;;
            "Pick custom ports")
                prompt_custom_ports "$(next_free_port 8090)" "$(next_free_port 8453)"
                ;;
            "Cancel"|*)
                echo "🚫 Cancelled."
                exit 0
                ;;
        esac
    fi

    # --- Check if anything actually changed ---
    if [ "$original_http" = "$HTTP_PORT" ] && [ "$original_https" = "$HTTPS_PORT" ]; then
        echo "ℹ️  Ports unchanged."
        exit 0
    fi

    # --- Preview ---
    echo ""
    gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 \
        "Port change:" \
        "  HTTP:  ${original_http} → ${HTTP_PORT}" \
        "  HTTPS: ${original_https} → ${HTTPS_PORT}"

    if ! $skip_urls && [ "$original_https" != "$HTTPS_PORT" ]; then
        echo ""
        local any_wp=false
        if [ -d "$SITES_DIR" ]; then
            local site_path site_name
            for site_path in "$SITES_DIR"/*; do
                [ -d "$site_path" ] || continue
                [ -f "$site_path/public/wp-config.php" ] || continue
                if ! $any_wp; then
                    echo "The following WordPress sites will have stored URLs updated:"
                    any_wp=true
                fi
                site_name=$(basename "$site_path")
                echo "   • ${site_name}: $(port_url_for "$site_name" "$original_https") → $(port_url_for "$site_name" "$HTTPS_PORT")"
            done
        fi
        if ! $any_wp; then
            echo "(No WordPress sites to update.)"
        fi
    elif $skip_urls; then
        echo ""
        gum style --faint "(--skip-urls: WordPress databases will NOT be updated)"
    fi

    # --- Dry run exits here ---
    if $dry_run; then
        echo ""
        echo "🔍 Dry run: running wp search-replace --dry-run..."
        echo ""
        if ! $skip_urls; then
            if ! update_wp_site_urls_for_port_change "$original_https" "$HTTPS_PORT" --dry-run; then
                url_migration_failed=true
            fi
        fi
        # Revert globals so nothing leaks to the caller
        HTTP_PORT="$original_http"
        HTTPS_PORT="$original_https"
        echo ""
        gum style --faint "Dry run complete. No changes committed."
        if $url_migration_failed; then
            gum style --foreground yellow \
                "⚠️  Dry run completed, but some WordPress URLs could not be checked."
            exit 1
        fi
        exit 0
    fi

    # --- Confirm ---
    echo ""
    if [ "$auto_yes" = false ]; then
        if ! gum confirm "Proceed with the port change?"; then
            # Revert globals so nothing leaks to the caller
            HTTP_PORT="$original_http"
            HTTPS_PORT="$original_https"
            echo "🚫 Cancelled."
            exit 0
        fi
    fi

    # --- Commit ---
    echo ""
    echo "💾 Saving port configuration..."
    config_set HTTP_PORT "$HTTP_PORT"
    config_set HTTPS_PORT "$HTTPS_PORT"

    if ! $skip_urls && [ "$original_https" != "$HTTPS_PORT" ]; then
        echo ""
        echo "🔄 Updating WordPress site URLs..."
        if ! update_wp_site_urls_for_port_change "$original_https" "$HTTPS_PORT"; then
            url_migration_failed=true
        fi
    fi

    echo ""
    regenerate_caddyfile

    echo ""
    plak_site_enable

    echo ""
    gum style --foreground green "✅ Plak is now on ports ${HTTP_PORT} / ${HTTPS_PORT}"
    if [ "$HTTPS_PORT" != "443" ]; then
        gum style --faint "   Dashboard: $(display_url_for plak.localhost)"
    fi
    if $url_migration_failed; then
        gum style --foreground yellow \
            "⚠️  Ports changed, but some WordPress URLs could not be migrated."
        return 1
    fi
}

# Source: commands/site/proxy
# --- Proxy Storage Directory ---
PROXY_DIR="$APP_DIR/proxies"

# --- Helper to get LAN IP (may already exist in main, but define here for safety) ---
get_lan_ip() {
    if [ "$OS" == "macos" ]; then
        ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1"
    else
        hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1"
    fi
}

plak_site_proxy_add() {
    local name=""
    local domain=""
    local target=""
    local tls_mode="internal"
    local force=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-tls)
                tls_mode="none"
                shift
                ;;
            --force|--yes|-y)
                force=true
                shift
                ;;
            *)
                if [ -z "$name" ]; then
                    name="$1"
                elif [ -z "$domain" ]; then
                    domain="$1"
                elif [ -z "$target" ]; then
                    target="$1"
                fi
                shift
                ;;
        esac
    done

    # Without a TTY, gum confirm can't prompt — treat as --force so scripted
    # callers (dashboard, CI) can overwrite safely.
    [ -t 0 ] || force=true

    # Interactive mode if arguments not provided
    if [ -z "$name" ]; then
        echo "📝 Adding a new reverse proxy entry..."
        name=$(gum input --width 0 --placeholder "Proxy name (e.g., opencode)")
    fi

    if [ -z "$name" ]; then
        gum style --foreground red "❌ Error: Proxy name is required."
        exit 1
    fi

    # Validate name (alphanumeric and hyphens only)
    if ! [[ "$name" =~ ^[a-zA-Z0-9-]+$ ]]; then
        gum style --foreground red "❌ Error: Proxy name must contain only letters, numbers, and hyphens."
        exit 1
    fi

    local proxy_file="$PROXY_DIR/$name"

    # Check if proxy already exists
    if [ -f "$proxy_file" ] && ! $force; then
        if ! gum confirm "⚠️ Proxy '$name' already exists. Overwrite?"; then
            echo "🚫 Cancelled."
            exit 0
        fi
    fi

    if [ -z "$domain" ]; then
        domain=$(gum input --width 0 --placeholder "Domain to listen on (e.g., myhost.tailnet.ts.net)")
    fi

    if [ -z "$domain" ]; then
        gum style --foreground red "❌ Error: Domain is required."
        exit 1
    fi

    if [ -z "$target" ]; then
        target=$(gum input --width 0 --placeholder "Target to proxy to (e.g., 127.0.0.1:4096)")
    fi

    if [ -z "$target" ]; then
        gum style --foreground red "❌ Error: Target is required."
        exit 1
    fi

    # Create proxy directory if it doesn't exist
    mkdir -p "$PROXY_DIR"

    # Save the proxy configuration
    cat > "$proxy_file" << EOF
domain=$domain
target=$target
tls=$tls_mode
EOF

    echo "✅ Proxy '$name' created:"
    echo "   Domain: $domain"
    echo "   Target: $target"
    echo "   TLS: $tls_mode"

    regenerate_caddyfile
}

plak_site_proxy_list() {
    echo "🔎 Listing all reverse proxy entries..."
    echo ""

    if [ ! -d "$PROXY_DIR" ] || [ -z "$(ls -A "$PROXY_DIR" 2>/dev/null)" ]; then
        gum style --foreground "yellow" "ℹ️ No proxy entries found."
        echo ""
        echo "Add one with: plak proxy add <name> <domain> <target>"
        exit 0
    fi

    # Print header
    printf "%-15s %-40s %-25s %-10s\n" "NAME" "DOMAIN" "TARGET" "TLS"
    printf "%-15s %-40s %-25s %-10s\n" "----" "------" "------" "---"

    for proxy_file in "$PROXY_DIR"/*; do
        if [ -f "$proxy_file" ]; then
            local name
            name=$(basename "$proxy_file")
            
            local domain=""
            local target=""
            local tls="internal"

            # Read the config file
            while IFS='=' read -r key value; do
                case "$key" in
                    domain) domain="$value" ;;
                    target) target="$value" ;;
                    tls) tls="$value" ;;
                esac
            done < "$proxy_file"

            printf "%-15s %-40s %-25s %-10s\n" "$name" "$domain" "$target" "$tls"
        fi
    done
}

plak_site_proxy_delete() {
    local name=""
    local force=false
    for arg in "$@"; do
        case "$arg" in
            --force|--yes|-y) force=true ;;
            -*)
                gum style --foreground red "❌ Unknown option: $arg"
                echo "Usage: plak proxy delete <name> [--force]"
                exit 1
                ;;
            *) [ -z "$name" ] && name="$arg" ;;
        esac
    done

    if [ -z "$name" ]; then
        # Interactive mode - let user select from existing proxies
        if [ ! -d "$PROXY_DIR" ] || [ -z "$(ls -A "$PROXY_DIR" 2>/dev/null)" ]; then
            gum style --foreground "yellow" "ℹ️ No proxy entries to delete."
            exit 0
        fi

        echo "🗑️ Select a proxy to delete:"
        name=$(ls "$PROXY_DIR" | gum choose)

        if [ -z "$name" ]; then
            echo "🚫 Cancelled."
            exit 0
        fi
    fi

    local proxy_file="$PROXY_DIR/$name"

    if [ ! -f "$proxy_file" ]; then
        gum style --foreground red "❌ Error: Proxy '$name' not found."
        exit 1
    fi

    # Show what will be deleted
    echo "Proxy '$name' configuration:"
    cat "$proxy_file"
    echo ""

    # Non-interactive callers have no TTY; auto-force so scripted deletes work.
    [ -t 0 ] || force=true

    if ! $force; then
        if ! gum confirm "🚨 Are you sure you want to delete proxy '$name'?"; then
            echo "🚫 Deletion cancelled."
            return 0
        fi
    fi
    rm "$proxy_file"
    echo "✅ Proxy '$name' deleted."
    regenerate_caddyfile
}

plak_site_proxy() {
    local action="$1"
    shift 2>/dev/null || true

    case "$action" in
        add)
            plak_site_proxy_add "$@"
            ;;
        list|ls)
            plak_site_proxy_list
            ;;
        delete|rm)
            plak_site_proxy_delete "$@"
            ;;
        *)
            echo "Usage: plak proxy <subcommand>"
            echo ""
            echo "Manage standalone reverse proxy entries in the Caddyfile."
            echo "These are top-level server blocks, useful for exposing local services"
            echo "via Tailscale or other external domains."
            echo ""
            echo "Subcommands:"
            echo "  add <name> <domain> <target>   Add a new reverse proxy entry"
            echo "  list                           List all proxy entries"
            echo "  delete <name>                  Delete a proxy entry"
            echo ""
            echo "Flags:"
            echo "  --no-tls   Disable TLS for this proxy (add only)"
            echo "  --force    Skip confirmation prompts (add overwrite, delete)"
            echo ""
            echo "Examples:"
            echo "  plak proxy add opencode myhost.tailnet.ts.net 127.0.0.1:4096"
            echo "  plak proxy add api api.example.com localhost:3000 --no-tls"
            echo "  plak proxy add api api.example.com localhost:3000 --force"
            echo "  plak proxy list"
            echo "  plak proxy delete opencode --force"
            exit 0
            ;;
    esac
}

# Source: commands/site/pull
# Remove local temporary state and the remote helper/backup on any exit path.
# Remote removal failures are reported with the recoverable location instead of
# silently deleting anything else.
plak_site_pull_cleanup() {
    [ -n "${PLAK_PULL_SSH_CTL:-}" ] && rm -f "$PLAK_PULL_SSH_CTL"
    [ -n "${PLAK_PULL_TMP_DIR:-}" ] && rm -rf "$PLAK_PULL_TMP_DIR"
    plak_remote_transfer_cleanup
}

plak_site_pull() {
    source_config

    # --- UI/Logging Functions ---
    log_step() {
        echo ""
        gum style --bold --foreground "yellow" "➡️  $1"
    }
    log_success() {
        gum style --foreground "green" "✅ $1"
    }
    log_error() {
        gum style --foreground "red" "❌ ERROR: $1" >&2
        exit 1
    }

    # --- Argument Parsing ---
    local site_name="" yes=0 proxy_uploads=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --yes|-y) yes=1; shift 1 ;;
            --proxy-uploads) proxy_uploads=true; shift 1 ;;
            -*) echo "Unknown flag: $1" >&2; exit 1 ;;
            *) site_name="$1"; shift 1 ;;
        esac
    done
    if [ -n "$site_name" ]; then
        plak_multisite_require_single "$SITES_DIR/$site_name.localhost/public" 'Pull' || return 1
    fi

    # Define quiet SSH options to prevent host key warnings. ControlMaster
    # shares a single authenticated connection across every ssh call below
    # so the user enters their password (or unlocks their key) once — the
    # validate, backup, and cleanup steps all piggyback on the first
    # connection instead of re-prompting. The socket lives in a per-run
    # path so parallel plak pull invocations don't collide.
    local ssh_ctl
    ssh_ctl=$(mktemp -u "${TMPDIR:-/tmp}/plak-ssh-XXXXXXXX")
    PLAK_PULL_SSH_CTL="$ssh_ctl"
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ControlMaster=auto -o ControlPath=$ssh_ctl -o ControlPersist=5m"
    # Remove the socket and any transferred remote files on every exit path
    # (success, failure, Ctrl-C). Any orphaned master process times out on its
    # own via ControlPersist.
    trap plak_site_pull_cleanup EXIT

    gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "This tool will guide you through pulling a remote WordPress site into Plak."

    # --- 0. Resolve site_name and remote binding ---
    # Three paths lead to a (site_name, remote_ssh, remote_path) tuple:
    #   (a) site arg given + it has a binding   → use binding, no prompts
    #   (b) site arg given + no binding         → ask for remote info (interactive)
    #   (c) no site arg, bound sites exist      → pre-step picker (interactive)
    #   (d) no site arg, no bound sites         → ask for everything (interactive)
    local remote_ssh remote_path remote_path_q binding

    if [ -n "$site_name" ]; then
        # Validate site exists
        if [ ! -d "$SITES_DIR/$site_name.localhost" ]; then
            log_error "Site '$site_name' does not exist under $SITES_DIR."
        fi

        # Try to use its binding
        binding=$(plak_remote_get_binding "$site_name" 2>/dev/null)
        local binding_rc=$?
        if [ "$binding_rc" -eq 0 ]; then
            remote_ssh="${binding%|*}"
            remote_path="${binding#*|}"
            log_success "Using remote '$remote_ssh' (path: $remote_path)"
        elif [ "$binding_rc" -eq 2 ] || [ "$binding_rc" -eq 3 ]; then
            case "$binding_rc" in
                2) log_error "Site '$site_name' is attached to a remote that no longer exists in $PLAK_SSH_CONFIG. Run 'plak remote edit' or 'plak remote attach' to fix." ;;
                3) log_error "Remote attached to '$site_name' has no remote_path set. Run 'plak remote edit <name>' to set one." ;;
            esac
        else
            # No binding for this site — fall through to manual remote info
            plak_require_gum
            log_step "Site '$site_name' has no remote binding. Choose remote manually."
            log_step "Choose remote server"
            remote_ssh=$(plak_remote_choose_ssh)
            if [ -z "$remote_ssh" ]; then log_error "SSH connection cannot be empty."; fi

            remote_path=$(gum input --width 0 --value "public/" --prompt "Path to WordPress Root: ")
            if [ -z "$remote_path" ]; then log_error "Remote path cannot be empty."; fi
        fi
    else
        # No site arg: scan for bound sites and offer the pre-step
        local bound_sites=()
        for site_dir in "$SITES_DIR"/*.localhost; do
            [ -d "$site_dir" ] || continue
            if [ -f "$site_dir/.remote" ]; then
                bound_sites+=("$(basename "$site_dir" .localhost)")
            fi
        done

        if [ ${#bound_sites[@]} -gt 0 ]; then
            plak_require_gum
            log_step "Bound sites detected"
            local bound_list=""
            for s in "${bound_sites[@]}"; do
                local r p
                r=$(cat "$SITES_DIR/$s.localhost/.remote")
                p=$(plak_remote_get_binding "$s" 2>/dev/null | awk -F'|' '{print $2}')
                if [ -n "$p" ]; then
                    bound_list="${bound_list}${bound_list:+\n}  • ${s}  →  ${r}  (path: ${p})"
                else
                    bound_list="${bound_list}${bound_list:+\n}  • ${s}  →  ${r}  (no path set)"
                fi
            done
            gum style --border normal --margin "0 0 1 2" --padding "0 1" --border-foreground 244 "$bound_list"

            local pre_choice
            pre_choice=$(printf "%s\n%s\n" "Use a bound site" "Specify remote manually" | gum choose)
            if [ "$pre_choice" = "Use a bound site" ]; then
                site_name=$(printf "%s\n" "${bound_sites[@]}" | gum filter --placeholder "Choose bound site")
                [ -n "$site_name" ] || exit 0

                binding=$(plak_remote_get_binding "$site_name")
                local binding_rc=$?
                case "$binding_rc" in
                    0)
                        remote_ssh="${binding%|*}"
                        remote_path="${binding#*|}"
                        log_success "Using remote '$remote_ssh' (path: $remote_path)"
                        ;;
                    2) log_error "Site '$site_name' is attached to a remote that no longer exists in $PLAK_SSH_CONFIG. Run 'plak remote edit' or 'plak remote attach' to fix." ;;
                    3) log_error "Remote attached to '$site_name' has no remote_path set. Run 'plak remote edit <name>' to set one." ;;
                    *) log_error "Could not resolve binding for '$site_name'." ;;
                esac
            fi
        else
            plak_require_gum
        fi
    fi

    # --- 1. Gather Remote Info (only if not already set) ---
    if [ -z "$site_name" ] || [ -z "$remote_ssh" ]; then
        if [ -z "$site_name" ]; then
            log_step "Choose remote server"
            remote_ssh=$(plak_remote_choose_ssh)
            if [ -z "$remote_ssh" ]; then log_error "SSH connection cannot be empty."; fi

            remote_path=$(gum input --width 0 --value "public/" --prompt "Path to WordPress Root: ")
            if [ -z "$remote_path" ]; then log_error "Remote path cannot be empty."; fi
        fi
        # If site_name given but no binding, the prompt block above already ran
    fi
    remote_path_q=$(shell_quote "$remote_path")

    # --- 2. Validate Remote Site and capture source URLs ---
    log_step "Validating remote WordPress site..."
    local remote_home remote_siteurl
    remote_home=$(ssh $ssh_opts $remote_ssh "cd $remote_path_q && wp option get home --skip-plugins --skip-themes 2>/dev/null")
    remote_siteurl=$(ssh $ssh_opts $remote_ssh "cd $remote_path_q && wp option get siteurl --skip-plugins --skip-themes 2>/dev/null")
    local domain
    domain=$(echo "$remote_home" | sed -E 's/https?:\/\/(www\.)?//; s/\/.*//')

    if [[ "$remote_home" != http* ]] || [[ "$remote_siteurl" != http* ]]; then
        log_error "Could not find a valid WordPress site at the specified path. Check your connection details and path."
    fi
    log_success "Found WordPress site: $remote_home"

    # --- 3. Choose Destination (skip if site_name already known) ---
    local dest_path local_url

    if [ -z "$site_name" ]; then
        log_step "Choose a destination for the pulled site"

        local wp_sites=()
        for site_dir in "$SITES_DIR"/*.localhost; do
            if [ -f "$site_dir/public/wp-config.php" ]; then
                wp_sites+=("$(basename "$site_dir" .localhost)")
            fi
        done

        local destination_choice
        destination_choice=$(gum choose "New Site" "${wp_sites[@]}")

        if [ "$destination_choice" == "New Site" ]; then
            local proposed_name
            proposed_name=$(echo "$remote_home" | sed -E 's/https?:\/\/(www\.)?//; s/\/.*//; s/\./-/g')
            site_name=$(gum input --width 0 --value "$proposed_name" --prompt "Enter a name for the new local site: ")
            if [ -z "$site_name" ]; then log_error "Site name cannot be empty."; fi

            log_step "Creating new placeholder site: ${site_name}.localhost"
            "$PLAK_SITE_CMD" add "$site_name"
            if [ $? -ne 0 ]; then log_error "Failed to create placeholder site. Does it already exist?"; fi

        else
            site_name="$destination_choice"
            if [ "$yes" -eq 0 ]; then
                if [ -t 0 ] && plak_command_exists gum; then
                    if ! gum confirm "Are you sure you want to overwrite '${site_name}'? All its files and database content will be replaced."; then
                        echo "🚫 Pull cancelled."
                        exit 0
                    fi
                else
                    log_error "Refusing to overwrite '$site_name' without --yes in non-interactive mode."
                fi
            fi

            log_step "Preparing to overwrite existing site: ${site_name}.localhost"
        fi
    else
        # site_name already known — always overwrite prep (pulling into an existing site)
        if [ "$yes" -eq 0 ]; then
            if [ -t 0 ] && plak_command_exists gum; then
                if ! gum confirm "Are you sure you want to overwrite '${site_name}'? All its files and database content will be replaced."; then
                    echo "🚫 Pull cancelled."
                    exit 0
                fi
            else
                log_error "Refusing to overwrite '$site_name' without --yes in non-interactive mode."
            fi
        fi

        log_step "Preparing to overwrite existing site: ${site_name}.localhost"
    fi

    dest_path="$SITES_DIR/$site_name.localhost/public"
    plak_multisite_require_single "$dest_path" 'Pull' || return 1
    local_url="$(url_for "$site_name.localhost")"

    # Capture both destination URLs while its database is still intact. A new
    # or not-yet-installed placeholder uses Plak's configured local URL as the
    # canonical fallback rather than introducing another source of truth.
    local destination_home destination_siteurl wp_cmd
    wp_cmd=$(get_wp_cmd)
    destination_home=$( (cd "$dest_path" && $wp_cmd option get home --skip-plugins --skip-themes 2>/dev/null) || true)
    destination_siteurl=$( (cd "$dest_path" && $wp_cmd option get siteurl --skip-plugins --skip-themes 2>/dev/null) || true)
    [[ "$destination_home" == http* ]] || destination_home="$local_url"
    [[ "$destination_siteurl" == http* ]] || destination_siteurl="$local_url"

    # --- 4. Transfer a self-contained engine and validate remote tools ---
    log_step "Preparing the transfer engine..."
    local pull_tmp_dir
    pull_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/plak-pull-XXXXXXXX")
    PLAK_PULL_TMP_DIR="$pull_tmp_dir"
    local local_helper="$pull_tmp_dir/plak-go.sh"
    if ! plak_fetch_go_runtime "$local_helper"; then
        log_error "Could not obtain the Plak transfer engine."
    fi

    local remote_helper remote_helper_q
    remote_helper=$(plak_remote_helper_path)
    remote_helper_q=$(shell_quote "$remote_helper")
    PLAK_RT_SSH_OPTS="$ssh_opts"
    PLAK_RT_REMOTE="$remote_ssh"

    log_step "Uploading transfer engine to ${remote_ssh}..."
    if ! ssh $ssh_opts $remote_ssh "cat > $remote_helper_q" < "$local_helper"; then
        log_error "Failed to upload the transfer engine to the remote."
    fi
    plak_remote_track_file "$remote_helper_q"

    log_step "Checking remote tools..."
    local remote_diagnostic
    if ! remote_diagnostic=$(ssh $ssh_opts $remote_ssh "bash $remote_helper_q diagnose --json" 2>/dev/null); then
        log_error "The remote could not run the transfer engine. Check that 'bash' is available."
    fi
    log_success "Remote tools: $remote_diagnostic"
    if ! grep -qE '"unzip":true|"tar":true' <<<"$remote_diagnostic"; then
        log_error "The remote has no archive tool (unzip or tar). Migration cancelled before changing anything."
    fi
    if ! grep -qE '"mysql":true|"mariadb":true' <<<"$remote_diagnostic"; then
        log_error "The remote has no MySQL client (mysql or mariadb). Migration cancelled before changing anything."
    fi
    if ! grep -qE '"mysqldump":true|"mariadb-dump":true' <<<"$remote_diagnostic"; then
        log_error "The remote has no database dump tool (mysqldump or mariadb-dump). Migration cancelled before changing anything."
    fi

    # --- 5. Generate the remote backup and transfer it over SSH ---
    log_step "Generating backup for ${remote_home}..."
    local backup_extra_args=""
    if [ "$proxy_uploads" = true ]; then
        log_success "Uploads will be excluded from the backup and proxied instead."
        backup_extra_args="--exclude=\"wp-content/uploads\""
    fi

    local backup_filename
    backup_filename=$(ssh $ssh_opts $remote_ssh "cd $remote_path_q && bash $remote_helper_q backup . --quiet --format=filename $backup_extra_args" 2>/dev/null | awk 'NF { last=$0 } END { print last }')
    if [[ -z "$backup_filename" || ! "$backup_filename" == *.zip ]]; then
        log_error "Failed to generate a backup on the remote."
    fi
    local remote_backup="$remote_path/$backup_filename"
    local remote_backup_q
    remote_backup_q=$(shell_quote "$remote_backup")
    plak_remote_track_file "$remote_backup_q"
    log_success "Backup created: ${backup_filename}"

    # Download and inspect the archive before go_migrate reaches its database
    # reset. This keeps the existing database recoverable when the download is
    # missing, corrupt, or does not contain a usable SQL export.
    log_step "Downloading and validating backup..."
    local local_backup_path="$pull_tmp_dir/backup.zip"
    if ! ssh $ssh_opts $remote_ssh "cat $remote_backup_q" > "$local_backup_path" 2>/dev/null || [ ! -s "$local_backup_path" ]; then
        log_error "Failed to download the generated backup. The existing database was not changed."
    fi
    local sql_entry
    if ! unzip -tq "$local_backup_path" >/dev/null 2>&1; then
        log_error "The downloaded backup is not a valid ZIP archive. The existing database was not changed."
    fi
    sql_entry=$(unzip -Z1 "$local_backup_path" | awk 'tolower($0) ~ /\.sql$/ { print; exit }' || true)
    if [ -z "$sql_entry" ]; then
        log_error "The downloaded backup does not contain a SQL export. The existing database was not changed."
    fi
    if ! unzip -p "$local_backup_path" "$sql_entry" > "$pull_tmp_dir/database.sql" || [ ! -s "$pull_tmp_dir/database.sql" ]; then
        log_error "The SQL export in the backup is empty or unreadable. The existing database was not changed."
    fi
    if ! grep -Eiq '^[[:space:]]*(CREATE TABLE|INSERT INTO|DROP TABLE)' "$pull_tmp_dir/database.sql"; then
        log_error "The SQL export in the backup does not contain importable table statements. The existing database was not changed."
    fi
    log_success "Backup download and SQL validation complete."

    # --- 6. Restore locally with the same engine file ---
    log_step "Restoring backup to ${site_name}.localhost..."
    if ! (cd "$dest_path" && bash "$local_helper" migrate \
        --url="$local_backup_path" \
        --update-urls \
        --source-home="$remote_home" \
        --source-siteurl="$remote_siteurl" \
        --destination-home="$destination_home" \
        --destination-siteurl="$destination_siteurl"); then
        log_error "The migration script failed to execute correctly."
    fi
    log_success "Restore complete."

    # --- 7. Post-Migration Configuration ---
    log_step "Configuring local site..."
    inject_mu_plugin "$dest_path"

    # --- 8. Add Proxy Directive if Flag is Set ---
    if [ "$proxy_uploads" = true ]; then
        log_step "Adding upload proxy directive..."
        local new_directive
        # Use a heredoc to create the multi-line directive string
        read -r -d '' new_directive << EOM || true
@local_upload {
    path /wp-content/uploads/*
    file {path}
}
handle @local_upload {
    # If the file exists, serve it and stop processing.
    file_server
}

handle /wp-content/uploads/* {
    # Proxy the request to the live site.
    reverse_proxy ${remote_home} {
        header_up Host ${domain}
        flush_interval -1
    }
}
EOM
        # Pipe the new directive into the add command
        echo "$new_directive" | "$PLAK_SITE_CMD" directive add "$site_name"
        log_success "Upload proxy directive added."
    fi

    # --- 9. Finalize ---
    # Local temporary state and the remote helper/backup are removed by the
    # EXIT trap, including on failure and Ctrl-C.
    regenerate_caddyfile

    gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "✨ All done! Your site is ready." "URL: ${local_url}"
}

# Source: commands/site/push
# Remove local temporary state and the remote helper/backup on any exit path.
# Remote removal failures are reported with the recoverable location.
plak_site_push_cleanup() {
    [ -n "${PLAK_PUSH_SSH_CTL:-}" ] && rm -f "$PLAK_PUSH_SSH_CTL"
    [ -n "${PLAK_PUSH_TMP_DIR:-}" ] && rm -rf "$PLAK_PUSH_TMP_DIR"
    [ -n "${PLAK_PUSH_LOCAL_BACKUP:-}" ] && rm -f "$PLAK_PUSH_LOCAL_BACKUP"
    plak_remote_transfer_cleanup
}

plak_site_push() {
    # --- Argument Parsing ---
    local site_name="" yes=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --yes|-y) yes=1; shift 1 ;;
            -*) echo "Unknown flag: $1" >&2; exit 1 ;;
            *) site_name="$1"; shift 1 ;;
        esac
    done
    if [ -n "$site_name" ]; then
        plak_multisite_require_single "$SITES_DIR/$site_name.localhost/public" 'Push' || return 1
    fi

    # --- UI/Logging Functions ---
    log_step() {
        echo ""
        gum style --bold --foreground "yellow" "➡️  $1"
    }
    log_success() {
        gum style --foreground "green" "✅ $1"
    }
    log_error() {
        gum style --foreground "red" "❌ ERROR: $1" >&2
        exit 1
    }

    # Define quiet SSH options to prevent host key warnings. ControlMaster
    # shares a single authenticated connection across every ssh call below
    # (validate, upload backup, restore, cleanup) so the user enters their
    # password or unlocks their key once instead of four times.
    local ssh_ctl
    ssh_ctl=$(mktemp -u "${TMPDIR:-/tmp}/plak-ssh-XXXXXXXX")
    PLAK_PUSH_SSH_CTL="$ssh_ctl"
    local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ControlMaster=auto -o ControlPath=$ssh_ctl -o ControlPersist=5m"
    trap plak_site_push_cleanup EXIT

    gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "This tool will guide you through pushing a local Plak site to a remote server."

    # --- 1. Choose Local Site ---
    if [ -z "$site_name" ]; then
        plak_require_gum
        log_step "Choose a local site to push"
        local wp_sites=()
        for site_dir in "$SITES_DIR"/*.localhost; do
            if [ -f "$site_dir/public/wp-config.php" ]; then
                wp_sites+=("$(basename "$site_dir" .localhost)")
            fi
        done

        if [ ${#wp_sites[@]} -eq 0 ]; then
            log_error "No local WordPress sites found to push."
        fi

        site_name=$(printf "%s\n" "${wp_sites[@]}" | gum filter --placeholder "Choose local site to push")
        if [ -z "$site_name" ]; then log_error "No site selected."; fi
    else
        if [ ! -d "$SITES_DIR/$site_name.localhost" ]; then
            log_error "Site '$site_name' does not exist under $SITES_DIR."
        fi
        if [ ! -f "$SITES_DIR/$site_name.localhost/public/wp-config.php" ]; then
            log_error "Site '$site_name' is not a WordPress site (no wp-config.php found)."
        fi
    fi

    local local_path="$SITES_DIR/$site_name.localhost/public"
    plak_multisite_require_single "$local_path" 'Push' || return 1
    local local_home local_siteurl wp_cmd
    wp_cmd=$(get_wp_cmd)
    local_home=$( (cd "$local_path" && $wp_cmd option get home --skip-plugins --skip-themes 2>/dev/null) || true)
    local_siteurl=$( (cd "$local_path" && $wp_cmd option get siteurl --skip-plugins --skip-themes 2>/dev/null) || true)
    if [[ "$local_home" != http* ]] || [[ "$local_siteurl" != http* ]]; then
        log_error "Could not read valid home and siteurl values from the local WordPress site."
    fi

    # --- 2. Gather Remote Info ---
    local remote_ssh remote_path remote_path_q binding
    binding=$(plak_remote_get_binding "$site_name" 2>/dev/null)
    local binding_rc=$?

    if [ "$binding_rc" -eq 0 ]; then
        remote_ssh="${binding%|*}"
        remote_path="${binding#*|}"
        log_success "Using remote '$remote_ssh' (path: $remote_path)"
    else
        case "$binding_rc" in
            2) log_error "Site '$site_name' is attached to a remote that no longer exists in $PLAK_SSH_CONFIG. Run 'plak remote edit' or 'plak remote attach' to fix." ;;
            3) log_error "Remote attached to '$site_name' has no remote_path set. Run 'plak remote edit <name>' to set one." ;;
            *) plak_require_gum
               log_step "Choose remote server"
               remote_ssh=$(plak_remote_choose_ssh)
               if [ -z "$remote_ssh" ]; then log_error "SSH connection cannot be empty."; fi

               remote_path=$(gum input --width 0 --value "public/" --prompt "Path to Remote WordPress Root: ")
               if [ -z "$remote_path" ]; then log_error "Remote path cannot be empty."; fi
               ;;
        esac
    fi
    remote_path_q=$(shell_quote "$remote_path")

    # --- 3. Validate Remote Site and capture destination URLs ---
    log_step "Validating remote WordPress site..."
    local remote_home remote_siteurl
    remote_home=$(ssh $ssh_opts $remote_ssh "cd $remote_path_q && wp option get home --skip-plugins --skip-themes 2>/dev/null")
    remote_siteurl=$(ssh $ssh_opts $remote_ssh "cd $remote_path_q && wp option get siteurl --skip-plugins --skip-themes 2>/dev/null")

    if [[ "$remote_home" != http* ]] || [[ "$remote_siteurl" != http* ]]; then
        log_error "Could not find a valid WordPress site at the specified path. Check your connection details and path."
    fi
    log_success "Found remote site to overwrite: $remote_home"

    # --- 4. Confirmation ---
    if [ "$yes" -eq 0 ]; then
        if [ -t 0 ] && plak_command_exists gum; then
            if ! gum confirm "🚨 Are you sure you want to push '${site_name}' to '${remote_home}'? This will completely overwrite the remote site's files and database."; then
                echo "🚫 Push cancelled."
                exit 0
            fi
        else
            log_error "Refusing to push without --yes in non-interactive mode."
        fi
    fi

    # --- 5. Transfer a self-contained engine and validate remote tools ---
    log_step "Preparing the transfer engine..."
    local push_tmp_dir
    push_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/plak-push-XXXXXXXX")
    PLAK_PUSH_TMP_DIR="$push_tmp_dir"
    local local_helper="$push_tmp_dir/plak-go.sh"
    if ! plak_fetch_go_runtime "$local_helper"; then
        log_error "Could not obtain the Plak transfer engine."
    fi

    local remote_helper remote_helper_q
    remote_helper=$(plak_remote_helper_path)
    remote_helper_q=$(shell_quote "$remote_helper")
    PLAK_RT_SSH_OPTS="$ssh_opts"
    PLAK_RT_REMOTE="$remote_ssh"

    log_step "Uploading transfer engine to ${remote_ssh}..."
    if ! ssh $ssh_opts $remote_ssh "cat > $remote_helper_q" < "$local_helper"; then
        log_error "Failed to upload the transfer engine to the remote."
    fi
    plak_remote_track_file "$remote_helper_q"

    log_step "Checking remote tools..."
    local remote_diagnostic
    if ! remote_diagnostic=$(ssh $ssh_opts $remote_ssh "bash $remote_helper_q diagnose --json" 2>/dev/null); then
        log_error "The remote could not run the transfer engine. Check that 'bash' is available."
    fi
    log_success "Remote tools: $remote_diagnostic"
    if ! grep -qE '"unzip":true|"tar":true' <<<"$remote_diagnostic"; then
        log_error "The remote has no archive tool (unzip or tar). Push cancelled before changing anything."
    fi
    if ! grep -qE '"mysql":true|"mariadb":true' <<<"$remote_diagnostic"; then
        log_error "The remote has no MySQL client (mysql or mariadb). Push cancelled before changing anything."
    fi
    if ! grep -qE '"mysqldump":true|"mariadb-dump":true' <<<"$remote_diagnostic"; then
        log_error "The remote has no database dump tool (mysqldump or mariadb-dump). Push cancelled before changing anything."
    fi

    # --- 6. Perform Local Backup ---
    log_step "Generating local backup for ${site_name}..."
    local backup_filename
    backup_filename=$( (cd "$local_path" && bash "$local_helper" backup . --quiet --format=filename) )
    backup_filename=$(printf '%s\n' "$backup_filename" | awk 'NF { last=$0 } END { print last }')
    local local_backup_path="$local_path/$backup_filename"
    PLAK_PUSH_LOCAL_BACKUP="$local_backup_path"

    if [[ ! -f "$local_backup_path" || ! "$backup_filename" == *".zip" ]]; then
        log_error "Failed to generate local backup."
    fi

    local size
    size=$(ls -lh "$local_backup_path" | awk '{print $5}')
    log_success "Local backup created: ${backup_filename} ($size)"

    # --- 7. Upload Backup ---
    local remote_backup="$remote_path/$backup_filename"
    local remote_backup_q
    remote_backup_q=$(shell_quote "$remote_backup")
    plak_remote_track_file "$remote_backup_q"
    log_step "Uploading backup to remote server..."
    if ! cat "$local_backup_path" | ssh $ssh_opts $remote_ssh "cat > $remote_backup_q"; then
        log_error "Failed to upload backup."
    fi
    log_success "Upload complete."

    # --- 8. Remote Restore ---
    log_step "Restoring backup on remote server..."
    local source_home_q source_siteurl_q destination_home_q destination_siteurl_q
    source_home_q=$(shell_quote "--source-home=$local_home")
    source_siteurl_q=$(shell_quote "--source-siteurl=$local_siteurl")
    destination_home_q=$(shell_quote "--destination-home=$remote_home")
    destination_siteurl_q=$(shell_quote "--destination-siteurl=$remote_siteurl")
    if ! ssh $ssh_opts $remote_ssh "cd $remote_path_q && bash $remote_helper_q migrate --url=$remote_backup_q --update-urls $source_home_q $source_siteurl_q $destination_home_q $destination_siteurl_q"; then
        log_error "The remote migration script failed to execute correctly."
    fi
    log_success "Remote restore complete."

    # --- 9. Finalize ---
    # Local and remote temporary files are removed by the EXIT trap, including
    # on failure and Ctrl-C.
    gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "✨ All done! Your site has been pushed successfully." "Remote URL: ${remote_home}"
}

# Source: commands/site/reload
plak_site_reload() {
    # Auto-heal any root-owned state left over from a pre-1.10 install.
    heal_plak_site_state_ownership
    # Serialize reloads to keep Caddy's admin server healthy. The dashboard
    # fires reload in the background after every site add/delete, so rapid
    # actions can spawn many concurrent plak-reload processes; two concurrent
    # frankenphp reload calls reliably deadlock Caddy's admin endpoint with
    # a 10s shutdown timeout.
    #
    # Strategy: first caller holds the lock and does the work. Subsequent
    # callers touch a "pending" marker and exit immediately. When the holder
    # finishes it re-runs once if the marker is set, so the final state
    # converges on the latest on-disk Sites listing.
    #
    # Implementation note: we use a single lock *file* (not a dir) opened with
    # set -C (noclobber) so the pid is written atomically with the lock's
    # creation. Earlier mkdir + echo > pid left a TOCTOU window where a
    # competing reload could read an empty pid, decide the holder was dead,
    # and stomp the lock — letting 3+ reloads run and race create_gui_file's
    # .tmp files.
    local lock_file="$PLAK_SITE_DIR/.reload.lock"
    local pending="$PLAK_SITE_DIR/.reload.pending"

    acquire_reload_lock() {
        (set -C; echo "$$" > "$lock_file") 2>/dev/null
    }

    if ! acquire_reload_lock; then
        local holder_pid
        holder_pid=$(cat "$lock_file" 2>/dev/null)
        if [ -n "$holder_pid" ] && kill -0 "$holder_pid" 2>/dev/null; then
            # A real holder is running — leave a breadcrumb and bail.
            touch "$pending" 2>/dev/null || true
            return 0
        fi
        # Stale (holder died, or was a pre-1.10 root-owned file). Reclaim,
        # falling back to sudo in case ownership blocks us.
        rm -f "$lock_file" 2>/dev/null || $SUDO_CMD -n rm -f "$lock_file" 2>/dev/null || true
        if ! acquire_reload_lock; then
            # Lost the race to another reclaimer — they've got it.
            touch "$pending" 2>/dev/null || true
            return 0
        fi
    fi

    # Trap for abnormal exits (Ctrl-C, signals). The happy-path cleanup
    # happens at the function end since the trap was observed not firing
    # reliably when plak_site_reload is invoked via shell_exec(…&) from PHP.
    trap 'rm -f "$lock_file" 2>/dev/null; trap - EXIT INT TERM' EXIT INT TERM

    while :; do
        rm -f "$pending"
        create_gui_file
        regenerate_caddyfile
        update_etc_hosts
        [ -f "$pending" ] || break
    done

    # Explicit unlock — belt-and-suspenders with the trap.
    rm -f "$lock_file" 2>/dev/null
    trap - EXIT INT TERM
}

# Source: commands/site/rename
plak_site_rename() {
    local old_name="${1:-}"
    local new_name="${2:-}"

    # --- Validation ---
    if [ -z "$old_name" ] || [ -z "$new_name" ]; then
        gum style --foreground red "❌ Error: Both old and new site names are required."
        echo "Usage: plak rename <old-name> <new-name>"
        exit 1
    fi

    if [ "$old_name" == "$new_name" ]; then
         gum style --foreground red "❌ Error: The new name must be different from the old name."
         exit 1
    fi

    local old_site_dir="$SITES_DIR/$old_name.localhost"
    if [ ! -d "$old_site_dir" ]; then
        gum style --foreground red "❌ Error: Site '$old_name.localhost' not found."
        exit 1
    fi

    # Validate the new_name using the same rules as the 'add' command
    if [[ "$new_name" =~ [^a-z0-9-] ]]; then
        gum style --foreground red "❌ Error: Invalid new site name '$new_name'." "Site names can only contain lowercase letters, numbers, and hyphens."
        exit 1
    fi
    if [[ "$new_name" == -* || "$new_name" == *- ]]; then
        gum style --foreground red "❌ Error: Invalid new site name '$new_name'." "Site names cannot begin or end with a hyphen."
        exit 1
    fi
    for protected_name in $PROTECTED_NAMES; do
        if [ "$new_name" == "$protected_name" ]; then
            gum style --foreground red "❌ Error: '$new_name' is a reserved name. Choose another."
            exit 1
        fi
    done

    local new_site_dir="$SITES_DIR/$new_name.localhost"
    if [ -d "$new_site_dir" ]; then
        gum style --foreground red "❌ Error: A site named '$new_name.localhost' already exists."
        exit 1
    fi
    if [ -f "$old_site_dir/.multisite-mode" ] || { [ -f "$old_site_dir/public/wp-config.php" ] && grep -q MULTISITE "$old_site_dir/public/wp-config.php"; }; then
        local mode
        mode=$(plak_multisite_mode "$old_site_dir/public") || return 1
        if [ "$mode" != single ]; then
            mkdir -p "$PLAK_SITE_DIR/cache" || return 1
            plak_multisite_rename "$old_name" "$new_name"
            return $?
        fi
    fi

    echo "🔄 Renaming '$old_name.localhost' to '$new_name.localhost'..."

    # --- Rename Directory ---
    mv "$old_site_dir" "$new_site_dir"
    echo "   - Directory renamed."

    # --- Handle WordPress Specifics ---
    if [ -f "$new_site_dir/public/wp-config.php" ]; then
        source_config
        
        # Get WP-CLI command (adds --allow-root if running as root)
        local wp_cmd
        wp_cmd=$(get_wp_cmd)
        
        local old_db_name
        old_db_name=$(echo "plak_site_$old_name" | tr -c '[:alnum:]_' '_')
        local new_db_name
        new_db_name=$(echo "plak_site_$new_name" | tr -c '[:alnum:]_' '_')
        local temp_sql_dump
        temp_sql_dump=$(mktemp) || {
            gum style --foreground red "❌ Error: Could not create a temporary file for the database dump."
            mv "$new_site_dir" "$old_site_dir"
            exit 1
        }
        trap 'rm -f "$temp_sql_dump"' EXIT

        echo "   - Backing up old database '$old_db_name'..."
        if ! mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$old_db_name" > "$temp_sql_dump"; then
            gum style --foreground red "❌ Error: Failed to dump the old database. Aborting."
            mv "$new_site_dir" "$old_site_dir" # Revert directory rename
            exit 1
        fi

        echo "   - Creating and importing to new database '$new_db_name'..."
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$new_db_name\`;"
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$new_db_name" < "$temp_sql_dump"

        echo "   - Updating wp-config.php..."
        (cd "$new_site_dir/public" && $wp_cmd config set DB_NAME "$new_db_name" --quiet)

        echo "   - Running search-replace for site URL..."
        (cd "$new_site_dir/public" && $wp_cmd search-replace "$(url_for "$old_name.localhost")" "$(url_for "$new_name.localhost")" --all-tables --skip-plugins --skip-themes --quiet)

        echo "   - Dropping old database '$old_db_name'..."
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "DROP DATABASE IF EXISTS \`$old_db_name\`;"
    fi

    # --- Rename Custom Caddy Directives File ---
    local old_custom_conf_file="$CUSTOM_CADDY_DIR/$old_name.localhost"
    local new_custom_conf_file="$CUSTOM_CADDY_DIR/$new_name.localhost"
    if [ -f "$old_custom_conf_file" ]; then
        mv "$old_custom_conf_file" "$new_custom_conf_file"
        echo "   - Custom Caddy directive file renamed."
    fi

    # --- Reload Server Configuration ---
    regenerate_caddyfile

    gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 "✅ Site renamed successfully!" "New URL: $(display_url_for "$new_name.localhost")"
}

# Source: commands/site/share
# --- Share Command ---
# Creates a temporary public tunnel to share a local site via Cloudflare Quick Tunnels
# Requires cloudflared (installed on-demand if missing)

SHARE_PROXY_PORT=19876

plak_site_share() {
    local print_url_only=false
    local no_install=false
    local positional=()

    for arg in "$@"; do
        case "$arg" in
            --print-url) print_url_only=true ;;
            --no-install) no_install=true ;;
            -h|--help)
                echo "Usage: plak share [<site>] [--print-url] [--no-install]"
                exit 0
                ;;
            *) positional+=("$arg") ;;
        esac
    done

    local site_name="${positional[0]:-}"

    # --- 1. Validate Site ---
    if [ -z "$site_name" ]; then
        # Interactive mode: let user select a site
        local all_sites=()
        for site_dir in "$SITES_DIR"/*.localhost; do
            if [ -d "$site_dir" ]; then
                all_sites+=("$(basename "$site_dir" .localhost)")
            fi
        done

        if [ ${#all_sites[@]} -eq 0 ]; then
            gum style --foreground red "Error: No sites found. Create one with 'plak add <name>'."
            exit 1
        fi

        if [ "$print_url_only" = true ]; then
            gum style --foreground red "Error: --print-url requires a site name (no interactive picker in non-TTY mode)."
            exit 1
        fi

        echo "Select a site to share:"
        site_name=$(gum choose "${all_sites[@]}")

        if [ -z "$site_name" ]; then
            echo "Cancelled."
            exit 0
        fi
    fi
    
    # Normalize site name (remove .localhost suffix if present)
    site_name="${site_name%.localhost}"
    
    local site_dir="$SITES_DIR/${site_name}.localhost"
    
    if [ ! -d "$site_dir" ]; then
        gum style --foreground red "Error: Site '${site_name}.localhost' not found."
        exit 1
    fi
    
    local local_hostname="${site_name}.localhost"
    plak_multisite_require_single "$site_dir/public" 'Quick tunnel sharing' || return 1
    
    # --- 2. Check for cloudflared (install on-demand if missing) ---
    if ! command -v cloudflared &> /dev/null; then
        echo "cloudflared is required for plak share but is not installed."
        echo ""
        
        local install_cmd=""
        local install_name=""
        
        if command -v brew &> /dev/null; then
            install_cmd="brew install cloudflared"
            install_name="Homebrew"
        elif command -v apt-get &> /dev/null; then
            # Debian/Ubuntu - need to add Cloudflare's repo first
            install_cmd="curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null && echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list && sudo apt-get update && sudo apt-get install -y cloudflared"
            install_name="apt"
        elif command -v dnf &> /dev/null; then
            # Fedora/RHEL
            install_cmd="curl -fsSL https://pkg.cloudflare.com/cloudflared-ascii.repo | sudo tee /etc/yum.repos.d/cloudflared.repo && sudo dnf install -y cloudflared"
            install_name="dnf"
        fi
        
        if [ -n "$install_cmd" ]; then
            if [ "$no_install" = true ]; then
                gum style --foreground red "Error: --no-install set but cloudflared is not installed."
                exit 1
            fi
            if [ "$print_url_only" = false ] && [ -t 0 ] && plak_command_exists gum; then
                if gum confirm "Install cloudflared via ${install_name}?"; then
                    echo "Installing cloudflared..."
                    eval "$install_cmd"
                    if ! command -v cloudflared &> /dev/null; then
                        gum style --foreground red "Error: Failed to install cloudflared."
                        exit 1
                    fi
                    echo "cloudflared installed successfully."
                    echo ""
                else
                    gum style --foreground red "Error: cloudflared is required."
                    exit 1
                fi
            else
                # Non-interactive: just install without prompting
                echo "Installing cloudflared via ${install_name}..."
                eval "$install_cmd"
                if ! command -v cloudflared &> /dev/null; then
                    gum style --foreground red "Error: Failed to install cloudflared."
                    exit 1
                fi
            fi
        else
            gum style --foreground red "Error: cloudflared not found."
            echo "Install it from: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
            exit 1
        fi
    fi
    
    # --- 3. Check for Python (needed for the HTTP proxy) ---
    local python_cmd=""
    if command -v python3 &> /dev/null; then
        python_cmd="python3"
    elif command -v python &> /dev/null; then
        python_cmd="python"
    else
        gum style --foreground red "Error: Python is required for plak share."
        exit 1
    fi
    
    # --- 4. Create temp files ---
    local tunnel_output
    tunnel_output=$(mktemp)
    
    # --- 5. Cleanup function ---
    local cleanup_triggered=""
    cleanup() {
        cleanup_triggered=1
        echo ""
        echo "Stopping tunnel..."
        # Kill processes and suppress job termination messages
        if [ -n "$proxy_pid" ]; then
            kill $proxy_pid 2>/dev/null
            wait $proxy_pid 2>/dev/null
        fi
        if [ -n "$tunnel_pid" ]; then
            kill $tunnel_pid 2>/dev/null
            wait $tunnel_pid 2>/dev/null
        fi
        rm -f "$tunnel_output"
        echo "Done."
    }
    trap cleanup EXIT
    
    # --- 6. Display initial message ---
    echo ""
    gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 \
        "Starting public tunnel for ${site_name}" \
        "" \
        "Local: $(display_url_for "${local_hostname}")" \
        "" \
        "Press Ctrl+C to stop sharing."
    echo ""
    
    echo "Starting Cloudflare tunnel..."
    
    # --- 7. Start cloudflared to get the public URL first ---
    # Use --protocol http2 for better compatibility (QUIC can be blocked by firewalls)
    cloudflared tunnel --url http://localhost:${SHARE_PROXY_PORT} \
        --protocol http2 --no-autoupdate > "$tunnel_output" 2>&1 &
    tunnel_pid=$!
    
    # Wait for the URL to appear in the output
    local public_url=""
    local attempts=0
    local max_attempts=30
    
    while [ -z "$public_url" ] && [ $attempts -lt $max_attempts ]; do
        sleep 1
        ((attempts++))
        
        if ! kill -0 $tunnel_pid 2>/dev/null; then
            gum style --foreground red "Error: Cloudflare tunnel failed to start."
            cat "$tunnel_output"
            exit 1
        fi
        
        public_url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$tunnel_output" 2>/dev/null | head -1)
    done
    
    if [ -z "$public_url" ]; then
        gum style --foreground red "Error: Could not get public URL from Cloudflare"
        cat "$tunnel_output"
        exit 1
    fi
    
    # Extract just the hostname from the URL
    local public_host="${public_url#https://}"

    if [ "$print_url_only" = true ]; then
        # Agent mode: print just the URL and exit
        printf '%s\n' "$public_url"
        kill $tunnel_pid 2>/dev/null
        wait $tunnel_pid 2>/dev/null
        kill $proxy_pid 2>/dev/null
        wait $proxy_pid 2>/dev/null
        exit 0
    fi

    gum style --foreground 212 --bold "Public URL: $(plak_terminal_link "$public_url")"
    echo ""
    echo "Share this URL with anyone to give them access to your site."
    echo ""
    
    # --- 8. Start Python HTTP proxy that rewrites URLs ---
    echo "Starting local proxy with URL rewriting..."
    
    $python_cmd - "$local_hostname" "$SHARE_PROXY_PORT" "$public_host" "$HTTPS_PORT" << 'PYTHON_PROXY' &
import sys
import ssl
import re
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import Request, urlopen

TARGET_HOST = sys.argv[1]  # e.g., anchordev.localhost
LISTEN_PORT = int(sys.argv[2])
PUBLIC_HOST = sys.argv[3]  # e.g., random-words.trycloudflare.com
HTTPS_PORT = int(sys.argv[4]) if len(sys.argv) > 4 else 443
TARGET_AUTHORITY = TARGET_HOST if HTTPS_PORT == 443 else f"{TARGET_HOST}:{HTTPS_PORT}"

# Create SSL context that doesn't verify certificates (for self-signed)
ssl_ctx = ssl.create_default_context()
ssl_ctx.check_hostname = False
ssl_ctx.verify_mode = ssl.CERT_NONE

# Content types that should have URL rewriting
REWRITABLE_TYPES = ('text/html', 'text/css', 'application/javascript', 'application/json', 'text/javascript')

class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    
    def log_message(self, format, *args):
        # Log requests in a nice format
        import datetime
        timestamp = datetime.datetime.now().strftime('%H:%M:%S')
        # Get client IP from CF-Connecting-IP (Cloudflare) or X-Forwarded-For
        client_ip = self.headers.get('CF-Connecting-IP',
                    self.headers.get('X-Forwarded-For', self.client_address[0]))
        # If multiple IPs in X-Forwarded-For, take the first (original client)
        if ',' in client_ip:
            client_ip = client_ip.split(',')[0].strip()
        # args[0] is typically "METHOD /path HTTP/1.1", args[1] is status code
        if len(args) >= 2:
            request_line = args[0]
            status_code = args[1]
            # Parse method and path from request line
            parts = request_line.split(' ')
            if len(parts) >= 2:
                method = parts[0]
                path = parts[1]
                # Color code status
                if str(status_code).startswith('2'):
                    status_color = '\033[32m'  # Green
                elif str(status_code).startswith('3'):
                    status_color = '\033[33m'  # Yellow
                elif str(status_code).startswith('4'):
                    status_color = '\033[31m'  # Red
                elif str(status_code).startswith('5'):
                    status_color = '\033[35m'  # Magenta
                else:
                    status_color = '\033[0m'
                reset = '\033[0m'
                dim = '\033[2m'
                print(f"{dim}{timestamp}{reset} {status_color}{status_code}{reset} {client_ip} {method} {path}", flush=True)
                return
        # Fallback for other log messages
        print(format % args, flush=True)
    
    def do_request(self):
        target_url = f"https://{TARGET_AUTHORITY}{self.path}"

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        req = Request(target_url, data=body, method=self.command)

        for key, value in self.headers.items():
            if key.lower() not in ('host', 'connection', 'accept-encoding'):
                req.add_header(key, value)
        req.add_header('Host', TARGET_AUTHORITY)

        try:
            with urlopen(req, context=ssl_ctx, timeout=60) as response:
                response_body = response.read()
                content_type = response.headers.get('Content-Type', '')

                # Rewrite URLs in text responses
                if any(ct in content_type for ct in REWRITABLE_TYPES):
                    try:
                        text = response_body.decode('utf-8')
                        # Replace https://site.localhost[:port] with https://public-url
                        text = text.replace(f'https://{TARGET_AUTHORITY}', f'https://{PUBLIC_HOST}')
                        text = text.replace(f'http://{TARGET_AUTHORITY}', f'https://{PUBLIC_HOST}')
                        # Escaped versions (for JSON)
                        text = text.replace(f'https:\\/\\/{TARGET_AUTHORITY}', f'https:\\/\\/{PUBLIC_HOST}')
                        response_body = text.encode('utf-8')
                    except:
                        pass  # If decode fails, send original
                
                self.send_response(response.status)
                for key, value in response.headers.items():
                    if key.lower() not in ('transfer-encoding', 'connection', 'content-length', 'content-encoding'):
                        self.send_header(key, value)
                self.send_header('Content-Length', len(response_body))
                self.end_headers()
                self.wfile.write(response_body)
        except Exception as e:
            error_msg = f"Proxy Error: {e}".encode()
            self.send_response(502)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', len(error_msg))
            self.end_headers()
            self.wfile.write(error_msg)
    
    def do_GET(self): self.do_request()
    def do_POST(self): self.do_request()
    def do_PUT(self): self.do_request()
    def do_DELETE(self): self.do_request()
    def do_HEAD(self): self.do_request()
    def do_OPTIONS(self): self.do_request()
    def do_PATCH(self): self.do_request()

class QuietHTTPServer(HTTPServer):
    """HTTPServer that silently ignores connection reset errors."""
    def handle_error(self, request, client_address):
        # Silently ignore connection reset errors (browser closed connection)
        import sys
        exc_type = sys.exc_info()[0]
        if exc_type in (ConnectionResetError, BrokenPipeError):
            return
        # For other errors, use default handling
        super().handle_error(request, client_address)

server = QuietHTTPServer(('127.0.0.1', LISTEN_PORT), ProxyHandler)
server.serve_forever()
PYTHON_PROXY
    proxy_pid=$!
    
    sleep 1
    
    if ! kill -0 $proxy_pid 2>/dev/null; then
        gum style --foreground red "Error: Failed to start local proxy."
        exit 1
    fi
    
    echo "Tunnel is active. Press Ctrl+C to stop."
    echo ""
    
    # Monitor tunnel connection - check every 5 seconds
    while kill -0 $tunnel_pid 2>/dev/null; do
        sleep 5
    done
    
    # Tunnel process ended - check if it was unexpected
    if [ -z "$cleanup_triggered" ]; then
        echo ""
        gum style --foreground yellow "Cloudflare tunnel disconnected."
    fi
}

# Source: commands/site/snapshot
plak_site_snapshot_usage() {
    cat <<'HELP'
Usage:
  plak snapshot <site> create [--note <text>] [--json]
  plak snapshot <site> list [--json]
  plak snapshot <site> restore <id> [--yes]
  plak snapshot <site> delete <id> [--yes]
  plak snapshot <site> export <id> [--output <path>]

Snapshots are local recovery points of a site's files and database. Static
(plain) sites include only their files.
HELP
}

# Resolve the site directory or fail before any work is done.
plak_snapshot_require_site() {
    local site="$1"
    if ! plak_validate_site_name "$site"; then
        echo "Error: invalid site name '$site'." >&2
        return 1
    fi
    local site_dir="$SITES_DIR/$site.localhost"
    if [ ! -d "$site_dir" ]; then
        echo "Error: site '$site.localhost' not found." >&2
        return 1
    fi
    printf '%s' "$site_dir"
}

plak_snapshot_site_is_wordpress() {
    [ -f "$1/public/wp-config.php" ]
}

plak_snapshot_create() {
    local site="$1"
    shift
    local note="" json=false
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --note)
                note="${2:-}"
                [ "$#" -ge 2 ] || { echo "Error: --note requires a value." >&2; return 1; }
                shift 2
                ;;
            --note=*)
                note="${1#*=}"
                shift
                ;;
            --json)
                json=true
                shift
                ;;
            *)
                echo "Error: unknown snapshot create argument '$1'." >&2
                return 1
                ;;
        esac
    done

    local site_dir
    site_dir=$(plak_snapshot_require_site "$site") || return 1

    local snapshots_dir id snapshot_dir
    snapshots_dir=$(plak_snapshot_dir "$site")
    id=$(plak_snapshot_new_id)
    snapshot_dir="$snapshots_dir/$id"
    mkdir -p "$snapshot_dir" || return 1

    local site_type="wordpress"
    plak_snapshot_site_is_wordpress "$site_dir" || site_type="plain"

    if ! tar -czf "$snapshot_dir/files.tar.gz" -C "$site_dir/public" . 2>/dev/null; then
        rm -rf "$snapshot_dir"
        echo "Error: could not archive site files." >&2
        return 1
    fi

    if [ "$site_type" = wordpress ]; then
        source_config
        local wp_cmd
        wp_cmd=$(get_wp_cmd)
        if ! (cd "$site_dir/public" && "$wp_cmd" db export "$snapshot_dir/database.sql" --add-drop-table --skip-plugins --skip-themes >/dev/null 2>&1); then
            rm -rf "$snapshot_dir"
            echo "Error: database export failed; snapshot was not published as complete." >&2
            return 1
        fi
        if [ ! -s "$snapshot_dir/database.sql" ]; then
            rm -rf "$snapshot_dir"
            echo "Error: database export is empty; snapshot was not published." >&2
            return 1
        fi
    fi

    {
        printf 'id=%s\n' "$id"
        printf 'site=%s\n' "$site"
        printf 'created=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'type=%s\n' "$site_type"
        printf 'note=%s\n' "$note"
    } > "$snapshot_dir/meta"

    if [ "$json" = true ]; then
        printf '{"id":"%s","site":"%s","type":"%s","note":"%s"}\n' "$id" "$site" "$site_type" "$note"
    else
        echo "Created snapshot $id for $site.localhost."
    fi
}

plak_snapshot_list() {
    local site="$1"
    shift
    local json=false
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --json) json=true; shift ;;
            *) echo "Error: unknown snapshot list argument '$1'." >&2; return 1 ;;
        esac
    done

    plak_snapshot_require_site "$site" >/dev/null || return 1

    local dir id first=true
    dir=$(plak_snapshot_dir "$site")
    if [ "$json" = true ]; then
        printf '['
        while IFS= read -r id; do
            [ -n "$id" ] || continue
            local created type note files_size db_size
            created=$(plak_snapshot_meta "$dir/$id" created || true)
            type=$(plak_snapshot_meta "$dir/$id" type || true)
            note=$(plak_snapshot_meta "$dir/$id" note || true)
            files_size="0"
            [ -f "$dir/$id/files.tar.gz" ] && files_size=$(stat -c '%s' "$dir/$id/files.tar.gz" 2>/dev/null || stat -f '%z' "$dir/$id/files.tar.gz" 2>/dev/null || echo 0)
            db_size="0"
            [ -f "$dir/$id/database.sql" ] && db_size=$(stat -c '%s' "$dir/$id/database.sql" 2>/dev/null || stat -f '%z' "$dir/$id/database.sql" 2>/dev/null || echo 0)
            if [ "$first" = true ]; then first=false; else printf ','; fi
            printf '{"id":"%s","created":"%s","type":"%s","note":"%s","files_bytes":%s,"db_bytes":%s}' \
                "$id" "$created" "$type" "$note" "$files_size" "$db_size"
        done < <(plak_snapshot_list_ids "$site")
        printf ']\n'
        return 0
    fi

    if ! plak_snapshot_list_ids "$site" | grep -q .; then
        echo "No snapshots found for $site.localhost."
        return 0
    fi
    printf '%-32s %-20s %-10s %s\n' "ID" "CREATED" "TYPE" "NOTE"
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        local created type note
        created=$(plak_snapshot_meta "$dir/$id" created || true)
        type=$(plak_snapshot_meta "$dir/$id" type || true)
        note=$(plak_snapshot_meta "$dir/$id" note || true)
        printf '%-32s %-20s %-10s %s\n' "$id" "$created" "$type" "$note"
    done < <(plak_snapshot_list_ids "$site")
}

plak_snapshot_delete() {
    local site="$1" id="$2"
    shift 2 || true
    local yes=false
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --yes|-y) yes=true; shift ;;
            *) echo "Error: unknown snapshot delete argument '$1'." >&2; return 1 ;;
        esac
    done

    plak_snapshot_require_site "$site" >/dev/null || return 1
    if ! plak_snapshot_valid_id "$id"; then
        echo "Error: invalid snapshot id '$id'." >&2
        return 1
    fi
    local dir
    dir=$(plak_snapshot_dir "$site")/$id
    if [ ! -d "$dir" ]; then
        echo "Error: snapshot '$id' not found for $site.localhost." >&2
        return 1
    fi

    if [ "$yes" = false ] && [ -t 0 ] && plak_command_exists gum; then
        if ! gum confirm "Delete snapshot $id for $site.localhost?"; then
            echo "Deletion cancelled."
            return 0
        fi
    elif [ "$yes" = false ]; then
        echo "Error: refusing to delete snapshot '$id' without --yes in non-interactive mode." >&2
        return 1
    fi

    rm -rf "$dir"
    echo "Deleted snapshot $id."
}

# Replace a site's database with the given SQL dump using the portable
# recoverable contract: keep a pre-reset snapshot, import, and roll back on
# failure. Recovery material survives a failed rollback for a later retry.
plak_snapshot_replace_database() {
    local site_dir="$1" dump="$2"
    local wp_cmd
    wp_cmd=$(get_wp_cmd)

    local recovery_dir="$site_dir/private/restore_recovery"
    local recovery_state="$recovery_dir/state"
    local recovery_dump="$recovery_dir/pre-reset-backup.sql"

    if [ -f "$recovery_state" ]; then
        echo "Error: an interrupted restore exists at $recovery_dir. Resolve it before retrying." >&2
        return 1
    fi

    mkdir -p "$recovery_dir" || return 1
    if ! (cd "$site_dir/public" && "$wp_cmd" db export "$recovery_dump" --add-drop-table --skip-plugins --skip-themes >/dev/null 2>&1); then
        rm -rf "$recovery_dir"
        echo "Error: could not snapshot the current database before restoring." >&2
        return 1
    fi
    {
        printf 'recovery_dump=%s\n' "$recovery_dump"
        printf 'stage=restoring\n'
    } > "$recovery_state"

    if ! (cd "$site_dir/public" && "$wp_cmd" db reset --yes --skip-plugins --skip-themes >/dev/null 2>&1); then
        echo "Error: database reset failed; recovery material kept at $recovery_dir." >&2
        return 1
    fi

    if (cd "$site_dir/public" && "$wp_cmd" db import "$dump" --skip-plugins --skip-themes >/dev/null 2>&1); then
        rm -rf "$recovery_dir"
        return 0
    fi

    echo "Database import failed; rolling back to the pre-restore state..."
    if (cd "$site_dir/public" && "$wp_cmd" db reset --yes --skip-plugins --skip-themes >/dev/null 2>&1 &&
        "$wp_cmd" db import "$recovery_dump" --skip-plugins --skip-themes >/dev/null 2>&1); then
        rm -rf "$recovery_dir"
        echo "The current database was restored to its pre-restore state."
    else
        echo "Error: automatic rollback failed; recovery material kept at $recovery_dir." >&2
    fi
    return 1
}

# Restore from a snapshot. A safety snapshot of the current state is taken
# first; the database step uses the recoverable contract.
plak_snapshot_restore() {
    local site="$1" id="$2"
    shift 2 || true
    local yes=false
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --yes|-y) yes=true; shift ;;
            *) echo "Error: unknown snapshot restore argument '$1'." >&2; return 1 ;;
        esac
    done

    local site_dir
    site_dir=$(plak_snapshot_require_site "$site") || return 1
    plak_multisite_require_single "$site_dir/public" 'Snapshot restore' || return 1
    if ! plak_snapshot_valid_id "$id"; then
        echo "Error: invalid snapshot id '$id'." >&2
        return 1
    fi
    local snapshot_dir
    snapshot_dir=$(plak_snapshot_dir "$site")/$id
    if [ ! -d "$snapshot_dir" ]; then
        echo "Error: snapshot '$id' not found for $site.localhost." >&2
        return 1
    fi

    if [ "$yes" = false ] && [ -t 0 ] && plak_command_exists gum; then
        if ! gum confirm "Restore $site.localhost from snapshot $id? Current files and database will be replaced."; then
            echo "Restore cancelled."
            return 0
        fi
    elif [ "$yes" = false ]; then
        echo "Error: refusing to restore without --yes in non-interactive mode." >&2
        return 1
    fi

    echo "Keeping a safety snapshot of the current state..."
    plak_snapshot_keep_safety "$site" || {
        echo "Error: could not keep a safety snapshot; restore aborted." >&2
        return 1
    }

    echo "Restoring files from snapshot $id..."
    if ! tar -xzf "$snapshot_dir/files.tar.gz" -C "$site_dir/public"; then
        echo "Error: failed to restore files; the safety snapshot was kept." >&2
        return 1
    fi

    if [ -f "$snapshot_dir/database.sql" ]; then
        echo "Restoring database from snapshot $id..."
        source_config
        # The Go engine is not available in the CLI shell, so the same portable
        # contract is applied here with the local WP-CLI: snapshot the current
        # database, reset, import, and roll back on failure.
        if ! plak_snapshot_replace_database "$site_dir" "$snapshot_dir/database.sql"; then
            echo "Error: database restore failed; the safety snapshot was kept." >&2
            return 1
        fi
    fi

    regenerate_caddyfile
    echo "Restored $site.localhost from snapshot $id."
}

plak_snapshot_export() {
    local site="$1" id="$2"
    shift 2 || true
    local output=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --output)
                output="${2:-}"
                [ "$#" -ge 2 ] || { echo "Error: --output requires a value." >&2; return 1; }
                shift 2
                ;;
            --output=*)
                output="${1#*=}"
                shift
                ;;
            *)
                echo "Error: unknown snapshot export argument '$1'." >&2
                return 1
                ;;
        esac
    done

    plak_snapshot_require_site "$site" >/dev/null || return 1
    plak_snapshot_valid_id "$id" || { echo "Error: invalid snapshot id '$id'." >&2; return 1; }
    local snapshot_dir
    snapshot_dir=$(plak_snapshot_dir "$site")/$id
    if [ ! -d "$snapshot_dir" ]; then
        echo "Error: snapshot '$id' not found." >&2
        return 1
    fi

    if [ -z "$output" ]; then
        output="./plak-snapshot-$site-$id.zip"
    fi

    if ! (cd "$snapshot_dir" && zip -qr "$(cd "$(dirname "$output")" && pwd -P)/$(basename "$output")" .); then
        echo "Error: failed to export snapshot." >&2
        return 1
    fi
    echo "Exported snapshot to $output"
}

plak_site_snapshot() {
    local site="${1:-}"
    if [ -z "$site" ] || [ "$site" = "help" ] || [ "$site" = "--help" ] || [ "$site" = "-h" ]; then
        plak_site_snapshot_usage
        return 0
    fi
    shift || true
    local action="${1:-}"
    [ "$#" -gt 0 ] && shift

    case "$action" in
        create) plak_snapshot_create "$site" "$@" ;;
        list) plak_snapshot_list "$site" "$@" ;;
        restore) plak_snapshot_restore "$site" "${1:-}" "${@:2}" ;;
        delete) plak_snapshot_delete "$site" "${1:-}" "${@:2}" ;;
        export) plak_snapshot_export "$site" "${1:-}" "${@:2}" ;;
        *)
            echo "Error: unknown snapshot action '${action:-}'." >&2
            plak_site_snapshot_usage >&2
            return 1
            ;;
    esac
}

# Source: commands/site/status
plak_site_status() {
    local json_mode=false
    for arg in "$@"; do
        case "$arg" in
            --json) json_mode=true ;;
            -h|--help)
                echo "Usage: plak status [--json]"
                exit 0
                ;;
        esac
    done

    if [ "$json_mode" = false ]; then
        echo "🔎 Checking Plak service status..."
    fi

    local caddy_running=false
    local mariadb_running=false
    local mailpit_running=false

    # Probe Caddy's admin endpoint. The prior pidfile check fell over on
    # Linux where sudo frankenphp start left the pidfile root-owned (0600),
    # so the user reading it as austin got "" and the status falsely showed
    # Stopped. The TCP probe is readable by any local user.
    if is_caddy_running; then
        caddy_running=true
    fi

    # Check MariaDB and Mailpit status on MacOS
    if [ "$OS" == "macos" ]; then
        if brew services list 2>/dev/null | grep -q "mariadb.*started"; then
            mariadb_running=true
        fi
        if launchctl list 2>/dev/null | grep -q "com.plak.mailpit"; then
            mailpit_running=true
        fi
    fi

    # Check MariaDB and Mailpit status on Linux
    if [ "$OS" == "linux" ]; then
        # Check all possible MariaDB service names
        local mariadb_service
        mariadb_service=$(get_mariadb_service_name)
        if systemctl is-active --quiet "$mariadb_service" 2>/dev/null; then
            mariadb_running=true
        fi
        if systemctl is-active --quiet mailpit 2>/dev/null; then
            mailpit_running=true
        fi
    fi

    if [ "$json_mode" = true ]; then
        local caddy_s="stopped"
        local mariadb_s="stopped"
        local mailpit_s="stopped"
        [ "$caddy_running" = true ] && caddy_s="running"
        [ "$mariadb_running" = true ] && mariadb_s="running"
        [ "$mailpit_running" = true ] && mailpit_s="running"
        printf '{"caddy":"%s","mariadb":"%s","mailpit":"%s","dashboard":"%s","all_running":%s}\n' \
            "$caddy_s" "$mariadb_s" "$mailpit_s" \
            "$(url_for plak.localhost)" \
            "$([ "$caddy_running" = true ] && [ "$mariadb_running" = true ] && [ "$mailpit_running" = true ] && echo true || echo false)"
        return 0
    fi

    local caddy_status="❌ Stopped"
    local mariadb_status="❌ Stopped"
    local mailpit_status="❌ Stopped"
    [ "$caddy_running" = true ] && caddy_status="✅ Running"
    [ "$mariadb_running" = true ] && mariadb_status="✅ Running"
    [ "$mailpit_running" = true ] && mailpit_status="✅ Running"

    echo ""
    echo "  Caddy Server: $caddy_status"
    echo "  MariaDB:      $mariadb_status"
    echo "  Mailpit:      $mailpit_status"
    echo ""

    if [[ "$caddy_status" == "✅ Running" && "$mariadb_status" == "✅ Running" && "$mailpit_status" == "✅ Running" ]]; then
        gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 \
            "✅ All services are running" \
            "Dashboard: $(url_for plak.localhost)" \
            "Adminer:   $(url_for db.plak.localhost)" \
            "Mailpit:   $(url_for mail.plak.localhost)"
    else
        gum style --border normal --margin "1" --padding "1 2" --border-foreground "yellow" \
            "⚠️  Some services are stopped." \
            "Run 'plak enable' to start them." \
            "Dashboard: $(url_for plak.localhost)"
    fi

    if [ "$HTTPS_PORT" != "443" ]; then
        echo ""
        gum style --foreground yellow \
            "Port note: Plak HTTPS is configured on ${HTTPS_PORT}." \
            "Use $(url_for plak.localhost), not https://plak.localhost/."
    fi

    # Show WSL-specific info
    if [ "$IS_WSL" = true ]; then
        local wsl_ip
        wsl_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        echo ""
        echo "  WSL IP: $wsl_ip"
    fi
}

# Source: commands/site/tailscale
# --- Tailscale Configuration ---
TAILSCALE_CONFIG="$APP_DIR/tailscale"

plak_site_tailscale_enable() {
    local hostname="${1:-}"

    # Try to auto-detect hostname if not provided
    if [ -z "$hostname" ]; then
        if command -v tailscale &> /dev/null; then
            echo "🔎 Detecting Tailscale hostname..."
            # Extract DNSName from Self section (handles both "key": "value" and "key":"value" formats)
            hostname=$(tailscale status --json 2>/dev/null | grep -m1 '"DNSName"' | sed 's/.*"DNSName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | sed 's/\.$//')
        fi
    fi

    # Interactive mode if still no hostname
    if [ -z "$hostname" ]; then
        if [ ! -t 0 ] || ! plak_command_exists gum; then
            gum style --foreground red "❌ Error: Could not auto-detect Tailscale hostname. Pass it explicitly: plak tailscale enable <hostname>"
            exit 1
        fi
        echo "📝 Enter your Tailscale machine hostname"
        echo "   (e.g., mycomputer.tail1234.ts.net)"
        hostname=$(gum input --width 0 --placeholder "your-machine.tailnet.ts.net")
    fi

    if [ -z "$hostname" ]; then
        gum style --foreground red "❌ Error: Tailscale hostname is required."
        exit 1
    fi

    # Remove any trailing dot
    hostname="${hostname%.}"

    # Validate it looks like a hostname
    if [[ ! "$hostname" =~ \. ]]; then
        gum style --foreground red "❌ Error: Invalid hostname. Expected format: machine.tailnet.ts.net"
        exit 1
    fi

    # Save the configuration
    mkdir -p "$APP_DIR"
    echo "$hostname" > "$TAILSCALE_CONFIG"

    echo "✅ Tailscale access enabled!"
    echo "   Hostname: $hostname"
    echo ""
    echo "   Regenerating Caddyfile with port-based routing..."
    echo ""
    regenerate_caddyfile
    
    echo ""
    echo "   Run 'plak tailscale status' to see all URLs."
}

plak_site_tailscale_disable() {
    if [ -f "$TAILSCALE_CONFIG" ]; then
        rm "$TAILSCALE_CONFIG"
        
        # Clean up port files
        if [ -d "$SITES_DIR" ]; then
            for site_path in "$SITES_DIR"/*; do
                if [ -f "$site_path/tailscale_port" ]; then
                    rm "$site_path/tailscale_port"
                fi
            done
        fi
        
        echo "✅ Tailscale access disabled."
        regenerate_caddyfile
    else
        echo "ℹ️ Tailscale access is not currently enabled."
    fi
}

plak_site_tailscale_status() {
    echo "🔎 Tailscale Access Status"
    echo ""
    
    if [ -f "$TAILSCALE_CONFIG" ]; then
        local hostname
        hostname=$(cat "$TAILSCALE_CONFIG")
        gum style --foreground green "✅ Enabled"
        echo "   Hostname: $hostname"
        echo ""
        echo "   Your sites are accessible at:"
        
        if [ -d "$SITES_DIR" ]; then
            for site_path in "$SITES_DIR"/*; do
                if [ -d "$site_path" ]; then
                    local site_name
                    site_name=$(basename "$site_path" | sed 's/\.localhost$//')
                    local port=""
                    if [ -f "$site_path/tailscale_port" ]; then
                        port=$(cat "$site_path/tailscale_port")
                    fi
                    if [ -n "$port" ]; then
                        echo "   - $(plak_terminal_link "https://${hostname}:${port}")  (${site_name})"
                    fi
                fi
            done
        fi
        
        echo ""
        echo "   Global services:"
        echo "   - $(plak_terminal_link "https://${hostname}:9900")  (Dashboard)"
        echo "   - $(plak_terminal_link "https://${hostname}:9901")  (Mailpit)"
        echo "   - $(plak_terminal_link "https://${hostname}:9902")  (Adminer)"
    else
        gum style --foreground yellow "❌ Disabled"
        echo ""
        echo "   Enable with: plak tailscale enable [hostname]"
    fi
}

plak_site_tailscale() {
    local action="$1"
    shift 2>/dev/null || true

    case "$action" in
        enable)
            plak_site_tailscale_enable "$@"
            ;;
        disable)
            plak_site_tailscale_disable
            ;;
        status)
            plak_site_tailscale_status
            ;;
        *)
            echo "Usage: plak tailscale <subcommand>"
            echo ""
            echo "Expose all Plak sites to your Tailscale network via port-based routing."
            echo "This allows devices on your Tailnet (like your iPhone) to access"
            echo "your local development sites."
            echo ""
            echo "Your Tailscale hostname is automatically detected when you run 'enable'."
            echo "Each site gets a unique port (starting at 9001), so you can access them at:"
            echo "  https://<your-tailscale-hostname>:<port>"
            echo ""
            echo "Subcommands:"
            echo "  enable     Enable Tailscale access (auto-detects hostname)"
            echo "  disable    Disable Tailscale access"
            echo "  status     Show current Tailscale configuration and URLs"
            echo ""
            echo "Examples:"
            echo "  plak tailscale enable"
            echo "  plak tailscale status"
            echo "  plak tailscale disable"
            exit 0
            ;;
    esac
}

# Source: commands/site/trust
# Locate the current Caddy local root certificate, preferring the one Caddy
# keeps in the user profile and falling back to the system-trust copy.
plak_site_caddy_root_cert() {
    local root_cert
    root_cert=$(find "${XDG_DATA_HOME:-$HOME/.local/share}/caddy/pki/authorities/local" \
        -maxdepth 1 -name 'root.crt' 2>/dev/null | head -1)
    if [ -z "$root_cert" ]; then
        root_cert=$(find /usr/local/share/ca-certificates \
            -maxdepth 1 -name 'Caddy_Local_Authority*.crt' 2>/dev/null | head -1)
    fi
    [ -n "$root_cert" ] && [ -r "$root_cert" ] && printf '%s\n' "$root_cert"
}

# Browser databases are always updated as the invoking user, never via sudo.
plak_site_trust_nss() {
    local root_cert="$1" db profile prefix failed=0 discovery
    local -a roots=()
    for profile in "$HOME/.pki" "${XDG_DATA_HOME:-$HOME/.local/share}/pki" "$HOME/.mozilla/firefox" "$HOME/snap" "$HOME/.var/app"; do
        [ ! -d "$profile" ] || roots+=("$profile")
    done
    [ "${#roots[@]}" -gt 0 ] || return 0
    discovery=$(mktemp) || return 1
    if ! find "${roots[@]}" -type f \( -name cert9.db -o -name cert8.db \) -print0 > "$discovery"; then
        plak_ui_error 'Some browser profile directories could not be inspected.'; failed=1
    fi
    local -a profiles=()
    while IFS= read -r -d '' db; do
        profile=$(dirname "$db")
        local seen=false item
        for item in "${profiles[@]}"; do [ "$item" != "$profile" ] || seen=true; done
        [ "$seen" = true ] || profiles+=("$profile")
    done < "$discovery"
    rm -f "$discovery"
    [ "${#profiles[@]}" -gt 0 ] || return "$failed"
    command -v certutil >/dev/null 2>&1 || { plak_ui_error 'certutil missing: browser profiles were not updated. Install libnss3-tools / nss-tools.'; return 1; }
    for profile in "${profiles[@]}"; do
        prefix=dbm
        [ ! -f "$profile/cert9.db" ] || prefix=sql
        echo "   - Trusting in $profile"
        # Replace only Plak/Caddy-managed nicknames; retain unrelated roots.
        for item in 'Plak Local Authority' 'Caddy Local Authority'; do
            if certutil -L -d "$prefix:$profile" -n "$item" >/dev/null 2>&1; then
                if ! certutil -D -d "$prefix:$profile" -n "$item"; then
                    plak_ui_error "Could not remove stale CA from $profile"; failed=1
                fi
            fi
        done
        if ! certutil -A -d "$prefix:$profile" -n 'Plak Local Authority' -t 'C,,' -i "$root_cert"; then
            plak_ui_error "Browser profile not updated: $profile"; failed=1
        fi
    done
    return "$failed"
}

# Replace Plak's block and migrate legacy unmarked Caddy roots. Real PEM files
# contain no readable subject name, so grep-only idempotence was insufficient.
plak_site_trust_linuxbrew_bundles() {
    local brew_prefix="$1" root_cert="$2"
    local bundle failed=0 tmp line certificate subject capturing=false skipping=false
    for bundle in \
        "$brew_prefix/etc/ca-certificates/cert.pem" \
        "$brew_prefix/opt/openssl@3/etc/openssl@3/cert.pem" \
        "$brew_prefix/etc/openssl@3/cert.pem"; do
        [ -f "$bundle" ] || continue
        if [ -L "$bundle" ]; then
            # This shared resolver handles BSD/GNU readlink without inspecting
            # PHP content, and preserves the original bundle symlink.
            bundle=$(plak_wp_realpath "$bundle") || { plak_ui_error 'Could not resolve Homebrew CA bundle symlink.'; failed=1; continue; }
        fi
        command -v openssl >/dev/null 2>&1 || { plak_ui_error "openssl missing; CA bundle not updated: $bundle"; failed=1; continue; }
        tmp=$(mktemp "$bundle.plak.XXXXXX") || { failed=1; continue; }
        cp -p "$bundle" "$tmp" || { rm -f "$tmp"; failed=1; continue; }
        certificate=""; capturing=false; skipping=false
        if ! (
            while IFS= read -r line || [ -n "$line" ]; do
                if [ "$line" = '# BEGIN PLAK LOCAL CA' ]; then skipping=true; continue; fi
                if [ "$line" = '# END PLAK LOCAL CA' ]; then skipping=false; continue; fi
                [ "$skipping" = false ] || continue
                if [ "$line" = '-----BEGIN CERTIFICATE-----' ]; then certificate=""; capturing=true; fi
                if [ "$capturing" = true ]; then
                    certificate+="$line"$'\n'
                    if [ "$line" = '-----END CERTIFICATE-----' ]; then
                        subject=$(printf '%s' "$certificate" | openssl x509 -noout -subject 2>/dev/null) || subject=""
                        if [[ "$subject" != *'Caddy Local Authority'* && "$certificate" != *'Caddy Local Authority'* ]]; then printf '%s' "$certificate"; fi
                        capturing=false
                    fi
                else printf '%s\n' "$line"; fi
            done < "$bundle"
            # A malformed trailing certificate must not be silently discarded.
            [ "$capturing" = false ] || printf '%s' "$certificate"
            printf '\n# BEGIN PLAK LOCAL CA\n'
            cat "$root_cert" || exit 1
            printf '\n# END PLAK LOCAL CA\n'
        ) > "$tmp"; then
            rm -f "$tmp"; failed=1; continue
        fi
        if mv "$tmp" "$bundle"; then
            echo "   - Added Caddy root to Homebrew CA bundle: $bundle"
        else
            rm -f "$tmp"
            gum style --foreground yellow "⚠️ Could not update Homebrew CA bundle: $bundle"
            failed=1
        fi
    done
    return "$failed"
}

plak_site_trust() {
    echo "🔐 Installing Plak's local root certificate..."
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
        plak_ui_error 'Run plak trust without sudo; only the system-store step escalates privileges.'
        return 1
    fi
    is_caddy_running || { plak_ui_error 'Plak server is unavailable. Run plak enable, then plak trust.'; return 1; }

    # FrankenPHP's trust subcommand writes the Caddy local root into the
    # system store and platform stores supported by Caddy. On
    # macOS that's the login keychain; on Linux it's /usr/local/share/ca-
    # certificates + ~/.pki/nssdb + ~/.mozilla/firefox/*.
    #
    # Safe to re-run — all writes are idempotent.

    if [ "$OS" = "linux" ]; then
        # certutil (libnss3-tools / nss-tools) is needed to touch NSS DBs.
        # Without it Firefox and Chromium keep showing the "Not Secure"
        # warning even though curl and Chrome-with-system-roots are fine.
        if ! command -v certutil &>/dev/null; then
            echo "   - Installing NSS tools for browser trust..."
            if [ "$PKG_MANAGER" = "apt" ]; then
                $SUDO_CMD apt install -y libnss3-tools &>/dev/null || true
            elif [ "$PKG_MANAGER" = "dnf" ]; then
                $SUDO_CMD dnf install -y nss-tools &>/dev/null || true
            fi
        fi
    fi

    # Run the built-in trust installer. Needs sudo on Linux to write to
    # /usr/local/share/ca-certificates and re-run update-ca-certificates.
    # frankenphp trust talks to the Caddy admin API on :2019 to fetch the
    # current root — so if Caddy isn't up (common right after plak install
    # fails to start the service) the call errors with "connection refused"
    # and the remainder of the trust work is a no-op. Capture the exit code
    # so the final success banner only fires when something was actually
    # installed.
    echo "   - Running frankenphp trust..."
    local trust_output trust_rc=0
    if [ "$OS" = "linux" ]; then
        trust_output=$($SUDO_CMD "$CADDY_CMD" trust 2>&1) || trust_rc=$?
    else
        trust_output=$("$CADDY_CMD" trust 2>&1) || trust_rc=$?
    fi
    echo "$trust_output" | grep -vE '^\{|^$' || true
    if [ "$trust_rc" -ne 0 ]; then
        plak_ui_error 'System trust installation failed; no total success reported.'
        return "$trust_rc"
    fi

    # Linux-only: Firefox and Chromium ship as snaps on Ubuntu 22+ and
    # store their NSS DBs under ~/snap/... — a path that neither Caddy nor
    # mkcert scans. Inject the root explicitly for each profile we find.
    if [ "$OS" = "linux" ]; then
        local root_cert
        root_cert=$(plak_site_caddy_root_cert) || root_cert=""

        if [ -n "$root_cert" ] && [ -r "$root_cert" ]; then
            plak_site_trust_nss "$root_cert" || trust_rc=1
        else
            plak_ui_error 'Could not locate current Caddy root.crt; browser trust was not updated.'
            trust_rc=1
        fi
    fi

    # Linuxbrew ships its own curl/OpenSSL with a CA bundle that ignores the
    # system store, so tools like wp-mcp fail with curl exit 60 even after the
    # root is trusted system-wide. Replace the managed root in Homebrew bundles.
    if [ "$OS" = "linux" ] && command -v brew &>/dev/null; then
        local brew_prefix_linux brew_root
        brew_prefix_linux=$(brew --prefix 2>/dev/null || true)
        brew_root=$(plak_site_caddy_root_cert)
        if [ -n "$brew_prefix_linux" ] && [ -n "$brew_root" ]; then
            plak_site_trust_linuxbrew_bundles "$brew_prefix_linux" "$brew_root" || trust_rc=1
        fi
    fi

    echo ""
    if [ "$trust_rc" -eq 0 ]; then
        gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 \
            "✅ Local SSL trust installed" \
            "If a browser was open during this run, restart it to pick up the new CA."
    else
        plak_ui_error 'Trust incomplete; see profile/bundle errors above. Close browsers and retry after resolving those errors.'
    fi
    return "$trust_rc"
}

# Source: commands/site/upgrade
upgrade_frankenphp() {
    local frankenphp_path
    frankenphp_path=$(command -v frankenphp)

    # Check if installed via package manager (typically at /usr/bin/frankenphp)
    if [ "$frankenphp_path" = "/usr/bin/frankenphp" ]; then
        # Package manager installation - use apt/dnf to upgrade
        if [ "$PKG_MANAGER" = "apt" ]; then
            echo "   - FrankenPHP installed via apt. Upgrading with apt..."
            if $SUDO_CMD apt update && $SUDO_CMD apt install --only-upgrade -y frankenphp; then
                echo "   - ✅ FrankenPHP upgraded successfully via apt."
            else
                gum style --foreground red "❌ Failed to upgrade FrankenPHP via apt."
                return 1
            fi
        elif [ "$PKG_MANAGER" = "dnf" ]; then
            echo "   - FrankenPHP installed via dnf. Upgrading with dnf..."
            if $SUDO_CMD dnf upgrade -y frankenphp; then
                echo "   - ✅ FrankenPHP upgraded successfully via dnf."
            else
                gum style --foreground red "❌ Failed to upgrade FrankenPHP via dnf."
                return 1
            fi
        else
            echo "   - ⚠️ Unknown package manager for FrankenPHP at /usr/bin. Skipping upgrade."
            return 1
        fi
    else
        # Static binary installation - download directly
        local target_bin_dir
        if [ -n "$frankenphp_path" ]; then
            target_bin_dir=$(dirname "$frankenphp_path")
            echo "   - Detected static FrankenPHP binary in '$target_bin_dir'."
        else
            target_bin_dir="$BIN_DIR"
            echo "   - FrankenPHP not found. Using default: $target_bin_dir"
        fi

        echo "   - Downloading latest FrankenPHP static binary..."

        # Determine the correct binary for this platform
        local arch=$(uname -m)
        local os=$(uname -s)
        local binary_name=""

        if [ "$os" = "Linux" ]; then
            case $arch in
                x86_64) binary_name="frankenphp-linux-x86_64" ;;
                aarch64) binary_name="frankenphp-linux-aarch64" ;;
            esac
            # Check for glibc
            if getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
                binary_name="${binary_name}-gnu"
            fi
        elif [ "$os" = "Darwin" ]; then
            case $arch in
                arm64) binary_name="frankenphp-mac-arm64" ;;
                x86_64) binary_name="frankenphp-mac-x86_64" ;;
            esac
        fi

        if [ -z "$binary_name" ]; then
            gum style --foreground red "❌ No precompiled FrankenPHP binary available for $os/$arch"
            return 1
        fi

        local temp_binary="/tmp/frankenphp_new"
        if curl -L --progress-bar "https://github.com/php/frankenphp/releases/latest/download/${binary_name}" -o "$temp_binary"; then
            chmod +x "$temp_binary"
            if sudo mv "$temp_binary" "$target_bin_dir/frankenphp"; then
                # Set capability to bind to low ports without root
                if command -v setcap &>/dev/null; then
                    $SUDO_CMD setcap 'cap_net_bind_service=+ep' "$target_bin_dir/frankenphp" 2>/dev/null || true
                fi
                echo "   - ✅ FrankenPHP upgraded successfully."
            else
                gum style --foreground red "❌ Failed to move FrankenPHP to $target_bin_dir"
                rm -f "$temp_binary"
                return 1
            fi
        else
            gum style --foreground red "❌ Failed to download FrankenPHP binary."
            return 1
        fi
    fi

    # Verify mysqli is available after upgrade
    echo "   - Verifying PHP mysqli extension..."
    if ! frankenphp php-cli -r "echo implode(',', get_loaded_extensions());" 2>/dev/null | grep -qi mysqli; then
        gum style --foreground yellow "⚠️ Warning: mysqli extension not found in FrankenPHP."
        gum style --foreground yellow "   WordPress sites may not work correctly."
        return 1
    fi
    echo "   - ✅ mysqli extension verified."

    return 0
}

plak_site_upgrade() {
    local auto_yes=false
    for arg in "$@"; do
        case "$arg" in
            --yes|-y|--force) auto_yes=true ;;
        esac
    done
    # Non-interactive callers have no TTY — auto-yes so the Adminer prompt
    # (only shown when the local version can't be parsed) doesn't hang.
    [ -t 0 ] || auto_yes=true

    echo "🔎 Checking for the latest version of Plak..."

    local download_url="https://raw.githubusercontent.com/plakio/plak-cli/main/plak.sh"
    local temp_script="/tmp/plak.sh.latest"
    local install_path

    # Find the real path of the currently running script
    install_path=$(command -v plak)
    if [ -z "$install_path" ]; then
        install_path="/usr/local/bin/plak" # Fallback to default
    fi

    # 1. Download the latest script
    echo "   - Downloading latest Plak script from GitHub..."
    if ! curl -L --fail --progress-bar "$download_url" -o "$temp_script"; then
        echo "❌ Error: Failed to download the latest version. Please check your connection."
        rm -f "$temp_script" 2>/dev/null
        return 1
    fi

    # 2. Make it executable
    chmod +x "$temp_script"

    # 3. Get the new version from the downloaded script
    local new_version
    new_version=$("$temp_script" version | awk '{print $2}' | sed 's/^v//')

    if [ -z "$new_version" ]; then
        echo "❌ Error: Could not determine the version from the downloaded script."
        rm -f "$temp_script" 2>/dev/null
        return 1
    fi

    # 4. Get the current version from the running script
    local current_version="$PLAK_VERSION"
    echo "   - Current Plak version:         $current_version"
    echo "   - Latest available Plak version: $new_version"

    # 5. Compare versions
    local latest
    latest=$(printf '%s\n' "$current_version" "$new_version" | sort -V | tail -n1)

    if [[ "$latest" == "$current_version" ]] && [[ "$new_version" != "$current_version" ]]; then
         echo "✅ Your current Plak version ($current_version) is newer than the latest release ($new_version). No action taken."
         rm -f "$temp_script" 2>/dev/null
    elif [[ "$latest" == "$current_version" ]]; then
        echo "✅ You are already using the latest version of Plak."
        rm -f "$temp_script" 2>/dev/null
    else
        # 6. Perform the Plak upgrade
        echo "🚀 Upgrading Plak to version $new_version..."

        if [ ! -w "$(dirname "$install_path")" ]; then
            echo "❌ Error: No write permissions for '$(dirname "$install_path")'."
            echo "   Please try running with sudo: 'sudo plak upgrade'"
            rm -f "$temp_script" 2>/dev/null
            return 1
        fi

        if ! mv "$temp_script" "$install_path"; then
            echo "❌ Error: Failed to replace the old script at '$install_path'."
            rm -f "$temp_script" 2>/dev/null
        else
            echo "✅ Plak has been successfully upgraded to version $new_version!"
            echo "   Run 'plak version' to see the new version."
        fi
    fi

    # --- New Section: FrankenPHP Upgrade Check ---
    echo ""
    echo "🔎 Checking for FrankenPHP updates..."

    if ! command -v frankenphp &> /dev/null; then
        echo "   - ⚠️ FrankenPHP not found. Skipping update check."
        return 0
    fi

    # Get local version (strip 'v' prefix if present)
    local local_frankenphp_version
    local_frankenphp_version=$(frankenphp version | awk '{print $2}' | sed 's/^v//')
    if [ -z "$local_frankenphp_version" ]; then
        echo "   - ❌ Could not determine local FrankenPHP version. Skipping update check."
        return 1
    fi

    # Get latest version from GitHub redirect (strip 'v' prefix)
    local latest_frankenphp_version
    latest_frankenphp_version=$(curl -sL -o /dev/null -w '%{url_effective}' https://github.com/php/frankenphp/releases/latest | sed 's/.*\/v//')

    if [ -z "$latest_frankenphp_version" ]; then
        echo "   - ❌ Could not determine the latest FrankenPHP version from GitHub. Skipping update check."
        return 1
    fi

    echo "   - Current FrankenPHP version:  $local_frankenphp_version"
    echo "   - Latest available version:    $latest_frankenphp_version"

    # Compare versions using sort -V (works without PHP)
    local needs_upgrade="false"
    if [ "$local_frankenphp_version" != "$latest_frankenphp_version" ]; then
        local older_version
        older_version=$(printf '%s\n' "$local_frankenphp_version" "$latest_frankenphp_version" | sort -V | head -n1)
        if [ "$older_version" = "$local_frankenphp_version" ]; then
            needs_upgrade="true"
        fi
    fi

    if [ "$needs_upgrade" == "true" ]; then
        echo "🚀 Upgrading FrankenPHP to version $latest_frankenphp_version..."
        upgrade_frankenphp
    else
        echo "✅ FrankenPHP is already up to date."
    fi

    # --- Adminer Upgrade Check ---
    echo ""
    echo "🔎 Checking for Adminer updates..."

    local adminer_file="$ADMINER_DIR/adminer-core.php"
    if [ ! -f "$adminer_file" ]; then
        echo "   - ⚠️ Adminer not found. Skipping update check."
        return 0
    fi

    # Get current Adminer version from the file (portable — BSD grep has no -P/\K)
    local current_adminer_version
    current_adminer_version=$(LC_ALL=C sed -nE 's/.*VERSION="([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$adminer_file" 2>/dev/null | head -1)
    if [ -z "$current_adminer_version" ]; then
        current_adminer_version=$(LC_ALL=C sed -nE 's/.*@version[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$adminer_file" 2>/dev/null | head -1)
    fi

    if [ -z "$current_adminer_version" ]; then
        echo "   - ⚠️ Could not determine current Adminer version."
        current_adminer_version="unknown"
    fi

    # Get latest version from GitHub
    local latest_adminer_version
    latest_adminer_version=$(curl -sL -o /dev/null -w '%{url_effective}' https://github.com/vrana/adminer/releases/latest | sed 's/.*\/v//')

    if [ -z "$latest_adminer_version" ]; then
        echo "   - ❌ Could not determine the latest Adminer version from GitHub."
        return 0
    fi

    echo "   - Current Adminer version:  $current_adminer_version"
    echo "   - Latest available version: $latest_adminer_version"

    # Compare versions (skip if current is unknown)
    if [ "$current_adminer_version" != "unknown" ]; then
        local adminer_needs_upgrade
        adminer_needs_upgrade=$(LOCAL_V="$current_adminer_version" REMOTE_V="$latest_adminer_version" frankenphp php-cli -r '
            if (version_compare(getenv("LOCAL_V"), getenv("REMOTE_V"), "<")) {
                echo "true";
            } else {
                echo "false";
            }
        ')

        if [ "$adminer_needs_upgrade" == "true" ]; then
            echo "🚀 Upgrading Adminer to version $latest_adminer_version..."
            if curl -sL "https://github.com/vrana/adminer/releases/download/v${latest_adminer_version}/adminer-${latest_adminer_version}.php" -o "$adminer_file"; then
                echo "✅ Adminer upgraded successfully."
            else
                echo "❌ Failed to download Adminer $latest_adminer_version."
            fi
        else
            echo "✅ Adminer is already up to date."
        fi
    else
        # If version unknown, offer to upgrade anyway
        local do_download=false
        if [ "$auto_yes" = true ]; then
            do_download=true
        elif gum confirm "Current version unknown. Would you like to download the latest Adminer ($latest_adminer_version)?"; then
            do_download=true
        fi
        if $do_download; then
            echo "🚀 Downloading Adminer $latest_adminer_version..."
            if curl -sL "https://github.com/vrana/adminer/releases/download/v${latest_adminer_version}/adminer-${latest_adminer_version}.php" -o "$adminer_file"; then
                echo "✅ Adminer downloaded successfully."
            else
                echo "❌ Failed to download Adminer $latest_adminer_version."
            fi
        fi
    fi

    # Always refresh the Plak Adminer theme + entry point. Pre-1.10 installs
    # shipped the Catppuccin CSS and a bare index.php without the head()
    # hook — without this step upgraders would keep the old UI even after
    # adminer-core.php gets the latest version.
    echo ""
    echo "🎨 Refreshing Plak Adminer theme..."
    deploy_adminer_theme

    # --- Floor Plak's PHP ini at the current installer default ---
    # Pre-1.10 installers wrote memory_limit=512M (also upload/post=unset).
    # Raise to the 1G floor the fresh installer uses today, but leave any
    # value already >= 1G alone so a user who bumped to 2G stays at 2G.
    local install_default_memory="1G"
    local floor_bytes=$(( 1024 * 1024 * 1024 ))

    mem_to_bytes() {
        local s="${1:-0}" n suffix
        n="${s%[KMGkmg]}"; suffix="${s#$n}"
        case "$suffix" in
            K|k) echo $((n * 1024)) ;;
            M|m) echo $((n * 1024 * 1024)) ;;
            G|g) echo $((n * 1024 * 1024 * 1024)) ;;
            *)   echo "${n:-0}" ;;
        esac
    }

    echo ""
    echo "🧠 Checking PHP memory floor…"
    local bumped_any=false
    local k
    for k in memory_limit upload_max_filesize post_max_size; do
        local current
        current=$(plak_site_ini_get "$k" "")
        local current_bytes
        current_bytes=$(mem_to_bytes "$current")
        if [ -z "$current" ] || [ "$current_bytes" -lt "$floor_bytes" ]; then
            mkdir -p "$(dirname "$PHP_INI_FILE")"
            touch "$PHP_INI_FILE"
            if grep -qE "^[[:space:]]*${k}[[:space:]]*=" "$PHP_INI_FILE"; then
                sed -i.bak -E "s|^[[:space:]]*${k}[[:space:]]*=.*|${k} = ${install_default_memory}|" "$PHP_INI_FILE"
            else
                echo "${k} = ${install_default_memory}" >> "$PHP_INI_FILE"
            fi
            rm -f "${PHP_INI_FILE}.bak"
            echo "   ↑ ${k}: ${current:-unset} → ${install_default_memory}"
            bumped_any=true
        else
            echo "   ✓ ${k}: ${current} (already ≥ ${install_default_memory})"
        fi
    done
    if [ "$bumped_any" = true ]; then
        echo "   (plak reload below regenerates the Caddyfile so the web server picks up the new limits.)"
    fi

    # --- Reload to pull in any UI updates ---
    # Invoke the on-disk binary so a freshly-upgraded script's new functions are used
    # (the currently-running process still holds the pre-upgrade functions in memory).
    echo ""
    echo "🔄 Reloading Plak to apply UI updates..."
    "$install_path" reload
}

# Source: commands/site/url
plak_site_url() {
    # -----------------------------------------------------------------
    #  plak url <site>
    #  Prints the HTTPS URL for a given site (e.g. https://foo.localhost)
    # -----------------------------------------------------------------
    local site_name="$1"

    # -------------------------------------------------------------
    #  Basic validation – the command requires exactly one argument.
    # -------------------------------------------------------------
    if [ -z "$site_name" ]; then
        gum style --foreground red "❌ Error: A site name is required."
        echo "Usage: plak url <site>"
        exit 1
    fi

    # -------------------------------------------------------------
    #  Build the expected directory name and verify that it exists.
    # -------------------------------------------------------------
    local site_dir="${SITES_DIR}/${site_name}.localhost"
    if [ ! -d "$site_dir" ]; then
        gum style --foreground red "❌ Error: Site '${site_name}.localhost' not found."
        exit 1
    fi

    # -------------------------------------------------------------
    #  Print the URL – we keep the output plain so it can be piped.
    # -------------------------------------------------------------
    url_for "${site_name}.localhost"
}
# Source: commands/site/wp
plak_site_wp() {
    local site_name="${1:-}"
    if [ "$site_name" = --help ] || [ "$site_name" = -h ]; then
        plak_display_command_help wp
        return 0
    fi
    if [ -z "$site_name" ] || [ "$#" -lt 2 ]; then
        plak_display_command_help wp >&2
        return 1
    fi
    shift
    site_name="${site_name%.localhost}"
    if ! plak_validate_site_name "$site_name"; then
        echo "Error: invalid site name '$site_name'." >&2
        return 1
    fi

    local public_dir="$SITES_DIR/$site_name.localhost/public"
    if [ ! -d "$public_dir" ] || [ ! -f "$public_dir/wp-config.php" ] || [ ! -f "$public_dir/wp-includes/version.php" ]; then
        echo "Error: WordPress site '$site_name.localhost' not found or incomplete." >&2
        return 1
    fi

    local PLAK_WP_COMMAND=()
    plak_wp_resolve_command || return $?
    cd "$public_dir" || return 1
    # Replace Plak with the runtime: stdin, stdout, stderr, signals and the
    # exit status are WP-CLI's, without a formatting/filtering intermediary.
    exec "${PLAK_WP_COMMAND[@]}" "$@"
}

# Source: commands/site/wsl-hosts
# Build the PowerShell that replaces Plak's managed block in the Windows hosts
# file. Idempotent: any previous Plak block is removed before writing the new
# one, so repeated runs update the WSL IP instead of duplicating lines. Only
# lines between the markers are touched.
plak_wsl_hosts_ps_command() {
    local wsl_ip="$1" hostnames="$2"
    local entry="### plak begin ###"
    local entry_end="### plak end ###"
    # The whole replacement is one PowerShell program submitted via -Command.
    cat <<POWERSHELL
\$hosts = "\$env:SystemRoot\System32\drivers\etc\hosts";
\$lines = Get-Content -LiteralPath \$hosts -ErrorAction SilentlyContinue;
\$kept = @(); \$inside = \$false;
foreach (\$line in \$lines) {
    if (\$line -match '^### plak (begin|end) ###') {
        if (\$line -match 'begin') { \$inside = \$true }
        if (\$line -match 'end') { \$inside = \$false }
        continue
    }
    if (-not \$inside) { \$kept += \$line }
}
\$block = @('### plak begin ###', '$wsl_ip $hostnames', '### plak end ###');
(\$kept + \$block) | Set-Content -LiteralPath \$hosts -Encoding ASCII;
Write-Host 'Plak hosts entries updated.'
POWERSHELL
}

plak_site_wsl_hosts() {
    if [ "$IS_WSL" != true ]; then
        echo "This command is only available in WSL environments."
        exit 1
    fi

    local wsl_ip
    wsl_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    if [ -z "$wsl_ip" ]; then
        gum style --foreground red "❌ Could not determine WSL IP address."
        exit 1
    fi

    # Build list of all hostnames
    local hostnames="plak.localhost db.plak.localhost mail.plak.localhost"

    # Add all site hostnames
    if [ -d "$SITES_DIR" ]; then
        for site_path in "$SITES_DIR"/*; do
            if [ -d "$site_path" ]; then
                local site_hostname
                site_hostname=$(basename "$site_path")
                hostnames="$hostnames $site_hostname"

                # Also add any custom mappings
                if [ -f "$site_path/mappings" ]; then
                    while IFS= read -r mapping || [ -n "$mapping" ]; do
                        if [ -n "$mapping" ]; then
                            hostnames="$hostnames $mapping"
                        fi
                    done < "$site_path/mappings"
                fi
            fi
        done
    fi

    # Find Caddy's CA certificate path
    local ca_cert="$HOME/.local/share/caddy/pki/authorities/local/root.crt"
    local windows_cert_path=""

    # Convert WSL path to Windows path for the certificate
    if [ -f "$ca_cert" ]; then
        windows_cert_path=$(wslpath -w "$ca_cert" 2>/dev/null || echo "")
    fi

    echo ""
    gum style --border normal --margin "1" --padding "1 2" --border-foreground 212 \
        "WSL Setup Helper" \
        "" \
        "WSL IP Address: $wsl_ip"

    # Mirrored networking makes *.localhost resolve without editing hosts.
    local mirrored="false"
    if command -v wslinfo >/dev/null 2>&1 && wslinfo --networking-mode 2>/dev/null | grep -qi mirrored; then
        mirrored="true"
    fi

    # --- STEP 1: Hosts File ---
    echo ""
    gum style --foreground 212 "━━━ Step 1: Update Windows Hosts File ━━━"
    echo ""

    if [ "$mirrored" = true ]; then
        gum style --foreground green "✅ WSL is using mirrored networking: *.localhost already resolves on Windows."
        echo "   You can skip this step."
    fi

    # One idempotent command that replaces Plak's block instead of appending.
    local ps_command
    ps_command=$(plak_wsl_hosts_ps_command "$wsl_ip" "$hostnames")

    echo "Run this in PowerShell (as Administrator):"
    echo ""
    gum style --foreground cyan "$ps_command"
    echo ""
    echo "It replaces Plak's managed block (between the ### plak begin/end ###"
    echo "markers) with the current WSL IP, so re-running never duplicates lines."

    # Offer to apply it directly when the Windows PowerShell bridge is present.
    if command -v powershell.exe >/dev/null 2>&1; then
        echo ""
        if gum confirm "Apply it now from here? (needs Administrator PowerShell)"; then
            if powershell.exe -NoProfile -Command "$ps_command"; then
                gum style --foreground green "✅ Windows hosts file updated."
            else
                gum style --foreground red "❌ Could not update the hosts file. Run the command above in an Administrator PowerShell."
            fi
        fi
    fi

    # --- STEP 2: Certificate Trust ---
    echo ""
    gum style --foreground 212 "━━━ Step 2: Trust Caddy's CA Certificate ━━━"
    echo ""
    echo "To remove browser certificate warnings, install Caddy's root CA in Windows."
    echo ""

    if [ -n "$windows_cert_path" ]; then
        echo "The certificate is located at:"
        gum style --foreground cyan "$windows_cert_path"
        echo ""
        echo "Option A: Double-click the certificate in Windows Explorer and install it:"
        echo "  1. Open the path above in Windows Explorer"
        echo "  2. Double-click root.crt"
        echo "  3. Click 'Install Certificate...'"
        echo "  4. Select 'Local Machine' and click Next"
        echo "  5. Select 'Place all certificates in the following store'"
        echo "  6. Click Browse and select 'Trusted Root Certification Authorities'"
        echo "  7. Click Next, then Finish"
        echo ""
        echo "Option B: Run this in PowerShell (as Administrator):"
        echo ""
        gum style --foreground cyan "Import-Certificate -FilePath \"$windows_cert_path\" -CertStoreLocation Cert:\\LocalMachine\\Root"
    else
        echo "Certificate not found at: $ca_cert"
        echo "Make sure Caddy has been started at least once with 'plak enable'."
    fi

    echo ""
    gum style --foreground yellow "Note: WSL IP may change on restart. Run 'plak wsl-hosts' again to refresh the managed block."
    echo ""
}

# Source: commands/skill
PLAK_SKILL_NAME="plak-cli"
PLAK_SKILL_RAW_BASE="${PLAK_SKILL_RAW_BASE:-https://raw.githubusercontent.com/plakio/plak-cli/main/skills/plak-cli}"
# The WP-MCP companion skill is installed beside the Plak skill for the same
# targets, so an agent that drives a Plak site knows how to use wp-mcp too.
PLAK_WPMCP_SKILL_NAME="wp-mcp"
PLAK_WPMCP_SKILL_RAW_BASE="${PLAK_WPMCP_SKILL_RAW_BASE:-https://raw.githubusercontent.com/plakio/wp-mcp-cli/${PLAK_WPMCP_VERSION}/skills/wp-mcp}"

# Destination used by wp-mcp-cli's own `skill install` for a target.
plak_skill_wpmcp_path() {
    case "$1" in
        codex) echo "$HOME/.codex/skills/$PLAK_WPMCP_SKILL_NAME/SKILL.md" ;;
        claude-code|claude) echo "$HOME/.claude/skills/$PLAK_WPMCP_SKILL_NAME/SKILL.md" ;;
        opencode) echo "$HOME/.config/opencode/skills/$PLAK_WPMCP_SKILL_NAME/SKILL.md" ;;
        hermes) echo "$HOME/.hermes/skills/$PLAK_WPMCP_SKILL_NAME/SKILL.md" ;;
        pi) echo "$HOME/.pi/skills/$PLAK_WPMCP_SKILL_NAME/SKILL.md" ;;
        global) echo "$HOME/.agents/skills/$PLAK_WPMCP_SKILL_NAME/SKILL.md" ;;
        *) return 1 ;;
    esac
}

# Install the official wp-mcp skill for one target. Prefer wp-mcp-cli's own
# installer; fall back to fetching the pinned skill file. Never fails the Plak
# skill install and never writes to targets the user did not select.
plak_skill_install_wpmcp_companion() {
    local target="$1" dest
    if plak_command_exists wp-mcp; then
        if wp-mcp skill install "$target" >/dev/null 2>&1; then
            return 0
        fi
    fi
    dest=$(plak_skill_wpmcp_path "$target") || return 0
    if ! plak_command_exists curl; then
        plak_ui_warn "curl is required to install the wp-mcp skill for $target."
        return 0
    fi
    mkdir -p "$(dirname "$dest")" || return 0
    if curl -fsSL "$PLAK_WPMCP_SKILL_RAW_BASE/SKILL.md" -o "$dest"; then
        plak_ui_success "Installed wp-mcp skill for $target: $dest"
    else
        plak_ui_warn "Could not install the wp-mcp skill for $target."
    fi
    return 0
}

plak_skill_help() {
    cat <<'HELP'
Usage:
  plak skill install [codex|claude-code|opencode|hermes|pi|global|all]
  plak skill help

Installs the Plak CLI agent skill for supported coding agents.

Targets:
  codex        ~/.codex/skills/plak-cli/SKILL.md
  claude-code  ~/.claude/skills/plak-cli/SKILL.md
  opencode     ~/.config/opencode/skills/plak-cli/SKILL.md
  hermes       ~/.hermes/skills/plak-cli/SKILL.md
  pi           ~/.pi/agent/skills/plak-cli/SKILL.md
  global       ~/.agents/skills/plak-cli/SKILL.md
  all          Install for every agent-specific target (does not include global)
HELP
}

plak_skill_target_path() {
    case "$1" in
        codex) echo "$HOME/.codex/skills/$PLAK_SKILL_NAME" ;;
        claude-code|claude) echo "$HOME/.claude/skills/$PLAK_SKILL_NAME" ;;
        opencode) echo "$HOME/.config/opencode/skills/$PLAK_SKILL_NAME" ;;
        hermes) echo "$HOME/.hermes/skills/$PLAK_SKILL_NAME" ;;
        pi) echo "$HOME/.pi/agent/skills/$PLAK_SKILL_NAME" ;;
        global) echo "$HOME/.agents/skills/$PLAK_SKILL_NAME" ;;
        *) return 1 ;;
    esac
}

plak_skill_normalize_target() {
    case "$1" in
        codex|openai|openai-codex) echo "codex" ;;
        claude|claude-code|claudecode) echo "claude-code" ;;
        opencode|open-code) echo "opencode" ;;
        hermes) echo "hermes" ;;
        pi) echo "pi" ;;
        global|agents|agent) echo "global" ;;
        all) echo "all" ;;
        *) return 1 ;;
    esac
}

plak_skill_source_dir() {
    local script_dir cwd_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
    cwd_dir=$(pwd)

    if [ -f "$script_dir/skills/$PLAK_SKILL_NAME/SKILL.md" ]; then
        echo "$script_dir/skills/$PLAK_SKILL_NAME"
    elif [ -f "$cwd_dir/skills/$PLAK_SKILL_NAME/SKILL.md" ]; then
        echo "$cwd_dir/skills/$PLAK_SKILL_NAME"
    else
        return 1
    fi
}

plak_skill_install_target() {
    local target="$1" dest source_dir
    dest=$(plak_skill_target_path "$target") || return 1

    mkdir -p "$dest"

    if source_dir=$(plak_skill_source_dir); then
        cp -R "$source_dir/." "$dest/"
    else
        if ! plak_command_exists curl; then
            plak_ui_error "curl is required to download the Plak skill."
            return 1
        fi
        curl -fsSL "$PLAK_SKILL_RAW_BASE/SKILL.md" -o "$dest/SKILL.md"
    fi

    if [ ! -f "$dest/SKILL.md" ]; then
        plak_ui_error "Failed to install skill for $target."
        return 1
    fi

    plak_ui_success "Installed Plak skill for $target: $dest/SKILL.md"
    plak_skill_install_wpmcp_companion "$target"
}

plak_skill_prompt_targets() {
    local selected input tty="/dev/tty"

    if plak_command_exists gum && [ -r "$tty" ] && [ -w "$tty" ]; then
        selected=$(gum choose \
            --no-limit \
            --height 8 \
            --header "Which agents do you use? Space to select, Enter to install." \
            codex \
            claude-code \
            opencode \
            hermes \
            pi \
            global \
            all < "$tty")
        [ -n "$selected" ] || return 1
        if printf '%s\n' "$selected" | grep -qx 'all'; then
            printf '%s\n' codex claude-code opencode hermes pi
            printf '%s\n' "$selected" | grep -vx 'all'
        else
            printf '%s\n' "$selected"
        fi
        return 0
    fi

    {
        echo "Which agents do you use? Enter one or more numbers separated by commas:"
        echo "  1) codex"
        echo "  2) claude-code"
        echo "  3) opencode"
        echo "  4) hermes"
        echo "  5) pi"
        echo "  6) global"
        echo "  7) all"
        printf "> "
    } > "$tty" 2>/dev/null || {
        echo "Which agents do you use? Enter one or more numbers separated by commas:" >&2
        echo "  1) codex" >&2
        echo "  2) claude-code" >&2
        echo "  3) opencode" >&2
        echo "  4) hermes" >&2
        echo "  5) pi" >&2
        echo "  6) global" >&2
        echo "  7) all" >&2
        printf "> " >&2
    }

    if [ -r "$tty" ]; then
        read -r input < "$tty"
    else
        read -r input
    fi

    case ",$input," in *",7,"*) printf '%s\n' codex claude-code opencode hermes pi ;; esac
    case ",$input," in *",1,"*) echo "codex" ;; esac
    case ",$input," in *",2,"*) echo "claude-code" ;; esac
    case ",$input," in *",3,"*) echo "opencode" ;; esac
    case ",$input," in *",4,"*) echo "hermes" ;; esac
    case ",$input," in *",5,"*) echo "pi" ;; esac
    case ",$input," in *",6,"*) echo "global" ;; esac
}

plak_skill_install() {
    local targets=() arg normalized target failed=false

    if [ "$#" -eq 0 ]; then
        while IFS= read -r target; do
            [ -n "$target" ] && targets+=("$target")
        done < <(plak_skill_prompt_targets)
    else
        for arg in "$@"; do
            case "$arg" in
                --help|-h)
                    plak_skill_help
                    return 0
                    ;;
                *)
                    if ! normalized=$(plak_skill_normalize_target "$arg"); then
                        plak_ui_error "Unknown skill target: $arg"
                        plak_skill_help
                        return 1
                    fi
                    if [ "$normalized" = "all" ]; then
                        targets+=(codex claude-code opencode hermes pi)
                    else
                        targets+=("$normalized")
                    fi
                    ;;
            esac
        done
    fi

    if [ "${#targets[@]}" -eq 0 ]; then
        plak_ui_warn "No agent selected."
        return 0
    fi

    local seen=","
    for target in "${targets[@]}"; do
        case "$seen" in
            *",$target,"*) continue ;;
        esac
        seen="$seen$target,"
        if ! plak_skill_install_target "$target"; then
            failed=true
        fi
    done

    if $failed; then
        return 1
    fi

    echo ""
    echo "Restart your agent session so it can discover the new skill."
}

plak_skill() {
    local action="${1:-help}"
    [ "$#" -gt 0 ] && shift

    case "$action" in
        install)
            plak_skill_install "$@"
            ;;
        help|--help|-h)
            plak_skill_help
            ;;
        *)
            plak_ui_error "Unknown skill action: $action"
            plak_skill_help
            return 1
            ;;
    esac
}

# Source: commands/sshkey
plak_sshkey_private_keys() {
    local ssh_dir="${1:-$HOME/.ssh}"

    [ -d "$ssh_dir" ] || return 0

    find "$ssh_dir" -maxdepth 1 -type f \
        ! -name '.*' \
        ! -name '*.pub' \
        ! -name 'authorized_keys' \
        ! -name 'known_hosts*' \
        ! -name '*_known_hosts' \
        ! -name 'config' \
        -print | while IFS= read -r key_path; do
            if head -n 1 "$key_path" 2>/dev/null | grep -q 'PRIVATE KEY'; then
                printf '%s\n' "$key_path"
            fi
        done | sort
}

plak_sshkey_rows() {
    plak_sshkey_private_keys | while IFS= read -r key_path; do
        key_name=$(basename "$key_path")
        has_public="No"
        [ -f "$key_path.pub" ] && has_public="Yes"
        printf '%s,%s,%s\n' "$key_name" "$has_public" "$key_path"
    done
}

plak_sshkey_list() {
    local ssh_dir="$HOME/.ssh" rows

    if [ ! -d "$ssh_dir" ]; then
        plak_ui_warn "SSH directory not found: $ssh_dir"
        return 0
    fi

    rows=$(plak_sshkey_rows)

    if [ -z "$rows" ]; then
        plak_ui_warn "No SSH keys found in $ssh_dir."
        return 0
    fi

    if plak_command_exists gum && [ -t 1 ]; then
        {
            echo "Name,Public Key,Path"
            echo "$rows"
        } | gum table --separator ","
    else
        echo "$rows" | column -t -s ',' 2>/dev/null || echo "$rows"
    fi
}

plak_sshkey_show_details() {
    local key_path="$1" pub_path details

    if [ ! -f "$key_path" ]; then
        plak_ui_error "Key not found: $key_path"
        return 1
    fi

    pub_path="$key_path.pub"
    plak_ui_title "SSH key: $(basename "$key_path")"
    echo "Private: $key_path"
    echo "Public:  $pub_path"
    echo ""

    if [ -f "$pub_path" ]; then
        if details=$(ssh-keygen -l -f "$pub_path" 2>/dev/null); then
            echo "$details"
            echo ""
        fi
        cat "$pub_path"
    else
        plak_ui_warn "No public key found."
    fi
}

plak_sshkey_view() {
    local keys selected key_name

    keys=$(plak_sshkey_private_keys)
    if [ -z "$keys" ]; then
        plak_ui_warn "No SSH keys found in $HOME/.ssh."
        return 0
    fi

    if [ "${1:-}" != "" ]; then
        key_name="$1"
        if [ -f "$HOME/.ssh/$key_name" ]; then
            plak_sshkey_show_details "$HOME/.ssh/$key_name"
        else
            plak_sshkey_show_details "$key_name"
        fi
        return
    fi

    plak_require_gum
    selected=$(echo "$keys" | gum filter --placeholder "Choose SSH key")
    [ -n "$selected" ] || return 0
    plak_sshkey_show_details "$selected"
}

plak_sshkey_create() {
    local key_name="" key_type="ed25519" bits="" passphrase="" overwrite=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --type) key_type="$2"; shift 2 ;;
            --bits) bits="$2"; shift 2 ;;
            --passphrase) passphrase="$2"; shift 2 ;;
            --force|--yes|-y) overwrite=true; shift 1 ;;
            -*)
                plak_ui_error "Unknown flag: $1"
                exit 1
                ;;
            *)
                if [ -z "$key_name" ]; then
                    key_name="$1"
                fi
                shift 1
                ;;
        esac
    done

    local have_all=1
    [ -z "$key_name" ] && have_all=0

    if [ "$have_all" -eq 0 ]; then
        plak_require_gum
        plak_ui_title "Create SSH key"
    fi

    if [ -z "$key_name" ]; then
        while true; do
            key_name=$(gum input --prompt "Key name: " --value "id_ed25519")
            [ -n "$key_name" ] || return 0
            if [[ "$key_name" == */* || "$key_name" == .* ]]; then
                plak_ui_error "Use a file name only, without slashes or leading dots."
                continue
            fi
            break
        done
    else
        if [[ "$key_name" == */* || "$key_name" == .* ]]; then
            plak_ui_error "Invalid key name '$key_name'. Use a file name only."
            exit 1
        fi
    fi

    local ssh_dir="$HOME/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    local key_path="$ssh_dir/$key_name"

    if [ -e "$key_path" ] || [ -e "$key_path.pub" ]; then
        if [ "$have_all" -eq 0 ] && [ "$overwrite" = false ]; then
            if gum confirm "Key '$key_name' already exists. Overwrite?"; then
                overwrite=true
            else
                plak_ui_warn "Cancelled."
                return 0
            fi
        fi
        if [ "$overwrite" = false ]; then
            plak_ui_error "Key '$key_name' already exists. Use --yes to overwrite."
            exit 1
        fi
    fi

    if [ "$have_all" -eq 0 ]; then
        if [ -z "$key_type" ]; then
            key_type=$(gum choose "ed25519" "rsa" "ecdsa")
        fi
        if [ "$key_type" = "rsa" ] && [ -z "$bits" ]; then
            bits=$(gum choose "4096" "2048")
        fi
        if [ -z "$passphrase" ]; then
            passphrase=$(gum input --password --placeholder "Passphrase (empty for none)")
        fi
    fi

    case "$key_type" in
        ed25519|rsa|ecdsa) : ;;
        *) plak_ui_error "Invalid key type '$key_type'. Use ed25519, rsa, or ecdsa."; exit 1 ;;
    esac

    if [ "$key_type" = "rsa" ]; then
        if [ -z "$bits" ]; then
            bits=4096
        fi
        if [[ ! "$bits" =~ ^[0-9]+$ ]] || { [ "$bits" -lt 1024 ] || [ "$bits" -gt 16384 ]; }; then
            plak_ui_error "Invalid bits '$bits'. Use 1024-16384 (recommend 4096)."
            exit 1
        fi
    fi

    if [ "$overwrite" = true ]; then
        rm -f "$key_path" "$key_path.pub"
    fi

    local cmd=(ssh-keygen -t "$key_type" -f "$key_path" -N "$passphrase")
    if [ -n "$bits" ]; then
        cmd=(ssh-keygen -t "$key_type" -b "$bits" -f "$key_path" -N "$passphrase")
    fi

    if "${cmd[@]}" 2>/dev/null; then
        chmod 600 "$key_path"
        [ -f "$key_path.pub" ] && chmod 644 "$key_path.pub"
        if [ "$have_all" -eq 0 ]; then
            plak_ui_success "SSH key '$key_name' created."
            echo ""
            plak_sshkey_show_details "$key_path"
        else
            plak_ui_success "SSH key '$key_name' created at $key_path"
        fi
    else
        plak_ui_error "ssh-keygen failed."
        return 1
    fi
}

plak_sshkey_delete() {
    local name="" yes=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --yes|-y) yes=1; shift 1 ;;
            -*) plak_ui_error "Unknown flag: $1"; exit 1 ;;
            *) name="$1"; shift 1 ;;
        esac
    done

    if [ -z "$name" ]; then
        plak_require_gum
        local keys
        keys=$(plak_sshkey_private_keys)
        if [ -z "$keys" ]; then
            plak_ui_warn "No SSH keys found in $HOME/.ssh."
            return 0
        fi
        name=$(echo "$keys" | gum filter --placeholder "Choose SSH key to delete")
        [ -n "$name" ] || return 0
    fi

    local ssh_dir="$HOME/.ssh"
    local key_path
    if [ -f "$ssh_dir/$name" ]; then
        key_path="$ssh_dir/$name"
    elif [ -f "$name" ]; then
        key_path="$name"
    else
        plak_ui_error "Key '$name' not found in $ssh_dir."
        exit 1
    fi

    if [ "$yes" -eq 0 ]; then
        if [ -t 0 ] && plak_command_exists gum; then
            if ! gum confirm "Delete '$(basename "$key_path")' and its .pub file?"; then
                plak_ui_warn "Cancelled."
                return 0
            fi
        else
            plak_ui_error "Refusing to delete '$(basename "$key_path")' without --yes in non-interactive mode."
            exit 1
        fi
    fi

    rm -f "$key_path" "$key_path.pub"
    plak_ui_success "SSH key '$(basename "$key_path")' deleted."
}

plak_sshkey() {
    local action="${1:-help}"
    if [ "$#" -gt 0 ]; then
        shift
    fi

    case "$action" in
        list)
            plak_sshkey_list "$@"
            ;;
        view)
            plak_sshkey_view "$@"
            ;;
        add|create)
            plak_sshkey_create "$@"
            ;;
        delete|remove)
            plak_sshkey_delete "$@"
            ;;
        help|--help|-h)
            plak_display_command_help sshkey
            ;;
        *)
            plak_ui_error "Unknown sshkey action '$action'"
            plak_display_command_help sshkey
            exit 1
            ;;
    esac
}

# Source: commands/status
plak_status() {
    local json_mode=false
    for arg in "$@"; do
        case "$arg" in
            --json) json_mode=true ;;
            -h|--help)
                echo "Usage: plak status [--json]"
                exit 0
                ;;
        esac
    done

    if [ "$json_mode" = true ]; then
        local deps_json=""
        local sep=""
        local dep status
        for dep in gum ssh ssh-keygen awk sed grep mktemp frankenphp mariadb mailpit wp; do
            if plak_command_exists "$dep"; then
                status="found"
            else
                status="missing"
            fi
            deps_json="${deps_json}${sep}\"${dep}\":\"${status}\""
            sep=","
        done

        printf '{"os":"%s","plak_home":"%s","sites_home":"%s","ssh_config":"%s","hosts_file":"%s","dependencies":{%s}}\n' \
            "$PLAK_OS" "$PLAK_HOME" "$PLAK_SITE_DIR" "$PLAK_SSH_CONFIG" "$PLAK_HOSTS_FILE" "$deps_json"
        return 0
    fi

    plak_ui_title "Plak status"
    echo ""
    echo "OS:          $PLAK_OS"
    echo "Plak home:   $PLAK_HOME"
    echo "Sites home:  $PLAK_SITE_DIR"
    echo "SSH config:  $PLAK_SSH_CONFIG"
    echo "Hosts file:  $PLAK_HOSTS_FILE"
    echo ""
    echo "Dependencies:"

    local dep status
    for dep in gum ssh ssh-keygen awk sed grep mktemp frankenphp mariadb mailpit wp; do
        if plak_command_exists "$dep"; then
            status="found"
        else
            status="missing"
        fi
        printf '  %-10s %s\n' "$dep" "$status"
    done

    if [ -f "$CONFIG_FILE" ] && plak_command_exists "$CADDY_CMD" && plak_command_exists gum; then
        if [ "$json_mode" = true ]; then
            plak_site_status --json
        else
            echo ""
            plak_site_status
        fi
    else
        if [ "$json_mode" = true ]; then
            printf '{"site_services":"not_installed","dashboard":"%s"}\n' "$(url_for plak.localhost)"
        else
            echo ""
            echo "Site services: not installed yet"
            echo "Dashboard:     $(url_for plak.localhost)"
        fi
    fi
}

# Source: commands/version
plak_version() {
    local json_mode=false
    for arg in "$@"; do
        case "$arg" in
            --json) json_mode=true ;;
            -h|--help)
                echo "Usage: plak version [--json]"
                exit 0
                ;;
        esac
    done

    if [ "$json_mode" = true ]; then
        printf '{"name":"%s","version":"%s"}\n' "$PLAK_NAME" "$PLAK_VERSION"
    else
        echo "$PLAK_NAME v$PLAK_VERSION"
    fi
}

# Pass all script arguments to the main function.
main "$@"
