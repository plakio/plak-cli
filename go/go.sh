#!/usr/bin/env bash

set -euo pipefail

PLAK_CLI_GO_VERSION="0.1.0"

go_usage() {
    cat <<'EOF'
Plak CLI Go

Portable WordPress operations for remote servers. It is designed to be used
without installing Plak CLI on the remote machine.

Alias:
  alias _go='curl -sL https://plak.sh/go | bash -s'

Usage:
  _go <command> [arguments] [--flags]

Commands:
  backup              Create a full WordPress backup ZIP.
  checkpoint          Manage file checkpoints with git.
  clean               Clean inactive plugins/themes or inspect disk usage.
  convert-to-webp     Convert JPG/PNG images to WebP.
  cron                Manage Plak CLI Go cron jobs.
  db backup           Create a database-only backup.
  db check-autoload   Report autoloaded options size.
  db optimize         Convert MyISAM tables, show large tables, clean transients.
  dump                Concatenate matching files for agent context.
  email               Send an email through wp_mail.
  find recent-files   List recently modified files.
  find slow-plugins   Measure active plugin impact on WP-CLI bootstrap time.
  find hidden-plugins Detect plugins hidden from the normal active list.
  find malware        Scan for suspicious PHP patterns and verify checksums.
  find php-tags       Find outdated PHP short tags.
  https               Replace site URLs with https:// URLs.
  login               Generate a temporary one-click WordPress login URL.
  migrate             Restore a WordPress backup.
  monitor             Monitor common access/error logs.
  reset               Reset permissions or WordPress.
  suspend             Add or remove a neutral suspension MU plugin.
  update              Run WordPress updates with checkpoints.
  vault               Manage restic snapshots.
  version             Show Plak CLI Go version.
  wpcli check         Diagnose WP-CLI warnings.
  zip                 Create a ZIP archive.
  help                Show this help text.

Examples:
  _go help
  _go backup . --quiet
  _go convert-to-webp wp-content/uploads --install-cwebp
  _go db backup
  _go db check-autoload
  _go find slow-plugins
  _go login admin --raw
  _go migrate --url=https://example.com/backup.zip --update-urls
EOF
}

go_command_help() {
    case "${1:-}" in
        backup)
            echo "Usage: _go backup <folder> [--quiet] [--format=filename] [--exclude=<pattern>]"
            ;;
        checkpoint)
            echo "Usage: _go checkpoint <create|list|show|revert|latest> [hash] [--yes]"
            ;;
        clean)
            echo "Usage: _go clean <plugins|themes|disk> [--yes]"
            ;;
        db)
            echo "Usage: _go db <backup|check-autoload|optimize>"
            ;;
        dump)
            echo "Usage: _go dump <pattern> [--output=<file>] [--exclude=<pattern>]"
            ;;
        convert-to-webp)
            echo "Usage: _go convert-to-webp [path] [--install-cwebp] [--quality=<1-100>] [--all] [--dry-run]"
            ;;
        cron)
            echo "Usage: _go cron <list|add|delete|run> [arguments]"
            ;;
        email)
            echo "Usage: _go email --to=<email> --subject=<subject> [--content=<html>] [--content-file=<file>]"
            ;;
        find)
            echo "Usage: _go find <recent-files|slow-plugins|hidden-plugins|malware|php-tags> [arguments]"
            ;;
        https)
            echo "Usage: _go https [--www|--no-www] [--yes]"
            ;;
        login)
            echo "Usage: _go login <user-id|user-login|email> [--expires=<seconds>] [--raw]"
            ;;
        migrate)
            echo "Usage: _go migrate --url=<backup.zip> [--update-urls]"
            ;;
        monitor)
            echo "Usage: _go monitor <errors|access.log|error.log|traffic> [--now] [--top=<n>]"
            ;;
        reset)
            echo "Usage: _go reset <permissions|wp> [--admin-user=<user>] [--yes]"
            ;;
        suspend)
            echo "Usage: _go suspend <activate|deactivate> [--name=<name>] [--link=<url>]"
            ;;
        update)
            echo "Usage: _go update <all|list>"
            ;;
        vault)
            echo "Usage: _go vault <create|snapshots|info|prune>"
            ;;
        wpcli)
            echo "Usage: _go wpcli check"
            ;;
        zip)
            echo "Usage: _go zip <path> [--output=<file>]"
            ;;
        *)
            go_usage
            ;;
    esac
}

go_main() {
    local command="${1:-help}"
    if [ "$#" -gt 0 ]; then
        shift
    fi

    case "$command" in
        backup)
            go_backup "$@"
            ;;
        checkpoint)
            go_checkpoint "$@"
            ;;
        clean)
            go_clean "$@"
            ;;
        convert-to-webp)
            go_convert_to_webp "$@"
            ;;
        cron)
            go_cron "$@"
            ;;
        db)
            local subcommand="${1:-}"
            [ "$#" -gt 0 ] && shift
            case "$subcommand" in
                backup)
                    go_db_backup "$@"
                    ;;
                check-autoload)
                    go_db_check_autoload "$@"
                    ;;
                optimize)
                    go_db_optimize "$@"
                    ;;
                help|--help|-h|"")
                    go_command_help db
                    ;;
                *)
                    go_error "Unknown db command: $subcommand"
                    go_command_help db >&2
                    return 1
                    ;;
            esac
            ;;
        dump)
            go_dump "$@"
            ;;
        email)
            go_email "$@"
            ;;
        find)
            local subcommand="${1:-}"
            [ "$#" -gt 0 ] && shift
            case "$subcommand" in
                recent-files)
                    go_find_recent_files "$@"
                    ;;
                slow-plugins)
                    go_find_slow_plugins "$@"
                    ;;
                hidden-plugins)
                    go_find_hidden_plugins "$@"
                    ;;
                malware)
                    go_find_malware "$@"
                    ;;
                php-tags)
                    go_find_php_tags "$@"
                    ;;
                help|--help|-h|"")
                    go_command_help find
                    ;;
                *)
                    go_error "Unknown find command: $subcommand"
                    go_command_help find >&2
                    return 1
                    ;;
            esac
            ;;
        https)
            go_https "$@"
            ;;
        login)
            go_login "$@"
            ;;
        migrate)
            go_migrate "$@"
            ;;
        monitor)
            go_monitor "$@"
            ;;
        reset)
            go_reset "$@"
            ;;
        suspend)
            go_suspend "$@"
            ;;
        update)
            go_update "$@"
            ;;
        vault)
            go_vault "$@"
            ;;
        version)
            go_version
            ;;
        wpcli)
            local subcommand="${1:-}"
            [ "$#" -gt 0 ] && shift
            case "$subcommand" in
                check)
                    go_wpcli_check "$@"
                    ;;
                help|--help|-h|"")
                    go_command_help wpcli
                    ;;
                *)
                    go_error "Unknown wpcli command: $subcommand"
                    go_command_help wpcli >&2
                    return 1
                    ;;
            esac
            ;;
        zip)
            go_zip "$@"
            ;;
        help)
            if [ "${1:-}" != "" ]; then
                go_command_help "$1"
            else
                go_usage
            fi
            ;;
        *)
            go_error "Unknown command: $command"
            go_usage >&2
            exit 1
            ;;
    esac
}


# --- Shared Helpers ---
# Source: shared/archive
go_require_command() {
    local command="$1"
    if ! command -v "$command" >/dev/null 2>&1; then
        go_error "Required command not found: $command"
        return 1
    fi
}

go_download_file() {
    local url="$1"
    local output="$2"

    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress --no-check-certificate --progress=bar:force:noscroll -O "$output" "$url"
        return $?
    fi

    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar -o "$output" "$url"
        return $?
    fi

    go_error "Either wget or curl is required to download backups."
    return 1
}

# Source: shared/logging
go_error() {
    echo "Error: $*" >&2
}

go_info() {
    echo "$*"
}

go_filter_insecure_mysql_warning() {
    grep -v -F "WARNING: option --ssl-verify-server-cert is disabled, because of an insecure passwordless login." || true
}

# Source: shared/private-dir
go_private_dir() {
    if [ -n "${RUNNER_PRIVATE_DIR:-}" ]; then
        echo "$RUNNER_PRIVATE_DIR"
        return 0
    fi

    local wp_cmd
    if wp_cmd=$(go_wp_cli 2>/dev/null) && "$wp_cmd" core is-installed --quiet 2>/dev/null; then
        local wp_config_path
        wp_config_path=$("$wp_cmd" config path --quiet 2>/dev/null || true)
        if [ -n "$wp_config_path" ] && [ -f "$wp_config_path" ]; then
            local wp_root
            local parent_dir
            wp_root=$(dirname "$wp_config_path")
            parent_dir=$(dirname "$wp_root")

            if [ -d "${wp_root}/_wpeprivate" ]; then
                RUNNER_PRIVATE_DIR="${wp_root}/_wpeprivate"
                echo "$RUNNER_PRIVATE_DIR"
                return 0
            fi

            if [ -d "${parent_dir}/_wpeprivate" ]; then
                RUNNER_PRIVATE_DIR="${parent_dir}/_wpeprivate"
                echo "$RUNNER_PRIVATE_DIR"
                return 0
            fi

            if [ -d "${parent_dir}/private" ]; then
                RUNNER_PRIVATE_DIR="${parent_dir}/private"
                echo "$RUNNER_PRIVATE_DIR"
                return 0
            fi

            if mkdir -p "${parent_dir}/private" 2>/dev/null; then
                RUNNER_PRIVATE_DIR="${parent_dir}/private"
                echo "$RUNNER_PRIVATE_DIR"
                return 0
            fi

            if [ -d "${parent_dir}/tmp" ]; then
                RUNNER_PRIVATE_DIR="${parent_dir}/tmp"
                echo "$RUNNER_PRIVATE_DIR"
                return 0
            fi
        fi
    fi

    local current_dir
    current_dir=$(pwd)

    if [ -d "${current_dir}/_wpeprivate" ]; then
        RUNNER_PRIVATE_DIR="${current_dir}/_wpeprivate"
        echo "$RUNNER_PRIVATE_DIR"
        return 0
    fi

    if [ -d "../private" ]; then
        RUNNER_PRIVATE_DIR=$(cd ../private && pwd)
        echo "$RUNNER_PRIVATE_DIR"
        return 0
    fi

    if mkdir -p "../private" 2>/dev/null; then
        RUNNER_PRIVATE_DIR=$(cd ../private && pwd)
        echo "$RUNNER_PRIVATE_DIR"
        return 0
    fi

    if [ -d "../tmp" ]; then
        RUNNER_PRIVATE_DIR=$(cd ../tmp && pwd)
        echo "$RUNNER_PRIVATE_DIR"
        return 0
    fi

    if mkdir -p "$HOME/private" 2>/dev/null; then
        RUNNER_PRIVATE_DIR="$HOME/private"
        echo "$RUNNER_PRIVATE_DIR"
        return 0
    fi

    go_error "Could not find or create a writable private directory."
    return 1
}

# Source: shared/wp-cli
go_wp_cli() {
    if [ -n "${RUNNER_WP_CLI_CMD:-}" ]; then
        echo "$RUNNER_WP_CLI_CMD"
        return 0
    fi

    if command -v wp >/dev/null 2>&1; then
        RUNNER_WP_CLI_CMD="wp"
        echo "$RUNNER_WP_CLI_CMD"
        return 0
    fi

    local candidate
    for candidate in "/usr/local/bin/wp" "$HOME/bin/wp" "/opt/wp-cli/wp"; do
        if [ -x "$candidate" ]; then
            RUNNER_WP_CLI_CMD="$candidate"
            echo "$RUNNER_WP_CLI_CMD"
            return 0
        fi
    done

    go_error "WP-CLI is required but was not found."
    return 1
}

# --- Command Functions ---
# Source: commands/backup
go_backup() {
    local target_folder=""
    local quiet_flag="false"
    local format_flag=""
    local exclude_patterns=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --quiet)
                quiet_flag="true"
                shift
                ;;
            --format=*)
                format_flag="${1#*=}"
                shift
                ;;
            --exclude=*)
                exclude_patterns+=("${1#*=}")
                shift
                ;;
            -*)
                go_error "Unknown backup flag: $1"
                return 1
                ;;
            *)
                if [ -z "$target_folder" ]; then
                    target_folder="$1"
                else
                    go_error "Unexpected backup argument: $1"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [ -z "$target_folder" ]; then
        go_error "Please provide a folder path."
        go_error "Usage: _go backup <folder> [--quiet] [--format=filename] [--exclude=<pattern>]"
        return 1
    fi

    if [ ! -d "$target_folder" ]; then
        go_error "Folder '$target_folder' not found."
        return 1
    fi

    go_require_command zip || return 1
    go_require_command openssl || return 1

    local wp_cmd
    wp_cmd=$(go_wp_cli) || return 1

    local full_target_path
    full_target_path=$(cd "$target_folder" && pwd -P) || return 1
    local parent_dir
    parent_dir=$(dirname "$full_target_path")
    local site_dir_name
    site_dir_name=$(basename "$full_target_path")
    local original_dir
    original_dir=$(pwd)

    local today
    local random
    local backup_filename
    today=$(date +"%Y-%m-%d")
    random=$(openssl rand -hex 4 | head -c 7)
    backup_filename="${today}_${random}.zip"

    cd "$parent_dir" || return 1

    local home_url
    local name
    local database_file="db_export.sql"
    home_url=$("$wp_cmd" option get home --path="$site_dir_name" --skip-plugins --skip-themes 2> >(go_filter_insecure_mysql_warning >&2))
    name=$("$wp_cmd" option get blogname --path="$site_dir_name" --skip-plugins --skip-themes 2> >(go_filter_insecure_mysql_warning >&2))

    if [ "$quiet_flag" != "true" ]; then
        echo "Exporting database for '$name'..."
    fi

    if ! "$wp_cmd" db export "$site_dir_name/$database_file" --path="$site_dir_name" --add-drop-table --default-character-set=utf8mb4 >/dev/null 2> >(go_filter_insecure_mysql_warning >&2); then
        go_error "Database export failed."
        cd "$original_dir"
        return 1
    fi

    if [ "$quiet_flag" != "true" ]; then
        echo "Creating zip archive..."
        if [ "${#exclude_patterns[@]}" -gt 0 ]; then
            echo "Excluding the following patterns:"
            local pattern
            for pattern in "${exclude_patterns[@]}"; do
                echo "  - $pattern"
            done
        fi
    fi

    local zip_exclude_args=()
    zip_exclude_args+=(-x "$site_dir_name/wp-content/updraft/*")
    local pattern
    for pattern in "${exclude_patterns[@]}"; do
        zip_exclude_args+=(-x "$site_dir_name/$pattern*")
    done

    if ! zip -r "$backup_filename" "$site_dir_name" "${zip_exclude_args[@]}" >/dev/null; then
        go_error "Failed to zip files."
        rm -f "$site_dir_name/$database_file"
        cd "$original_dir"
        return 1
    fi

    if [ -f "$site_dir_name/wp-config.php" ]; then
        zip "$backup_filename" "$site_dir_name/wp-config.php" >/dev/null
    fi

    local size
    size=$(ls -lh "$backup_filename" | awk '{print $5}')
    rm -f "$site_dir_name/$database_file"
    mv "$backup_filename" "$site_dir_name/"
    cd "$original_dir"

    local final_backup_location="$full_target_path/$backup_filename"
    local final_url="${home_url%/}/${backup_filename}"

    if [ "$format_flag" = "filename" ]; then
        echo "$backup_filename"
        return 0
    fi

    if [ "$quiet_flag" = "true" ]; then
        echo "$final_url"
        return 0
    fi

    echo "-----------------------------------------------------"
    echo "Full site backup complete."
    echo "   Name: $name"
    echo "   Location: $final_backup_location"
    echo "   Size: $size"
    echo "   URL: $final_url"
    echo "-----------------------------------------------------"
    echo "When done, remember to remove the backup file."
    echo "rm -f \"$final_backup_location\""
}

# Source: commands/checkpoint
go_checkpoint() {
    local action="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$action" in
        create) go_checkpoint_create "$@" ;;
        list) go_checkpoint_list ;;
        latest) go_checkpoint_latest ;;
        show) go_checkpoint_show "${1:-}" ;;
        revert) go_checkpoint_revert "$@" ;;
        -h|--help|"") echo "Usage: _go checkpoint <create|list|show|revert|latest> [hash] [--yes]" ;;
        *) go_error "Unknown checkpoint command: $action"; return 1 ;;
    esac
}

go_checkpoint_git_ready() {
    go_require_command git || return 1
    if [ ! -d .git ]; then
        git init >/dev/null
        git config user.name "Plak CLI Go" >/dev/null
        git config user.email "go@plak.sh" >/dev/null
    fi
}

go_checkpoint_create() {
    go_checkpoint_git_ready || return 1
    git add wp-admin wp-includes wp-content index.php wp-*.php .htaccess 2>/dev/null || true
    if git diff --cached --quiet; then echo "No file changes to checkpoint."; return 0; fi
    git commit -m "Plak checkpoint $(date +%Y-%m-%d-%H%M%S)" >/dev/null
    git rev-parse --short HEAD
}

go_checkpoint_list() { go_checkpoint_git_ready || return 1; git log --oneline -20; }
go_checkpoint_latest() { go_checkpoint_git_ready || return 1; git rev-parse --short HEAD; }
go_checkpoint_show() { [ -n "$1" ] || { go_error "Missing checkpoint hash."; return 1; }; git show --stat "$1"; }

go_checkpoint_revert() {
    local hash="" yes=false
    while [ "$#" -gt 0 ]; do case "$1" in --yes|-y) yes=true ;; *) hash="$1" ;; esac; shift; done
    [ -n "$hash" ] || { go_error "Missing checkpoint hash."; return 1; }
    $yes || { go_error "Reverting files is destructive. Re-run with --yes."; return 1; }
    git checkout "$hash" -- wp-admin wp-includes wp-content index.php wp-*.php .htaccess 2>/dev/null || return 1
    echo "Reverted files to checkpoint ${hash}."
}

# Source: commands/clean
go_clean() {
    local action="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$action" in
        plugins) go_clean_plugins "$@" ;;
        themes) go_clean_themes "$@" ;;
        disk) go_clean_disk "$@" ;;
        -h|--help|"") echo "Usage: _go clean <plugins|themes|disk> [--yes]" ;;
        *) go_error "Unknown clean command: $action"; return 1 ;;
    esac
}

go_clean_plugins() {
    local yes=false
    [ "${1:-}" = "--yes" ] && yes=true
    local wp_cmd plugins=() plugin
    wp_cmd=$(go_wp_cli) || return 1
    while IFS= read -r plugin; do [ -n "$plugin" ] && plugins+=("$plugin"); done < <("$wp_cmd" plugin list --status=inactive --field=name)
    if [ "${#plugins[@]}" -eq 0 ]; then echo "No inactive plugins found."; return 0; fi
    printf '%s\n' "${plugins[@]}"
    $yes || { go_error "Re-run with --yes to delete inactive plugins."; return 1; }
    "$wp_cmd" plugin delete "${plugins[@]}"
}

go_clean_themes() {
    local yes=false
    [ "${1:-}" = "--yes" ] && yes=true
    local wp_cmd active template themes=() theme
    wp_cmd=$(go_wp_cli) || return 1
    active=$("$wp_cmd" option get stylesheet --skip-plugins --skip-themes 2>/dev/null || true)
    template=$("$wp_cmd" option get template --skip-plugins --skip-themes 2>/dev/null || true)
    while IFS= read -r theme; do
        [ -n "$theme" ] || continue
        [ "$theme" = "$active" ] && continue
        [ "$theme" = "$template" ] && continue
        themes+=("$theme")
    done < <("$wp_cmd" theme list --field=name)
    if [ "${#themes[@]}" -eq 0 ]; then echo "No inactive themes found."; return 0; fi
    printf '%s\n' "${themes[@]}"
    $yes || { go_error "Re-run with --yes to delete inactive themes."; return 1; }
    "$wp_cmd" theme delete "${themes[@]}"
}

go_clean_disk() {
    local path="${1:-.}"
    [ -d "$path" ] || { go_error "Directory not found: $path"; return 1; }
    du -sh "$path"/* 2>/dev/null | sort -hr | head -n 30
}

# Source: commands/convert-to-webp
go_cwebp_command() {
    local install_flag="$1"

    if command -v cwebp >/dev/null 2>&1; then
        command -v cwebp
        return 0
    fi

    local private_dir cwebp_path
    private_dir=$(go_private_dir) || return 1
    cwebp_path="${private_dir}/bin/cwebp"
    if [ -x "$cwebp_path" ]; then
        echo "$cwebp_path"
        return 0
    fi

    if [ "$install_flag" != "true" ]; then
        go_error "cwebp was not found. Re-run with --install-cwebp to install it locally."
        return 1
    fi

    go_require_command tar || return 1
    mkdir -p "${private_dir}/bin" "${private_dir}/tmp"

    local os arch archive_url archive_file extract_dir found_cwebp
    os=$(uname -s)
    arch=$(uname -m)

    case "${os}-${arch}" in
        Linux-x86_64|Linux-amd64)
            archive_url="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.5.0-linux-x86-64.tar.gz"
            ;;
        Darwin-x86_64)
            archive_url="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.5.0-mac-x86-64.tar.gz"
            ;;
        *)
            go_error "Automatic cwebp install is not available for ${os}/${arch}. Install cwebp manually or add it to PATH."
            return 1
            ;;
    esac

    archive_file="${private_dir}/tmp/libwebp.tar.gz"
    extract_dir="${private_dir}/tmp/libwebp"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"

    echo "Installing cwebp locally into ${private_dir}/bin..." >&2
    if ! go_download_file "$archive_url" "$archive_file"; then
        go_error "Failed to download cwebp."
        return 1
    fi

    if ! tar -xzf "$archive_file" -C "$extract_dir"; then
        rm -f "$archive_file"
        go_error "Failed to extract cwebp archive."
        return 1
    fi

    found_cwebp=$(find "$extract_dir" -type f -name cwebp -perm -u+x -print -quit)
    if [ -z "$found_cwebp" ]; then
        found_cwebp=$(find "$extract_dir" -type f -name cwebp -print -quit)
    fi
    if [ -z "$found_cwebp" ]; then
        rm -f "$archive_file"
        rm -rf "$extract_dir"
        go_error "Downloaded archive did not contain cwebp."
        return 1
    fi

    cp "$found_cwebp" "$cwebp_path"
    chmod +x "$cwebp_path"
    rm -f "$archive_file"
    rm -rf "$extract_dir"
    echo "$cwebp_path"
}

go_convert_to_webp() {
    local target_path="wp-content/uploads"
    local install_cwebp=false
    local quality="82"
    local overwrite=false
    local dry_run=false

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --install-cwebp)
                install_cwebp=true
                ;;
            --quality=*)
                quality="${1#*=}"
                ;;
            --all)
                overwrite=true
                ;;
            --dry-run)
                dry_run=true
                ;;
            -h|--help)
                echo "Usage: _go convert-to-webp [path] [--install-cwebp] [--quality=<1-100>] [--all] [--dry-run]"
                return 0
                ;;
            -* )
                go_error "Unknown convert-to-webp flag: $1"
                return 1
                ;;
            *)
                target_path="$1"
                ;;
        esac
        shift
    done

    [ -d "$target_path" ] || { go_error "Directory not found: $target_path"; return 1; }
    [[ "$quality" =~ ^[0-9]+$ ]] || { go_error "--quality must be a number from 1 to 100."; return 1; }
    [ "$quality" -ge 1 ] && [ "$quality" -le 100 ] || { go_error "--quality must be between 1 and 100."; return 1; }

    local cwebp_cmd=""
    if ! $dry_run; then
        cwebp_cmd=$(go_cwebp_command "$install_cwebp") || return 1
    fi

    local converted=0 skipped=0 failed=0 source_file output_file
    echo "Converting images in ${target_path} with quality ${quality}..."

    while IFS= read -r -d '' source_file; do
        output_file="${source_file%.*}.webp"
        if [ -f "$output_file" ] && [ "$overwrite" != "true" ]; then
            echo "skipped: ${output_file} already exists"
            skipped=$((skipped + 1))
            continue
        fi

        if $dry_run; then
            echo "would convert: ${source_file} -> ${output_file}"
            continue
        fi

        if "$cwebp_cmd" -quiet -q "$quality" "$source_file" -o "$output_file"; then
            echo "converted: ${source_file} -> ${output_file}"
            converted=$((converted + 1))
        else
            echo "failed: ${source_file}"
            failed=$((failed + 1))
        fi
    done < <(find "$target_path" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0)

    echo "Done. Converted: ${converted}. Skipped: ${skipped}. Failed: ${failed}."
    [ "$failed" -eq 0 ]
}

# Source: commands/cron
go_cron() {
    local action="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$action" in
        list) crontab -l 2>/dev/null | grep 'plak.sh/go' || true ;;
        add) go_cron_add "$@" ;;
        delete) go_cron_delete "$@" ;;
        run) go_main "$@" ;;
        -h|--help|"") echo "Usage: _go cron <list|add|delete|run> [command] [schedule]" ;;
        *) go_error "Unknown cron command: $action"; return 1 ;;
    esac
}

go_cron_add() {
    local command_string="${1:-}" schedule="${2:-0 4 * * *}"
    [ -n "$command_string" ] || { go_error "Usage: _go cron add '<command>' ['0 4 * * *']"; return 1; }
    local line="${schedule} cd $(pwd) && curl -sL https://plak.sh/go | bash -s ${command_string} # plak.sh/go"
    (crontab -l 2>/dev/null; echo "$line") | crontab -
    echo "Cron added: ${line}"
}

go_cron_delete() {
    local match="${1:-plak.sh/go}"
    crontab -l 2>/dev/null | grep -v "$match" | crontab -
    echo "Cron entries matching '${match}' removed."
}

# Source: commands/db
go_db_backup() {
    local quiet=false

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --quiet)
                quiet=true
                shift
                ;;
            -h|--help)
                echo "Usage: _go db backup [--quiet]"
                return 0
                ;;
            *)
                go_error "Unknown db backup argument: $1"
                return 1
                ;;
        esac
    done

    local wp_cmd private_dir database_name database_username database_password database_host database_port dump_command backup_file
    wp_cmd=$(go_wp_cli) || return 1
    "$wp_cmd" core is-installed --quiet || { go_error "This does not appear to be a WordPress installation."; return 1; }

    private_dir=$(go_private_dir) || return 1
    database_name=$("$wp_cmd" config get DB_NAME --skip-plugins --skip-themes --quiet)
    database_username=$("$wp_cmd" config get DB_USER --skip-plugins --skip-themes --quiet)
    database_password=$("$wp_cmd" config get DB_PASSWORD --skip-plugins --skip-themes --quiet)
    database_host=$("$wp_cmd" config get DB_HOST --skip-plugins --skip-themes --quiet 2>/dev/null || echo "localhost")
    database_port="3306"

    if [[ "$database_host" == *:* ]]; then
        database_port="${database_host##*:}"
        database_host="${database_host%:*}"
    fi

    if command -v mariadb-dump >/dev/null 2>&1; then
        dump_command="mariadb-dump"
    elif command -v mysqldump >/dev/null 2>&1; then
        dump_command="mysqldump"
    else
        go_error "Neither mariadb-dump nor mysqldump could be found."
        return 1
    fi

    backup_file="${private_dir}/database-backup-$(date +"%Y-%m-%d-%H%M%S").sql"
    $quiet || echo "Creating database backup with ${dump_command}..."

    if ! "${dump_command}" -h"${database_host}" -P"${database_port}" -u"${database_username}" -p"${database_password}" --max_allowed_packet=512M --default-character-set=utf8mb4 --add-drop-table --single-transaction --quick --lock-tables=false "${database_name}" > "${backup_file}"; then
        rm -f "${backup_file}"
        go_error "Database dump failed."
        return 1
    fi

    chmod 600 "${backup_file}"
    if $quiet; then
        echo "${backup_file}"
    else
        echo "Database backup complete: ${backup_file}"
    fi
}

go_db_check_autoload() {
    local wp_cmd prefix
    wp_cmd=$(go_wp_cli) || return 1
    "$wp_cmd" core is-installed --quiet || { go_error "This does not appear to be a WordPress installation."; return 1; }
    prefix=$("$wp_cmd" db prefix --skip-plugins --skip-themes)

    echo "Total autoloaded size:"
    "$wp_cmd" db query "SELECT ROUND(SUM(LENGTH(option_value))/1024/1024, 2) AS 'Autoload MB', COUNT(*) AS 'Count' FROM ${prefix}options WHERE autoload IN ('yes', 'on');" --skip-plugins --skip-themes
    echo
    echo "Top 25 autoloaded options:"
    "$wp_cmd" db query "SELECT option_name, ROUND(LENGTH(option_value)/1024/1024, 2) AS 'Size MB' FROM ${prefix}options WHERE autoload IN ('yes', 'on') ORDER BY LENGTH(option_value) DESC LIMIT 25;" --skip-plugins --skip-themes
}

go_db_optimize() {
    local wp_cmd myisam_queries
    wp_cmd=$(go_wp_cli) || return 1
    "$wp_cmd" core is-installed --quiet || { go_error "This does not appear to be a WordPress installation."; return 1; }

    echo "Checking for MyISAM tables..."
    myisam_queries=$("$wp_cmd" db query "SELECT CONCAT('ALTER TABLE `', TABLE_NAME, '` ENGINE=InnoDB;') FROM information_schema.TABLES WHERE ENGINE = 'MyISAM' AND TABLE_SCHEMA = DATABASE();" --skip-column-names --skip-plugins --skip-themes)
    if [ -n "$myisam_queries" ]; then
        echo "Converting MyISAM tables to InnoDB..."
        echo "$myisam_queries" | "$wp_cmd" db query --skip-plugins --skip-themes
    else
        echo "All tables already use InnoDB."
    fi

    echo
    echo "Top 10 tables larger than 1 MB:"
    "$wp_cmd" db query "SELECT TABLE_NAME, CASE WHEN (data_length + index_length) >= 1073741824 THEN CONCAT(ROUND((data_length + index_length) / 1073741824, 2), ' GB') WHEN (data_length + index_length) >= 1048576 THEN CONCAT(ROUND((data_length + index_length) / 1048576, 2), ' MB') WHEN (data_length + index_length) >= 1024 THEN CONCAT(ROUND((data_length + index_length) / 1024, 2), ' KB') ELSE CONCAT((data_length + index_length), ' B') END AS Size FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND (data_length + index_length) > 1048576 ORDER BY (data_length + index_length) DESC LIMIT 10;" --skip-plugins --skip-themes

    echo
    echo "Deleting expired transients..."
    "$wp_cmd" transient delete --expired
    echo "Database optimization complete."
}

# Source: commands/dump
go_dump() {
    local pattern="" output="" max_file_size=204800 max_total_size=2097152 exclude_patterns=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --output=*) output="${1#*=}" ;;
            --exclude=*) exclude_patterns+=("${1#*=}") ;;
            --max-file-size=*) max_file_size="${1#*=}" ;;
            --max-total-size=*) max_total_size="${1#*=}" ;;
            -x)
                shift
                [ "$#" -gt 0 ] || { go_error "Missing pattern after -x."; return 1; }
                exclude_patterns+=("$1")
                ;;
            -h|--help)
                echo "Usage: _go dump <pattern> [--output=<file>] [--exclude=<pattern>] [--max-file-size=<bytes>] [--max-total-size=<bytes>]"
                return 0
                ;;
            -* ) go_error "Unknown dump flag: $1"; return 1 ;;
            *)
                [ -z "$pattern" ] || { go_error "Unexpected dump argument: $1"; return 1; }
                pattern="$1"
                ;;
        esac
        shift
    done

    [ -n "$pattern" ] || { go_error "Please provide a quoted file pattern."; return 1; }
    [[ "$max_file_size" =~ ^[0-9]+$ ]] || { go_error "--max-file-size must be bytes."; return 1; }
    [[ "$max_total_size" =~ ^[0-9]+$ ]] || { go_error "--max-total-size must be bytes."; return 1; }

    local total=0 count=0 skipped=0 file size excluded
    local tmp_output=""
    if [ -n "$output" ]; then
        tmp_output="${output}.tmp"
        : > "$tmp_output"
    fi

    while IFS= read -r file; do
        [ -f "$file" ] || continue
        excluded=false
        local ex
        for ex in "${exclude_patterns[@]}"; do
            case "$file" in $ex|./$ex) excluded=true ;; esac
        done
        if $excluded; then skipped=$((skipped + 1)); continue; fi

        size=$(wc -c < "$file" | tr -d ' ')
        if [ "$size" -gt "$max_file_size" ]; then skipped=$((skipped + 1)); continue; fi
        if [ $((total + size)) -gt "$max_total_size" ]; then skipped=$((skipped + 1)); continue; fi

        {
            echo "===== ${file} ====="
            sed -n '1,2000p' "$file"
            echo
        } | if [ -n "$tmp_output" ]; then tee -a "$tmp_output" >/dev/null; else cat; fi
        total=$((total + size))
        count=$((count + 1))
    done < <(find . \( -path "./$pattern" -o -name "$pattern" \) -type f 2>/dev/null | sort)

    if [ -n "$output" ]; then
        mv "$tmp_output" "$output"
        echo "Dump written to ${output}. Files: ${count}. Skipped: ${skipped}. Bytes: ${total}."
    else
        echo "Dump complete. Files: ${count}. Skipped: ${skipped}. Bytes: ${total}." >&2
    fi
}

# Source: commands/email
go_email() {
    local to_email="" subject="" content="" content_file=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --to=*) to_email="${1#*=}" ;;
            --subject=*) subject="${1#*=}" ;;
            --content=*) content="${1#*=}" ;;
            --content-file=*) content_file="${1#*=}" ;;
            -h|--help)
                echo "Usage: _go email --to=<email> --subject=<subject> [--content=<html>] [--content-file=<file>]"
                return 0
                ;;
            *)
                go_error "Unknown email argument: $1"
                return 1
                ;;
        esac
        shift
    done

    if [ -n "$content_file" ]; then
        [ -f "$content_file" ] || { go_error "Content file not found: $content_file"; return 1; }
        content=$(<"$content_file")
    elif [ -z "$content" ] && [ ! -t 0 ]; then
        content=$(cat)
    fi

    [ -n "$to_email" ] || { go_error "Missing --to=<email>."; return 1; }
    [ -n "$subject" ] || { go_error "Missing --subject=<subject>."; return 1; }
    [ -n "$content" ] || { go_error "Missing --content=<html>, --content-file=<file>, or stdin content."; return 1; }

    local wp_cmd php_file escaped_to escaped_subject escaped_content
    wp_cmd=$(go_wp_cli) || return 1
    "$wp_cmd" core is-installed --quiet || { go_error "This does not appear to be a WordPress installation."; return 1; }

    php_file=$(mktemp)
    escaped_to=$(printf "%s" "$to_email" | sed "s/'/'\\\\''/g")
    escaped_subject=$(printf "%s" "$subject" | sed "s/'/'\\\\''/g")
    escaped_content=$(printf "%s" "$content" | sed "s/'/'\\\\''/g")
    printf "if (! wp_mail('%s', '%s', '%s', ['Content-Type: text/html; charset=UTF-8'])) { exit(1); }\n" "$escaped_to" "$escaped_subject" "$escaped_content" > "$php_file"

    if "$wp_cmd" eval-file "$php_file"; then
        rm -f "$php_file"
        echo "Email command sent to ${to_email}."
        return 0
    fi

    rm -f "$php_file"
    go_error "wp_mail failed. Check WordPress mail configuration."
    return 1
}

# Source: commands/find
go_find_recent_files() {
    local days="${1:-1}"
    [[ "$days" =~ ^[0-9]+$ ]] || { go_error "Please provide a valid number of days."; return 1; }

    echo "Files modified in the last ${days} day(s):"
    if [ "$(uname)" = "Darwin" ]; then
        find . -type f -mtime "-${days}" -exec stat -f "%Sm %N" -t "%Y-%m-%d %H:%M:%S" {} + | sort -r
    else
        find . -type f -mtime "-${days}" -printf "%TY-%Tm-%Td %TH:%M:%S %p\n" | sort -r
    fi
}

go_find_slow_plugins() {
    local page_to_check="${1:-}"
    local wp_cmd
    wp_cmd=$(go_wp_cli) || return 1
    "$wp_cmd" core is-installed --quiet || { go_error "This does not appear to be a WordPress installation."; return 1; }

    go_wp_execution_time() {
        local output
        output=$("$wp_cmd" "$@" --debug 2>&1 || true)
        echo "$output" | perl -ne '/Debug \(bootstrap\): Running command: .+\(([^s]+s)/ && print $1' | tail -1
    }

    local base_command_args=("plugin" "list") skip_argument="--skip-plugins" description="wp plugin list --debug"
    if [ -n "$page_to_check" ]; then
        if ! "$wp_cmd" help render >/dev/null 2>&1; then
            go_error "wp render is required for page checks. Run without a page path or install render-command."
            return 1
        fi
        base_command_args=("render" "$page_to_check")
        skip_argument="--without-plugin"
        description="wp render ${page_to_check} --debug"
    fi

    echo "Measuring plugin impact for: ${description}"
    local base_time_s
    base_time_s=$(go_wp_execution_time "${base_command_args[@]}")
    [ -n "$base_time_s" ] || { go_error "Could not measure base execution time."; return 1; }
    echo "Base time: ${base_time_s}"

    local active_plugins=() plugin results=()
    while IFS= read -r plugin; do
        [ -n "$plugin" ] && active_plugins+=("$plugin")
    done < <("$wp_cmd" plugin list --field=name --status=active)

    printf "%-40s | %-15s | %-15s\n" "Plugin Skipped" "Time w/ Skip" "Impact"
    printf '%s\n' "---------------------------------------------------------------------------------"
    for plugin in "${active_plugins[@]}"; do
        local time_with_skip_s diff_s impact_sign=""
        time_with_skip_s=$(go_wp_execution_time "${base_command_args[@]}" "${skip_argument}=${plugin}")
        if [ -n "$time_with_skip_s" ]; then
            diff_s=$(awk -v base="${base_time_s%s}" -v skip="${time_with_skip_s%s}" 'BEGIN { printf "%.3f", base - skip }')
            if [ "$(awk -v diff="$diff_s" 'BEGIN { print (diff > 0) }')" -eq 1 ]; then impact_sign="+"; fi
            results+=("$(printf "%.3f" "$diff_s")|$plugin|$time_with_skip_s|${impact_sign}${diff_s}s")
        else
            results+=("0.000|$plugin|Error|Error")
        fi
    done

    printf "%s\n" "${results[@]}" | sort -t'|' -k1,1nr | while IFS='|' read -r _ plugin_name time_skip impact; do
        printf "%-40s | %-15s | %-15s\n" "$plugin_name" "$time_skip" "$impact"
    done
}

go_find_hidden_plugins() {
    local wp_cmd active_plugins active_plugins_raw regular_count raw_count hidden_plugins
    wp_cmd=$(go_wp_cli) || return 1
    "$wp_cmd" core is-installed --quiet || { go_error "This does not appear to be a WordPress installation."; return 1; }

    active_plugins=$("$wp_cmd" plugin list --field=name --status=active)
    active_plugins_raw=$("$wp_cmd" plugin list --field=name --status=active --skip-themes --skip-plugins)
    regular_count=$(printf "%s\n" "$active_plugins" | sed '/^$/d' | wc -l | tr -d ' ')
    raw_count=$(printf "%s\n" "$active_plugins_raw" | sed '/^$/d' | wc -l | tr -d ' ')

    if [ "$regular_count" = "$raw_count" ]; then
        echo "No hidden plugins detected. Active plugin counts match (${regular_count})."
        return 0
    fi

    echo "Plugin list discrepancy found. Standard: ${regular_count}; raw: ${raw_count}."
    hidden_plugins=$(comm -13 <(printf "%s\n" "$active_plugins" | sort) <(printf "%s\n" "$active_plugins_raw" | sort))
    if [ -n "$hidden_plugins" ]; then
        echo "Hidden plugin candidates:"
        echo "$hidden_plugins"
    fi
}

go_find_malware() {
    local wp_cmd combined_pattern search_results
    wp_cmd=$(go_wp_cli) || return 1
    "$wp_cmd" core is-installed --quiet || { go_error "This does not appear to be a WordPress installation."; return 1; }

    combined_pattern='eval\(base64_decode\(|eval\(gzinflate\(|eval\(gzuncompress\(|eval\(str_rot13\(|preg_replace.*\/e|create_function|FilesMan|c99shell|r57shell|shell_exec\(|passthru\(|system\(|phpinfo\(|assert\('
    search_results=$(grep -rn --include='*.php' -iE "$combined_pattern" . 2>/dev/null || true)
    if [ -n "$search_results" ]; then
        echo "Potentially suspicious PHP patterns found:"
        echo "$search_results"
    else
        echo "No suspicious PHP patterns found."
    fi

    echo
    echo "Verifying WordPress core checksums..."
    "$wp_cmd" core verify-checksums --skip-plugins --skip-themes || true
    echo
    echo "Verifying wordpress.org plugin checksums..."
    "$wp_cmd" plugin verify-checksums --all --skip-plugins --skip-themes || true
}

go_find_php_tags() {
    local search_dir="${1:-.}"
    [ -d "$search_dir" ] || { go_error "Directory not found: $search_dir"; return 1; }

    local found_tags
    found_tags=$(grep --include="*.php" --line-number --recursive '<?' "$search_dir" 2>/dev/null \
        | grep -v -F -e '<?php' -e '<?=' -e '<?xml' \
        | grep -v -F -e "strpos(" -e "str_replace(" \
        | grep -v -E "^[^:]*:[^:]*:\s*(\*|//|#)|'\<\?'|\"\<\?\"" || true)

    if [ -z "$found_tags" ]; then
        echo "No outdated PHP tags found."
    else
        echo "Potential outdated PHP tags:"
        echo "$found_tags"
    fi
}

# Source: commands/https
go_https() {
    local use_www="" yes=false

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --www) use_www=true ;;
            --no-www) use_www=false ;;
            --yes|-y) yes=true ;;
            -h|--help)
                echo "Usage: _go https [--www|--no-www] [--yes]"
                return 0
                ;;
            *)
                go_error "Unknown https argument: $1"
                return 1
                ;;
        esac
        shift
    done

    local wp_cmd current_url domain new_url new_url_escaped
    wp_cmd=$(go_wp_cli) || return 1
    "$wp_cmd" core is-installed --quiet || { go_error "This does not appear to be a WordPress installation."; return 1; }

    current_url=$("$wp_cmd" option get home --skip-plugins --skip-themes)
    domain=${current_url#http://}
    domain=${domain#https://}
    domain=${domain#www.}
    domain=${domain%%/*}

    if [ -z "$use_www" ]; then
        use_www=false
    fi

    if $use_www; then
        new_url="https://www.${domain}"
        new_url_escaped="https:\/\/www.${domain}"
    else
        new_url="https://${domain}"
        new_url_escaped="https:\/\/${domain}"
    fi

    if ! $yes && [ -t 0 ]; then
        printf "Update all URLs to '%s'? [y/N] " "$new_url"
        read -r answer
        case "$answer" in
            y|Y|yes|YES) ;;
            *) echo "Operation cancelled."; return 0 ;;
        esac
    elif ! $yes; then
        go_error "Confirmation required in non-interactive mode. Re-run with --yes."
        return 1
    fi

    "$wp_cmd" search-replace "http://${domain}" "$new_url" --all-tables --skip-plugins --skip-themes --report-changed-only
    "$wp_cmd" search-replace "http://www.${domain}" "$new_url" --all-tables --skip-plugins --skip-themes --report-changed-only
    "$wp_cmd" search-replace "http:\/\/${domain}" "$new_url_escaped" --all-tables --skip-plugins --skip-themes --report-changed-only
    "$wp_cmd" search-replace "http:\/\/www.${domain}" "$new_url_escaped" --all-tables --skip-plugins --skip-themes --report-changed-only
    "$wp_cmd" cache flush || true
    echo "HTTPS migration complete: ${new_url}"
}

# Source: commands/login
go_login() {
    local user_identifier=""
    local expires="600"
    local raw=false

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --expires=*)
                expires="${1#*=}"
                ;;
            --raw)
                raw=true
                ;;
            -h|--help)
                echo "Usage: _go login <user-id|user-login|email> [--expires=<seconds>] [--raw]"
                return 0
                ;;
            -* )
                go_error "Unknown login flag: $1"
                return 1
                ;;
            *)
                if [ -z "$user_identifier" ]; then
                    user_identifier="$1"
                else
                    go_error "Unexpected login argument: $1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    [ -n "$user_identifier" ] || { go_error "Please provide a user ID, login, or email."; return 1; }
    [[ "$expires" =~ ^[0-9]+$ ]] || { go_error "--expires must be a number of seconds."; return 1; }
    [ "$expires" -gt 0 ] || { go_error "--expires must be greater than 0."; return 1; }

    local wp_cmd
    wp_cmd=$(go_wp_cli) || return 1
    "$wp_cmd" core is-installed --quiet || { go_error "This does not appear to be a WordPress installation."; return 1; }

    local user_id user_login site_url mu_plugins_dir
    user_id=$("$wp_cmd" user get "$user_identifier" --field=ID --skip-plugins --skip-themes 2>/dev/null) || {
        go_error "User not found: $user_identifier"
        return 1
    }
    user_login=$("$wp_cmd" user get "$user_id" --field=user_login --skip-plugins --skip-themes 2>/dev/null || echo "$user_identifier")
    site_url=$("$wp_cmd" option get siteurl --skip-plugins --skip-themes)
    mu_plugins_dir=$("$wp_cmd" eval 'echo WPMU_PLUGIN_DIR;' --skip-plugins --skip-themes 2>/dev/null)

    [ -n "$mu_plugins_dir" ] || { go_error "Could not determine WPMU_PLUGIN_DIR."; return 1; }
    mkdir -p "$mu_plugins_dir" || { go_error "Could not create MU plugins directory: $mu_plugins_dir"; return 1; }

    local token token_hash token_key transient_key plugin_file login_url
    if command -v openssl >/dev/null 2>&1; then
        token=$(openssl rand -hex 32)
    else
        token="$(date +%s)-$$-${RANDOM:-0}-${user_id}"
    fi

    if command -v shasum >/dev/null 2>&1; then
        token_hash=$(printf "%s" "$token" | shasum -a 256 | awk '{print $1}')
    elif command -v sha256sum >/dev/null 2>&1; then
        token_hash=$(printf "%s" "$token" | sha256sum | awk '{print $1}')
    else
        go_error "Either shasum or sha256sum is required to generate login tokens."
        return 1
    fi

    token_key="${token_hash:0:16}"
    transient_key="plak_go_login_${user_id}_${token_hash}"
    plugin_file="${mu_plugins_dir}/plak-cli-go-login-${token_key}.php"

    "$wp_cmd" transient set "$transient_key" "1" "$expires" --skip-plugins --skip-themes >/dev/null || {
        go_error "Could not store temporary login token."
        return 1
    }

    cat > "$plugin_file" <<PHP
<?php
/**
 * Plugin Name: Plak CLI Go Temporary Login
 * Description: Temporary one-click login handler generated by Plak CLI Go.
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

add_action( 'init', function () {
    \$plak_go_login_key = '${token_key}';
    \$plak_go_user_id = ${user_id};
    \$plak_go_token_hash = '${token_hash}';
    \$plak_go_file = __FILE__;

    if ( empty( \$_GET['plak_go_login'] ) || ! hash_equals( \$plak_go_login_key, sanitize_text_field( wp_unslash( \$_GET['plak_go_login'] ) ) ) ) {
        return;
    }

    \$cleanup = static function () use ( \$plak_go_file ) {
        if ( is_writable( \$plak_go_file ) ) {
            @unlink( \$plak_go_file );
        }
    };

    \$token = isset( \$_GET['token'] ) ? sanitize_text_field( wp_unslash( \$_GET['token'] ) ) : '';
    if ( ! hash_equals( \$plak_go_token_hash, hash( 'sha256', \$token ) ) ) {
        \$cleanup();
        wp_die( 'Invalid temporary login token.' );
    }

    \$transient_key = 'plak_go_login_' . \$plak_go_user_id . '_' . \$plak_go_token_hash;
    if ( get_transient( \$transient_key ) !== '1' ) {
        \$cleanup();
        wp_die( 'Temporary login token expired.' );
    }

    delete_transient( \$transient_key );

    \$user = get_user_by( 'id', \$plak_go_user_id );
    if ( ! \$user ) {
        \$cleanup();
        wp_die( 'Temporary login user not found.' );
    }

    wp_set_current_user( \$user->ID );
    wp_set_auth_cookie( \$user->ID, true, is_ssl() );
    do_action( 'wp_login', \$user->user_login, \$user );

    \$cleanup();
    wp_safe_redirect( admin_url() );
    exit;
}, 0 );
PHP

    chmod 600 "$plugin_file" 2>/dev/null || true

    login_url="${site_url%/}/wp-login.php?plak_go_login=${token_key}&token=${token}"
    if $raw; then
        echo "$login_url"
        return 0
    fi

    echo "Temporary login URL created for ${user_login} (user ID ${user_id})."
    echo "Expires in ${expires} seconds and removes its MU plugin after use."
    echo "$login_url"
}

# Source: commands/migrate
go_migrate() {
    local backup_url=""
    local update_urls_flag="false"

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --url=*)
                backup_url="${1#*=}"
                shift
                ;;
            --update-urls)
                update_urls_flag="true"
                shift
                ;;
            -*)
                go_error "Unknown migrate flag: $1"
                return 1
                ;;
            *)
                go_error "Unexpected migrate argument: $1"
                return 1
                ;;
        esac
    done

    if [ -z "$backup_url" ]; then
        go_error "Please provide a backup URL or filename."
        go_error "Usage: _go migrate --url=<backup.zip> [--update-urls]"
        return 1
    fi

    echo "Starting site migration..."

    go_require_command unzip || return 1
    go_require_command tar || return 1

    local wp_cmd
    wp_cmd=$(go_wp_cli) || return 1

    local home_directory
    home_directory=$(pwd)
    local wp_home
    wp_home=$("$wp_cmd" option get home --skip-themes --skip-plugins 2> >(go_filter_insecure_mysql_warning >&2))
    if [[ "$wp_home" != http* ]]; then
        go_error "WordPress not found in current directory. Migration cancelled."
        return 1
    fi

    local private_dir
    private_dir=$(go_private_dir) || return 1

    local timedate
    local restore_dir
    timedate=$(date +'%Y-%m-%d-%H%M%S')
    restore_dir="${private_dir}/restore_${timedate}"
    mkdir -p "$restore_dir"
    cd "$restore_dir" || return 1

    local local_file_name
    local_file_name=$(basename "$backup_url")
    if [ -f "${home_directory}/${local_file_name}" ]; then
        mv "${home_directory}/${local_file_name}" "${private_dir}/${local_file_name}"
    fi

    if [[ "$backup_url" == *"admin-ajax.php"* ]]; then
        echo "BackupBuddy URL found, transforming..."
        backup_url=${backup_url/wp-admin\/admin-ajax.php?action=pb_backupbuddy_backupbuddy&function=download_archive&backupbuddy_backup=/wp-content\/uploads\/backupbuddy_backups/}
    fi
    if [[ "$backup_url" == *"dropbox.com"* && "$backup_url" != *"dl=1" ]]; then
        echo "Dropbox URL found, adding dl=1..."
        backup_url=${backup_url/&dl=0/&dl=1}
    fi

    if [ ! -f "${private_dir}/${local_file_name}" ]; then
        echo "Downloading from $backup_url..."
        if ! go_download_file "$backup_url" "backup_file"; then
            go_error "Download failed."
            cd "$home_directory"
            return 1
        fi
    else
        echo "Local file '${local_file_name}' found. Using it."
        mv "${private_dir}/${local_file_name}" ./backup_file
    fi

    echo "Extracting backup..."
    if [[ "$backup_url" == *".zip"* || "$local_file_name" == *".zip"* ]]; then
        unzip -q -o backup_file -x "__MACOSX/*" "cgi-bin/*"
    elif [[ "$backup_url" == *".tar.gz"* || "$local_file_name" == *".tar.gz"* ]]; then
        tar xzf backup_file
    elif [[ "$backup_url" == *".tar"* || "$local_file_name" == *".tar"* ]]; then
        tar xf backup_file
    else
        echo "No clear extension, assuming .zip format."
        unzip -q -o backup_file -x "__MACOSX/*" "cgi-bin/*"
    fi
    rm -f backup_file

    local wordpresspath
    wordpresspath=$(find . -type d -name 'wp-content' -print -quit)
    if [ -z "$wordpresspath" ]; then
        go_error "Cannot find wp-content/ in backup. Migration cancelled."
        cd "$home_directory"
        return 1
    fi

    echo "Migrating files..."
    mkdir -p "$home_directory/wp-content/mu-plugins" "$home_directory/wp-content/themes" "$home_directory/wp-content/plugins"

    if [ -d "$wordpresspath/mu-plugins" ]; then
        echo "Moving: mu-plugins"
        local working
        for working in "$wordpresspath/mu-plugins"/*; do
            [ -e "$working" ] || continue
            rm -rf "$home_directory/wp-content/mu-plugins/$(basename "$working")"
            mv "$working" "$home_directory/wp-content/mu-plugins/"
        done
    fi

    local content_dir
    for content_dir in blogs.dir gallery ngg uploads; do
        if [ -d "$wordpresspath/$content_dir" ]; then
            echo "Moving: $content_dir"
            rm -rf "$home_directory/wp-content/$content_dir"
            mv "$wordpresspath/$content_dir" "$home_directory/wp-content/"
        fi
    done

    local d
    for d in "$wordpresspath/themes"/*/; do
        [ -d "$d" ] || continue
        echo "Moving: themes/$(basename "$d")"
        rm -rf "$home_directory/wp-content/themes/$(basename "$d")"
        mv "$d" "$home_directory/wp-content/themes/"
    done

    for d in "$wordpresspath/plugins"/*/; do
        [ -d "$d" ] || continue
        echo "Moving: plugins/$(basename "$d")"
        rm -rf "$home_directory/wp-content/plugins/$(basename "$d")"
        mv "$d" "$home_directory/wp-content/plugins/"
    done

    local backup_root_dir
    backup_root_dir=$(dirname "$wordpresspath")
    cd "$backup_root_dir" || return 1
    local default_files=(index.php license.txt readme.html wp-activate.php wp-app.php wp-blog-header.php wp-comments-post.php wp-config-sample.php wp-cron.php wp-links-opml.php wp-load.php wp-login.php wp-mail.php wp-pass.php wp-register.php wp-settings.php wp-signup.php wp-trackback.php xmlrpc.php wp-admin wp-config.php wp-content wp-includes)
    local item
    for item in *; do
        [ -e "$item" ] || continue
        local is_default="false"
        local default
        for default in "${default_files[@]}"; do
            if [ "$item" = "$default" ]; then
                is_default="true"
                break
            fi
        done
        if [ "$is_default" = "false" ]; then
            echo "Moving root item: $item"
            mv -f "$item" "$home_directory/"
        fi
    done
    cd "$home_directory"

    local database=""
    if [ "$(uname)" = "Darwin" ]; then
        database=$(find "$restore_dir" "$home_directory" -type f -name '*.sql' -print0 | xargs -0 stat -f '%m %N' 2>/dev/null | sort -n | tail -1 | cut -f2- -d" " || true)
    else
        database=$(find "$restore_dir" "$home_directory" -type f -name '*.sql' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- || true)
    fi

    if [ -z "$database" ] || [ ! -f "$database" ]; then
        echo "Warning: No .sql file found in backup. Skipping database import."
    else
        echo "Importing database from $database..."
        local search_privacy
        search_privacy=$("$wp_cmd" option get blog_public --skip-plugins --skip-themes 2> >(go_filter_insecure_mysql_warning >&2))

        local table_prefix=""
        local current_table_prefix
        if [ -f "${backup_root_dir}/wp-config.php" ]; then
            table_prefix=$(grep 'table_prefix' "${backup_root_dir}/wp-config.php" | perl -n -e '/\047(.+)\047/&& print $1' || true)
        fi

        current_table_prefix=$("$wp_cmd" config get table_prefix --skip-plugins --skip-themes 2> >(go_filter_insecure_mysql_warning >&2))
        if [ -n "$table_prefix" ] && [ "$table_prefix" != "$current_table_prefix" ]; then
            echo "Updating table prefix from $current_table_prefix to $table_prefix"
            "$wp_cmd" config set table_prefix "$table_prefix" --skip-plugins --skip-themes
        fi

        "$wp_cmd" db reset --yes --skip-plugins --skip-themes 2> >(go_filter_insecure_mysql_warning >&2)
        if ! "$wp_cmd" db import "$database" 2> >(go_filter_insecure_mysql_warning >&2); then
            go_error "Database import failed."
            cd "$home_directory"
            return 1
        fi

        "$wp_cmd" cache flush --skip-plugins --skip-themes
        "$wp_cmd" option update blog_public "$search_privacy" --skip-plugins --skip-themes

        local wp_home_imported
        wp_home_imported=$("$wp_cmd" option get home --skip-plugins --skip-themes 2> >(go_filter_insecure_mysql_warning >&2))
        if [ "$update_urls_flag" = "true" ] && [ "$wp_home_imported" != "$wp_home" ]; then
            echo "Updating URLs from $wp_home_imported to $wp_home..."
            "$wp_cmd" search-replace "$wp_home_imported" "$wp_home" --all-tables --report-changed-only --skip-plugins --skip-themes
        fi
    fi

    echo "Performing cleanup and final optimizations..."
    local plugin
    local plugins_to_remove=(backupbuddy wordfence w3-total-cache wp-super-cache ewww-image-optimizer)
    for plugin in "${plugins_to_remove[@]}"; do
        if "$wp_cmd" plugin is-installed "$plugin" --skip-plugins --skip-themes >/dev/null 2>&1; then
            echo "Removing plugin: $plugin"
            "$wp_cmd" plugin delete "$plugin" --skip-plugins --skip-themes
        fi
    done

    local alter_queries
    alter_queries=$("$wp_cmd" db query "SELECT CONCAT('ALTER TABLE ', TABLE_SCHEMA,'.', TABLE_NAME, ' ENGINE=InnoDB;') FROM information_schema.TABLES WHERE ENGINE = 'MyISAM' AND TABLE_SCHEMA=DATABASE()" --skip-column-names --skip-plugins --skip-themes 2> >(go_filter_insecure_mysql_warning >&2))
    if [ -n "$alter_queries" ]; then
        echo "Converting MyISAM tables to InnoDB..."
        echo "$alter_queries" | "$wp_cmd" db query --skip-plugins --skip-themes 2> >(go_filter_insecure_mysql_warning >&2)
    fi

    "$wp_cmd" rewrite flush
    if "$wp_cmd" plugin is-active woocommerce --skip-plugins --skip-themes >/dev/null 2>&1; then
        "$wp_cmd" wc tool run regenerate_product_attributes_lookup_table --user=1 --skip-plugins --skip-themes
    fi

    find . -type d -exec chmod 755 {} \;
    find . -type f -exec chmod 644 {} \;
    rm -rf "$restore_dir"

    echo "Site migration complete."
}

# Source: commands/monitor
go_monitor() {
    local action="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$action" in
        errors) go_monitor_errors "$@" ;;
        access.log) go_monitor_log access "$@" ;;
        error.log) go_monitor_log error "$@" ;;
        traffic) go_monitor_traffic "$@" ;;
        -h|--help|"") echo "Usage: _go monitor <errors|access.log|error.log|traffic> [--now] [--top=<n>]" ;;
        *) go_error "Unknown monitor command: $action"; return 1 ;;
    esac
}

go_monitor_find_logs() {
    local type="$1"
    local candidates=(
        "./${type}.log"
        "../logs/${type}.log"
        "../log/${type}.log"
        "../../logs/${type}.log"
        "${HOME}/logs/${type}.log"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
        [ -f "$candidate" ] && echo "$candidate"
    done
}

go_monitor_log() {
    local type="$1" now=false
    shift || true
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --now) now=true ;;
            *) go_error "Unknown monitor flag: $1"; return 1 ;;
        esac
        shift
    done
    local logs=()
    while IFS= read -r log; do logs+=("$log"); done < <(go_monitor_find_logs "$type")
    [ "${#logs[@]}" -gt 0 ] || { go_error "No ${type}.log files found in common locations."; return 1; }
    if $now; then
        tail -n 100 "${logs[@]}"
    else
        tail -n 100 -f "${logs[@]}"
    fi
}

go_monitor_errors() {
    local now=false
    while [ "$#" -gt 0 ]; do
        case "$1" in --now) now=true ;; *) go_error "Unknown monitor errors flag: $1"; return 1 ;; esac
        shift
    done
    local logs=()
    while IFS= read -r log; do logs+=("$log"); done < <(go_monitor_find_logs access; go_monitor_find_logs error)
    [ "${#logs[@]}" -gt 0 ] || { go_error "No access/error logs found in common locations."; return 1; }
    if $now; then
        grep -Ei ' 500 |fatal|parse error|uncaught|critical' "${logs[@]}" | tail -n 100 || true
    else
        tail -n 0 -f "${logs[@]}" | grep -Ei ' 500 |fatal|parse error|uncaught|critical'
    fi
}

go_monitor_traffic() {
    local top=20
    while [ "$#" -gt 0 ]; do
        case "$1" in --top=*) top="${1#*=}" ;; --now) ;; *) go_error "Unknown monitor traffic flag: $1"; return 1 ;; esac
        shift
    done
    local logs=()
    while IFS= read -r log; do logs+=("$log"); done < <(go_monitor_find_logs access)
    [ "${#logs[@]}" -gt 0 ] || { go_error "No access.log files found in common locations."; return 1; }
    awk '{print $1}' "${logs[@]}" | sort | uniq -c | sort -nr | head -n "$top"
}

# Source: commands/reset
go_reset() {
    local action="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$action" in
        permissions) go_reset_permissions "$@" ;;
        wp) go_reset_wp "$@" ;;
        -h|--help|"") echo "Usage: _go reset <permissions|wp> [--admin-user=<user>] [--yes]" ;;
        *) go_error "Unknown reset command: $action"; return 1 ;;
    esac
}

go_reset_permissions() {
    local target="."
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --path=*) target="${1#*=}" ;;
            -h|--help) echo "Usage: _go reset permissions [--path=<path>]"; return 0 ;;
            *) go_error "Unknown reset permissions argument: $1"; return 1 ;;
        esac
        shift
    done
    [ -d "$target" ] || { go_error "Directory not found: $target"; return 1; }
    find "$target" -type d -exec chmod 755 {} \;
    find "$target" -type f -exec chmod 644 {} \;
    [ -f "$target/wp-config.php" ] && chmod 600 "$target/wp-config.php" 2>/dev/null || true
    echo "Permissions reset under ${target}."
}

go_reset_wp() {
    local admin_user="admin" yes=false
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --admin-user=*) admin_user="${1#*=}" ;;
            --yes|-y) yes=true ;;
            -h|--help) echo "Usage: _go reset wp --admin-user=<user> --yes"; return 0 ;;
            *) go_error "Unknown reset wp argument: $1"; return 1 ;;
        esac
        shift
    done
    $yes || { go_error "reset wp is destructive. Re-run with --yes."; return 1; }
    local wp_cmd url title email pass
    wp_cmd=$(go_wp_cli) || return 1
    url=$("$wp_cmd" option get siteurl --skip-plugins --skip-themes 2>/dev/null || echo "http://example.com")
    title=$("$wp_cmd" option get blogname --skip-plugins --skip-themes 2>/dev/null || echo "WordPress")
    email=$("$wp_cmd" user get "$admin_user" --field=user_email --skip-plugins --skip-themes 2>/dev/null || echo "admin@example.com")
    pass="plak-$(date +%s)-${RANDOM:-0}"
    "$wp_cmd" db reset --yes --skip-plugins --skip-themes
    "$wp_cmd" core install --url="$url" --title="$title" --admin_user="$admin_user" --admin_password="$pass" --admin_email="$email" --skip-email
    echo "WordPress reset complete. Admin user: ${admin_user}. Password: ${pass}"
}

# Source: commands/suspend
go_suspend() {
    local action="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$action" in
        activate) go_suspend_activate "$@" ;;
        deactivate) go_suspend_deactivate "$@" ;;
        -h|--help|"") echo "Usage: _go suspend <activate|deactivate> [--name=<name>] [--link=<url>]" ;;
        *) go_error "Unknown suspend command: $action"; return 1 ;;
    esac
}

go_suspend_activate() {
    local name="Website" link=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --name=*) name="${1#*=}" ;;
            --link=*) link="${1#*=}" ;;
            *) go_error "Unknown suspend activate argument: $1"; return 1 ;;
        esac
        shift
    done
    local wp_cmd mu_dir file safe_name safe_link
    wp_cmd=$(go_wp_cli) || return 1
    mu_dir=$("$wp_cmd" eval 'echo WPMU_PLUGIN_DIR;' --skip-plugins --skip-themes 2>/dev/null)
    mkdir -p "$mu_dir"
    file="${mu_dir}/plak-suspended.php"
    safe_name=$(printf "%s" "$name" | sed "s/'/\\\\'/g")
    safe_link=$(printf "%s" "$link" | sed "s/'/\\\\'/g")
    cat > "$file" <<PHP
<?php
/** Plugin Name: Plak Suspended Site */
if ( ! defined( 'ABSPATH' ) ) { exit; }
add_action( 'template_redirect', function () {
    if ( is_admin() || wp_doing_ajax() || ( defined( 'WP_CLI' ) && WP_CLI ) ) { return; }
    \$plak_suspend_name = '${safe_name}';
    \$plak_suspend_link = '${safe_link}';
    status_header( 503 );
    header( 'Retry-After: 3600' );
    nocache_headers();
    echo '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Website temporarily unavailable</title><style>body{font-family:system-ui,sans-serif;display:grid;min-height:100vh;place-items:center;margin:0;background:#111;color:#fff}.box{max-width:620px;padding:48px;text-align:center}a{color:#8bd3ff}</style></head><body><main class="box"><h1>' . esc_html( \$plak_suspend_name ) . ' is temporarily unavailable</h1><p>This website is currently suspended or under maintenance.</p>';
    if ( \$plak_suspend_link !== '' ) { echo '<p><a href="' . esc_url( \$plak_suspend_link ) . '">Contact support</a></p>'; }
    echo '</main></body></html>';
    exit;
}, 0 );
PHP
    echo "Suspension activated: ${file}"
}

go_suspend_deactivate() {
    local wp_cmd mu_dir file
    wp_cmd=$(go_wp_cli) || return 1
    mu_dir=$("$wp_cmd" eval 'echo WPMU_PLUGIN_DIR;' --skip-plugins --skip-themes 2>/dev/null)
    file="${mu_dir}/plak-suspended.php"
    if [ -f "$file" ]; then
        rm -f "$file"
        echo "Suspension deactivated."
    else
        echo "Suspension plugin not found."
    fi
}

# Source: commands/update
go_update() {
    local action="${1:-}"
    case "$action" in
        all) go_update_all ;;
        list) go_checkpoint_list ;;
        -h|--help|"") echo "Usage: _go update <all|list>" ;;
        *) go_error "Unknown update command: $action"; return 1 ;;
    esac
}

go_update_all() {
    local wp_cmd before after
    wp_cmd=$(go_wp_cli) || return 1
    "$wp_cmd" core is-installed --quiet || { go_error "This does not appear to be a WordPress installation."; return 1; }
    echo "Creating before-update checkpoint..."
    before=$(go_checkpoint_create || true)
    "$wp_cmd" core update || true
    "$wp_cmd" plugin update --all || true
    "$wp_cmd" theme update --all || true
    "$wp_cmd" core update-db || true
    echo "Creating after-update checkpoint..."
    after=$(go_checkpoint_create || true)
    echo "Update complete. Before: ${before:-none}. After: ${after:-none}."
}

# Source: commands/vault
go_vault() {
    local action="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$action" in
        create) go_vault_create "$@" ;;
        snapshots) go_vault_restic snapshots "$@" ;;
        info) go_vault_restic stats "$@" ;;
        prune) go_vault_prune "$@" ;;
        -h|--help|"") echo "Usage: _go vault <create|snapshots|info|prune>" ;;
        *) go_error "Unknown vault command: $action"; return 1 ;;
    esac
}

go_vault_env() {
    go_require_command restic || return 1
    [ -n "${RESTIC_REPOSITORY:-}" ] || { go_error "RESTIC_REPOSITORY is required."; return 1; }
    [ -n "${RESTIC_PASSWORD:-}" ] || { go_error "RESTIC_PASSWORD is required."; return 1; }
}

go_vault_restic() { go_vault_env || return 1; restic "$@"; }

go_vault_create() {
    go_vault_env || return 1
    local private_dir db_file
    private_dir=$(go_private_dir) || return 1
    db_file="${private_dir}/vault-db-$(date +%Y-%m-%d-%H%M%S).sql"
    local wp_cmd
    wp_cmd=$(go_wp_cli 2>/dev/null || true)
    if [ -n "$wp_cmd" ] && "$wp_cmd" db export "$db_file" --add-drop-table >/dev/null 2>&1; then
        restic backup . "$db_file"
        rm -f "$db_file"
    else
        restic backup .
    fi
}

go_vault_prune() {
    local yes=false
    [ "${1:-}" = "--yes" ] && yes=true
    $yes || { go_error "restic prune can be destructive. Re-run with --yes."; return 1; }
    go_vault_env || return 1
    restic forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6
}

# Source: commands/version
go_version() {
    echo "Plak CLI Go version ${PLAK_CLI_GO_VERSION}"
}

# Source: commands/wpcli
go_wpcli_check() {
    local wp_cmd
    wp_cmd=$(go_wp_cli) || return 1
    "$wp_cmd" core is-installed --quiet || { go_error "This does not appear to be a WordPress installation."; return 1; }

    echo "Checking for WP-CLI warnings..."

    local base_warnings
    base_warnings=$("$wp_cmd" plugin list --skip-themes --skip-plugins 2>&1 >/dev/null || true)
    if [ -n "$base_warnings" ]; then
        echo "Warnings appear even with plugins and themes skipped:"
        echo "$base_warnings"
        return 1
    fi

    local initial_warnings
    initial_warnings=$("$wp_cmd" plugin list 2>&1 >/dev/null || true)
    if [ -z "$initial_warnings" ]; then
        echo "WP-CLI is running without warnings."
        return 0
    fi

    echo "Initial warnings:"
    echo "$initial_warnings"
    echo

    local warnings_without_theme
    warnings_without_theme=$("$wp_cmd" plugin list --skip-themes 2>&1 >/dev/null || true)
    if [ -z "$warnings_without_theme" ]; then
        local active_theme
        active_theme=$("$wp_cmd" theme list --status=active --field=name 2>/dev/null || true)
        echo "Warnings disappear when skipping themes. Active theme is likely involved: ${active_theme:-unknown}"
    fi

    local active_plugins=() plugin warnings_without_plugin culprit_found=false
    while IFS= read -r plugin; do
        [ -n "$plugin" ] && active_plugins+=("$plugin")
    done < <("$wp_cmd" plugin list --field=name --status=active)

    for plugin in "${active_plugins[@]}"; do
        printf "Testing without '%s'... " "$plugin"
        warnings_without_plugin=$("$wp_cmd" plugin list --skip-plugins="$plugin" 2>&1 >/dev/null || true)
        if [ -z "$warnings_without_plugin" ]; then
            echo "likely culprit"
            culprit_found=true
        else
            echo "warnings remain"
        fi
    done

    if ! $culprit_found; then
        echo "Could not isolate a single plugin as the source."
    fi
}

# Source: commands/zip
go_zip() {
    local target="" output=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --output=*) output="${1#*=}" ;;
            -h|--help)
                echo "Usage: _go zip <path> [--output=<file>]"
                return 0
                ;;
            -* ) go_error "Unknown zip flag: $1"; return 1 ;;
            *)
                [ -z "$target" ] || { go_error "Unexpected zip argument: $1"; return 1; }
                target="$1"
                ;;
        esac
        shift
    done

    [ -n "$target" ] || { go_error "Please provide a path to zip."; return 1; }
    [ -e "$target" ] || { go_error "Path not found: $target"; return 1; }
    go_require_command zip || return 1

    if [ -z "$output" ]; then
        output="$(basename "$target")-$(date +%Y-%m-%d-%H%M%S).zip"
    fi

    zip -r "$output" "$target" -x '*/.git/*' '*/node_modules/*' '*/vendor/*' '*/cache/*' >/dev/null
    echo "$output"
}

# Pass all script arguments to the main function.
go_main "$@"
