#!/usr/bin/env bash

set -euo pipefail

go_usage() {
    cat <<'EOF'
Plak Go

Usage:
  go <command> [arguments] [--flags]

Commands:
  backup      Create a WordPress backup.
  migrate     Restore a WordPress backup.
  help        Show this help text.
EOF
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
        migrate)
            go_migrate "$@"
            ;;
        help|--help|-h)
            go_usage
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
        go_error "Usage: go backup <folder> [--quiet] [--format=filename] [--exclude=<pattern>]"
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
        go_error "Usage: go migrate --url=<backup.zip> [--update-urls]"
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

# Pass all script arguments to the main function.
go_main "$@"
