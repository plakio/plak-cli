#!/usr/bin/env bash

# Plak - Bash entrypoint
# Source file for the compiled plak.sh distribution script.

set -euo pipefail

PLAK_NAME="plak"
PLAK_VERSION="0.3.0-dev"
PLAK_HOME="${PLAK_HOME:-$HOME/.plak}"
PLAK_SSH_CONFIG="${PLAK_SSH_CONFIG:-$HOME/.ssh/config}"
PLAK_HOSTS_FILE="${PLAK_HOSTS_FILE:-/etc/hosts}"

# Ensure common user-managed binary locations are available when launched from
# restricted environments such as cron, launchd, or GUI shells.
for _plak_bin in /opt/homebrew/bin /usr/local/bin /usr/local/sbin "$HOME/.local/bin"; do
    if [ -d "$_plak_bin" ] && [[ ":$PATH:" != *":$_plak_bin:"* ]]; then
        PATH="$_plak_bin:$PATH"
    fi
done
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
  server      Manage SSH server connections
  domain      Manage local hosts entries
  sshkey      Manage SSH keys
  status      Check local dependencies and paths
  install     Install required dependencies
  version     Show Plak version
  help        Show this help

Examples:
  plak server list
  plak server connect
  plak status
HELP
}

plak_display_command_help() {
    local command="${1:-}"

    case "$command" in
        server)
            cat <<'HELP'
Usage:
  plak server <action>

Actions:
  list        List hosts from ~/.ssh/config
  connect     Pick a host with gum and connect through ssh
  add         Add a new SSH host interactively
  delete      Delete an SSH host interactively
  help        Show server help
HELP
            ;;
        domain)
            cat <<'HELP'
Usage:
  plak domain <action>

Actions:
  list        List non-comment entries from /etc/hosts
  add         Add a hosts entry interactively
  delete      Delete a hosts entry interactively
  help        Show domain help
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
        install)
            cat <<'HELP'
Usage:
  plak install

Installs or guides installation for dependencies used by Plak.
HELP
            ;;
        status)
            echo "Usage: plak status"
            ;;
        version)
            echo "Usage: plak version"
            ;;
        *)
            plak_show_help
            ;;
    esac
}

main() {
    plak_setup_environment

    for arg in "$@"; do
        if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
            plak_display_command_help "${1:-}"
            exit 0
        fi
    done

    local command="${1:-help}"
    if [ "$#" -gt 0 ]; then
        shift
    fi

    case "$command" in
        server)
            plak_server "$@"
            ;;
        domain)
            ;;
        sshkey)
            plak_sshkey "$@"
            ;;
        status|doctor)
            plak_status "$@"
            ;;
        install)
            plak_install "$@"
            ;;
        version|--version|-v)
            plak_version
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
    if plak_command_exists gum; then
        gum style --foreground green "$1"
    else
        echo "$1"
    fi
}

# Source: shared/validate
# Shared validation helpers for Plak Bash commands.

plak_validate_hostname_alias() {
    local value="$1"
    [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]]
}

plak_validate_port() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 1 ] && [ "$value" -le 65535 ]
}

# --- Command Functions ---
# Source: commands/domain
plak_domain_entries() {
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

plak_domain_exists() {
    local domain="$1"
    plak_domain_entries | awk -F, -v target="$domain" '$2 == target { found = 1 } END { exit found ? 0 : 1 }'
}

plak_domain_validate_name() {
    local domain="$1"
    [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] && [[ "$domain" == *.* || "$domain" == "localhost" ]]
}

plak_domain_validate_ip() {
    local ip="$1"
    [[ "$ip" =~ ^[A-Za-z0-9:.%-]+$ ]]
}

plak_domain_write_hosts_file() {
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

plak_domain_add_entry() {
    local ip="$1" domain="$2" tmp_file

    [ -f "$PLAK_HOSTS_FILE" ] || {
        plak_ui_error "Hosts file not found: $PLAK_HOSTS_FILE"
        return 1
    }

    if plak_domain_exists "$domain"; then
        plak_ui_error "Domain '$domain' already exists in $PLAK_HOSTS_FILE."
        return 1
    fi

    tmp_file=$(mktemp)
    cat "$PLAK_HOSTS_FILE" > "$tmp_file"
    printf '\n%s\t%s # plak\n' "$ip" "$domain" >> "$tmp_file"

    plak_domain_write_hosts_file "$tmp_file"
    rm -f "$tmp_file"
}

plak_domain_remove_entry() {
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

    plak_domain_write_hosts_file "$tmp_file"
    rm -f "$tmp_file"
}

plak_domain_list() {
    if [ ! -f "$PLAK_HOSTS_FILE" ]; then
        plak_ui_warn "Hosts file not found: $PLAK_HOSTS_FILE"
        return 0
    fi

    local rows
    rows=$(plak_domain_entries)

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

plak_domain_add() {
    plak_require_gum

    plak_ui_title "Add hosts entry"

    local domain ip
    while true; do
        domain=$(gum input --prompt "Domain: " --placeholder "site.localhost")
        [ -n "$domain" ] || return 0
        if plak_domain_validate_name "$domain"; then
            break
        fi
        plak_ui_error "Invalid domain name."
    done

    while true; do
        ip=$(gum input --prompt "IP: " --value "127.0.0.1")
        [ -n "$ip" ] || return 0
        if plak_domain_validate_ip "$ip"; then
            break
        fi
        plak_ui_error "Invalid IP or host value."
    done

    gum style --border normal --margin "1 0" --padding "1 2" --border-foreground 212 \
        "Hosts entry" \
        "$ip    $domain"

    if ! gum confirm "Add this entry to $PLAK_HOSTS_FILE?"; then
        plak_ui_warn "Cancelled."
        return 0
    fi

    plak_domain_add_entry "$ip" "$domain"
    plak_ui_success "Domain '$domain' added."
}

plak_domain_delete() {
    plak_require_gum

    local rows selected domain
    rows=$(plak_domain_entries)

    if [ -z "$rows" ]; then
        plak_ui_warn "No hosts entries found."
        return 0
    fi

    selected=$(echo "$rows" | awk -F, '{ print $2 "    " $1 }' | gum filter --placeholder "Choose domain to delete")
    [ -n "$selected" ] || return 0

    domain=$(echo "$selected" | awk '{ print $1 }')
    if ! gum confirm "Delete domain '$domain' from $PLAK_HOSTS_FILE?"; then
        plak_ui_warn "Cancelled."
        return 0
    fi

    plak_domain_remove_entry "$domain"
    plak_ui_success "Domain '$domain' deleted."
}

plak_domain() {
    local action="${1:-help}"
    if [ "$#" -gt 0 ]; then
        shift
    fi

    case "$action" in
        list|view)
            plak_domain_list "$@"
            ;;
        add|create)
            plak_domain_add "$@"
            ;;
        delete|remove)
            plak_domain_delete "$@"
            ;;
        help|--help|-h)
            plak_display_command_help domain
            ;;
        *)
            plak_ui_error "Unknown domain action '$action'"
            plak_display_command_help domain
            exit 1
            ;;
    esac
}

# Source: commands/install
plak_install() {
    plak_ui_title "Plak install"
    echo ""

    if plak_command_exists gum; then
        plak_ui_success "gum is already installed."
        return 0
    fi

    case "$PLAK_OS" in
        macos)
            if plak_command_exists brew; then
                echo "Installing gum with Homebrew..."
                brew install gum
            else
                plak_ui_warn "Homebrew is not installed. Install gum from: https://github.com/charmbracelet/gum"
                return 1
            fi
            ;;
        linux)
            plak_ui_warn "gum is missing. Install instructions: https://github.com/charmbracelet/gum#installation"
            return 1
            ;;
        *)
            plak_ui_warn "Unsupported OS. Install gum manually from: https://github.com/charmbracelet/gum"
            return 1
            ;;
    esac
}

# Source: commands/server
plak_server_parse_hosts() {
    local config_path="${1:-$PLAK_SSH_CONFIG}"

    [ -f "$config_path" ] || return 0

    awk '
        BEGIN { IGNORECASE = 1 }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        /^[[:space:]]*Host[[:space:]]+/ {
            for (i = 2; i <= NF; i++) {
                if ($i !~ /[*?]/) {
                    print $i
                }
            }
        }
    ' "$config_path" | sort -u
}

plak_server_host_exists() {
    local name="$1"
    plak_server_parse_hosts | awk -v target="$name" '$0 == target { found = 1 } END { exit found ? 0 : 1 }'
}

plak_server_ensure_config() {
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

plak_server_append_config() {
    local name="$1" hostname="$2" user="$3" port="$4" identity_file="${5:-}"

    plak_server_ensure_config

    {
        echo ""
        echo "Host $name"
        echo "    HostName $hostname"
        echo "    User $user"
        echo "    Port $port"
        if [ -n "$identity_file" ]; then
            echo "    IdentityFile $identity_file"
        fi
    } >> "$PLAK_SSH_CONFIG"
}

plak_server_remove_config() {
    local name="$1" tmp_file

    [ -f "$PLAK_SSH_CONFIG" ] || return 1
    tmp_file=$(mktemp)

    awk -v target="$name" '
        BEGIN { skip = 0; found = 0 }
        /^[[:space:]]*Host[[:space:]]+/ {
            skip = 0
            for (i = 2; i <= NF; i++) {
                if ($i == target) {
                    skip = 1
                    found = 1
                    next
                }
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

plak_server_list() {
    local hosts
    hosts=$(plak_server_parse_hosts)

    if [ -z "$hosts" ]; then
        plak_ui_warn "No SSH hosts found in $PLAK_SSH_CONFIG."
        return 0
    fi

    if plak_command_exists gum && [ -t 1 ]; then
        {
            echo "Name"
            echo "$hosts"
        } | gum table
    else
        echo "$hosts"
    fi
}

plak_server_connect() {
    plak_require_gum

    local hosts selected
    hosts=$(plak_server_parse_hosts)

    if [ -z "$hosts" ]; then
        plak_ui_warn "No SSH hosts found in $PLAK_SSH_CONFIG."
        return 0
    fi

    selected=$(echo "$hosts" | gum filter --placeholder "Choose SSH host")
    [ -n "$selected" ] || return 0

    if ! plak_validate_hostname_alias "$selected"; then
        plak_ui_error "Invalid SSH host alias: $selected"
        exit 1
    fi

    plak_ui_success "Connecting to $selected..."
    ssh "$selected"
}

plak_server_add() {
    plak_require_gum

    plak_ui_title "Add SSH connection"

    local name hostname user port identity_choice identity_file=""

    while true; do
        name=$(gum input --prompt "Name: " --placeholder "my-server")
        [ -n "$name" ] || return 0

        if ! plak_validate_hostname_alias "$name"; then
            plak_ui_error "Use only letters, numbers, dots, underscores and hyphens."
            continue
        fi

        if plak_server_host_exists "$name"; then
            plak_ui_error "SSH host '$name' already exists."
            continue
        fi

        break
    done

    hostname=$(gum input --prompt "Hostname/IP: " --placeholder "example.com")
    [ -n "$hostname" ] || return 0

    user=$(gum input --prompt "User: " --placeholder "ubuntu")
    [ -n "$user" ] || return 0

    while true; do
        port=$(gum input --prompt "Port: " --value "22")
        if plak_validate_port "$port"; then
            break
        fi
        plak_ui_error "Invalid port. Use a number from 1 to 65535."
    done

    if gum confirm "Use an identity file?"; then
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
    fi

    echo ""
    gum style --border normal --margin "1 0" --padding "1 2" --border-foreground 212 \
        "Host $name" \
        "HostName $hostname" \
        "User $user" \
        "Port $port" \
        "IdentityFile ${identity_file:-none}"

    if ! gum confirm "Save this SSH connection?"; then
        plak_ui_warn "Cancelled."
        return 0
    fi

    plak_server_append_config "$name" "$hostname" "$user" "$port" "$identity_file"
    plak_ui_success "SSH connection '$name' added to $PLAK_SSH_CONFIG."
}

plak_server_delete() {
    plak_require_gum

    local hosts selected
    hosts=$(plak_server_parse_hosts)

    if [ -z "$hosts" ]; then
        plak_ui_warn "No SSH hosts found in $PLAK_SSH_CONFIG."
        return 0
    fi

    selected=$(echo "$hosts" | gum filter --placeholder "Choose SSH host to delete")
    [ -n "$selected" ] || return 0

    if ! gum confirm "Delete SSH connection '$selected'?"; then
        plak_ui_warn "Cancelled."
        return 0
    fi

    if plak_server_remove_config "$selected"; then
        plak_ui_success "SSH connection '$selected' deleted."
    else
        plak_ui_error "Could not delete SSH connection '$selected'."
        exit 1
    fi
}

plak_server() {
    local action="${1:-help}"
    if [ "$#" -gt 0 ]; then
        shift
    fi

    case "$action" in
        list|view)
            plak_server_list "$@"
            ;;
        connect)
            plak_server_connect "$@"
            ;;
        add|create)
            plak_server_add "$@"
            ;;
        delete|remove)
            plak_server_delete "$@"
            ;;
        help|--help|-h)
            plak_display_command_help server
            ;;
        *)
            plak_ui_error "Unknown server action '$action'"
            plak_display_command_help server
            exit 1
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
    plak_require_gum

    plak_ui_title "Create SSH key"

    local ssh_dir key_name key_path key_type bits passphrase overwrite=false
    ssh_dir="$HOME/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    while true; do
        key_name=$(gum input --prompt "Key name: " --value "id_ed25519")
        [ -n "$key_name" ] || return 0
        if [[ "$key_name" == */* || "$key_name" == .* ]]; then
            plak_ui_error "Use a file name only, without slashes or leading dots."
            continue
        fi
        break
    done

    key_path="$ssh_dir/$key_name"
    if [ -e "$key_path" ] || [ -e "$key_path.pub" ]; then
        if gum confirm "Key '$key_name' already exists. Overwrite?"; then
            overwrite=true
        else
            plak_ui_warn "Cancelled."
            return 0
        fi
    fi

    key_type=$(gum choose "ed25519" "rsa" "ecdsa")
    bits=""
    if [ "$key_type" = "rsa" ]; then
        bits=$(gum choose "4096" "2048")
    fi

    passphrase=$(gum input --password --placeholder "Passphrase (empty for none)")

    if [ "$overwrite" = true ]; then
        rm -f "$key_path" "$key_path.pub"
    fi

    local cmd=(ssh-keygen -t "$key_type" -f "$key_path" -N "$passphrase")
    if [ -n "$bits" ]; then
        cmd=(ssh-keygen -t "$key_type" -b "$bits" -f "$key_path" -N "$passphrase")
    fi

    if "${cmd[@]}"; then
        chmod 600 "$key_path"
        [ -f "$key_path.pub" ] && chmod 644 "$key_path.pub"
        plak_ui_success "SSH key '$key_name' created."
        echo ""
        plak_sshkey_show_details "$key_path"
    else
        plak_ui_error "ssh-keygen failed."
        return 1
    fi
}

plak_sshkey_delete() {
    plak_require_gum

    local keys selected
    keys=$(plak_sshkey_private_keys)
    if [ -z "$keys" ]; then
        plak_ui_warn "No SSH keys found in $HOME/.ssh."
        return 0
    fi

    selected=$(echo "$keys" | gum filter --placeholder "Choose SSH key to delete")
    [ -n "$selected" ] || return 0

    if ! gum confirm "Delete '$(basename "$selected")' and its .pub file?"; then
        plak_ui_warn "Cancelled."
        return 0
    fi

    rm -f "$selected" "$selected.pub"
    plak_ui_success "SSH key '$(basename "$selected")' deleted."
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
    plak_ui_title "Plak status"
    echo ""
    echo "OS:          $PLAK_OS"
    echo "Plak home:   $PLAK_HOME"
    echo "SSH config:  $PLAK_SSH_CONFIG"
    echo "Hosts file:  $PLAK_HOSTS_FILE"
    echo ""
    echo "Dependencies:"

    local dep status
    for dep in gum ssh ssh-keygen awk sed grep mktemp; do
        if plak_command_exists "$dep"; then
            status="found"
        else
            status="missing"
        fi
        printf '  %-10s %s\n' "$dep" "$status"
    done
}

# Source: commands/version
plak_version() {
    echo "$PLAK_NAME v$PLAK_VERSION"
}

# Pass all script arguments to the main function.
main "$@"
