#!/usr/bin/env bash

set -euo pipefail

OUTPUT_FILE="runner.sh"
MAIN_SCRIPT="main"
LIB_DIR="shared"
COMMANDS_DIR="commands"

if [ ! -f "$MAIN_SCRIPT" ] || [ ! -d "$COMMANDS_DIR" ] || [ ! -d "$LIB_DIR" ]; then
    echo "Error: run compile.sh from the runner directory." >&2
    exit 1
fi

echo "Compiling $OUTPUT_FILE..."

grep -v 'runner_main "$@"' "$MAIN_SCRIPT" > "$OUTPUT_FILE"

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

    echo '# Pass all script arguments to the main function.'
    echo 'runner_main "$@"'
} >> "$OUTPUT_FILE"

chmod +x "$OUTPUT_FILE"
echo "Created $(pwd)/$OUTPUT_FILE"
