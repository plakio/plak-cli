#!/usr/bin/env bash

set -euo pipefail

OUTPUT_FILE="plak.sh"
MAIN_SCRIPT="main"
LIB_DIR="shared"
COMMANDS_DIR="commands"

if [ ! -f "$MAIN_SCRIPT" ] || [ ! -d "$COMMANDS_DIR" ] || [ ! -d "$LIB_DIR" ]; then
    echo "Error: run compile.sh from the Plak repository root." >&2
    exit 1
fi
if [ ! -d editor ]; then
    echo "Error: editor assets are missing; run compile.sh from the Plak repository root." >&2
    exit 1
fi

echo "Compiling $OUTPUT_FILE..."

# Use -F (fixed string) + -x (whole line) so only the exact `main "$@"`
# invocation at the bottom of `main` is stripped. A bare `grep -vF` would
# also remove lines like `plak_hosts "$@"` because "main \"$@\"" is a
# substring of "hosts \"$@\"".
grep -vFx 'main "$@"' "$MAIN_SCRIPT" > "$OUTPUT_FILE"

{
    echo ""
    echo "# --- Shared Helpers ---"
    find "$LIB_DIR" -type f ! -name '.*' | sort | while IFS= read -r lib_file; do
        echo "# Source: $lib_file"
        cat "$lib_file"
        echo ""
    done

    echo "# --- Command Functions ---"
    find "$COMMANDS_DIR" -type f ! -name '.*' | sort | while IFS= read -r cmd_file; do
        echo "# Source: $cmd_file"
        cat "$cmd_file"
        echo ""
    done

    echo "# --- HTML Editor Assets ---"
    echo 'deploy_html_editor() {'
    echo '    local editor_dir="${1:-$GUI_DIR/editor}"'
    echo '    local app_dir="${2:-$APP_DIR}"'
    echo '    mkdir -p "$editor_dir" "$app_dir/lib" "$app_dir/site-router" || return 1'
    while IFS= read -r asset; do
        case "$asset" in
            editor/lib/html-site.php) target='$app_dir/lib/html-site.php' ;;
            editor/site-router/render.php) target='$app_dir/site-router/render.php' ;;
            editor/*) target='$editor_dir/'"$(basename "$asset")" ;;
            *) continue ;;
        esac
        printf '    cat > "%s" <<%s\n' "$target" "'PLAK_EDITOR_ASSET_EOF'"
        cat "$asset"
        printf 'PLAK_EDITOR_ASSET_EOF\n'
    done < <(find editor -type f | sort)
    cat <<'EDITOR_FOOTER'
    local home_escaped
    home_escaped=$(printf '%s' "${HOME:-}" | sed -e 's/[\/&|]/\\&/g')
    sed "s|__PLAK_HOME__|$home_escaped|g" "$app_dir/lib/html-site.php" > "$app_dir/lib/html-site.php.tmp" || return 1
    mv "$app_dir/lib/html-site.php.tmp" "$app_dir/lib/html-site.php" || return 1
    echo "   - ✅ Deployed HTML editor."
}
EDITOR_FOOTER

    echo '# Pass all script arguments to the main function.'
    echo 'main "$@"'
} >> "$OUTPUT_FILE"

chmod +x "$OUTPUT_FILE"
echo "Created $(pwd)/$OUTPUT_FILE"
