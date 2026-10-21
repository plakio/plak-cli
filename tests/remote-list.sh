#!/usr/bin/env bash

# Regression tests for the remote listing (`plak remote list`).
#
# The listing used to be piped into `gum table`, whose interactive mode draws
# the header and the keybind footer but never the rows themselves with gum 2.
# The tests below check both the plain output and the interactive selector
# inside a real pseudo terminal.

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

./compile.sh >/dev/null

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

export HOME="$tmpdir/home"
mkdir -p "$HOME"
export PLAK_HOSTS_FILE="$tmpdir/hosts"
: > "$PLAK_HOSTS_FILE"

fail() {
    echo "remote list regression test failed: $1" >&2
    exit 1
}

assert_contains() {
    local haystack="$1" needle="$2" message="$3"
    grep -qF -- "$needle" <<<"$haystack" || fail "$message"
}

assert_not_contains() {
    local haystack="$1" needle="$2" message="$3"
    if grep -qF -- "$needle" <<<"$haystack"; then
        fail "$message"
    fi
}

# Write a throwaway SSH config with the given number of fake remotes.
make_ssh_config() {
    local path="$1" count="$2" index
    : > "$path"
    for index in $(seq 1 "$count"); do
        {
            printf 'Host remote-%02d\n' "$index"
            printf '    HostName 192.0.2.%d\n' "$index"
            printf '    User deploy\n'
            printf '    Port %d\n' "$((2200 + index))"
            printf '    # plak-remote-path: /srv/www/remote-%02d/public\n' "$index"
        } >> "$path"
    done
}

# --- Plain output (no terminal) --------------------------------------------

make_ssh_config "$tmpdir/ssh_config" 3
plain_output=$(PLAK_SSH_CONFIG="$tmpdir/ssh_config" ./plak.sh remote list)

assert_contains "$plain_output" "Name" "the listing lost its header"
assert_contains "$plain_output" "Host" "the listing lost its header"
assert_contains "$plain_output" "Path" "the listing lost its header"
assert_contains "$plain_output" "remote-01" "remote-01 is missing from the listing"
assert_contains "$plain_output" "remote-03" "remote-03 is missing from the listing"
# Every column of the row has to be there, not only the first one.
assert_contains "$plain_output" "remote-01        192.0.2.1                    deploy       2201   /srv/www/remote-01/public" \
    "the row of remote-01 is truncated"
assert_contains "$plain_output" "192.0.2.2" "the host of remote-02 is missing"
assert_contains "$plain_output" "2203" "the port of remote-03 is missing"

make_ssh_config "$tmpdir/ssh_config" 25
plain_output=$(PLAK_SSH_CONFIG="$tmpdir/ssh_config" ./plak.sh remote list)
for index in $(seq 1 25); do
    assert_contains "$plain_output" "remote-$(printf '%02d' "$index")" \
        "remote-$(printf '%02d' "$index") is missing from a listing of 25 remotes"
done

# An empty config is not an error.
: > "$tmpdir/ssh_config"
empty_output=$(PLAK_SSH_CONFIG="$tmpdir/ssh_config" ./plak.sh remote list)
assert_contains "$empty_output" "No SSH hosts found" "an empty config has to report that there is nothing to list"

empty_json=$(PLAK_SSH_CONFIG="$tmpdir/ssh_config" ./plak.sh remote list --json)
assert_contains "$empty_json" "[]" "an empty config has to produce an empty json list"

# The json output keeps every remote.
make_ssh_config "$tmpdir/ssh_config" 25
json_output=$(PLAK_SSH_CONFIG="$tmpdir/ssh_config" ./plak.sh remote list --json)
assert_contains "$json_output" '"name":"remote-01"' "the json output lost the first remote"
assert_contains "$json_output" '"name":"remote-25"' "the json output lost the last remote"
json_count=$(grep -o '"name":' <<<"$json_output" | wc -l | tr -d ' ')
[ "$json_count" = "25" ] || fail "the json output holds $json_count remotes instead of 25"

# --- Interactive selector (real pseudo terminal) ----------------------------

if ! command -v python3 >/dev/null 2>&1; then
    echo "remote list regression test failed: python3 is required for the terminal tests" >&2
    exit 1
fi
if ! command -v gum >/dev/null 2>&1; then
    echo "remote list regression test failed: gum is required for the terminal tests" >&2
    exit 1
fi

pty_run() {
    python3 "$ROOT_DIR/tests/helpers/pty-run.py" "$@"
}

# Extract one screen of the report of the pseudo terminal helper.
screen_of() {
    local output="$1" name="$2"
    awk -v name="$name" '
        $0 == "=== " name " SCREEN ===" { inside = 1; next }
        inside && /^=== / { inside = 0 }
        inside { print }
    ' <<<"$output"
}

raw_bytes_of() {
    local output="$1"
    grep -o '=== RAW BYTES: [0-9]*' <<<"$output" | grep -o '[0-9]*'
}

# The rows of the list have to be visible, not only its header and footer.
make_ssh_config "$tmpdir/ssh_config" 25
tty_output=$(PLAK_SSH_CONFIG="$tmpdir/ssh_config" pty_run --rows 24 --cols 100 -- ./plak.sh remote list)
tty_screen=$(screen_of "$tty_output" INITIAL)

assert_contains "$tty_screen" "remote-01" "the selector does not show the first remote"
assert_contains "$tty_screen" "remote-02" "the selector does not show the second remote"
assert_contains "$tty_screen" "192.0.2.1" "the selector does not show the host column"
assert_contains "$tty_screen" "/srv/www/remote-01/public" "the selector does not show the path column"
assert_contains "$tty_screen" "Name" "the selector does not show the header"

# The selector may not repaint itself in a loop.
raw_bytes=$(raw_bytes_of "$tty_output")
[ "${raw_bytes:-0}" -lt 100000 ] || fail "the selector repainted itself in a loop ($raw_bytes bytes)"

# The selection has to match the remote under the cursor.
tty_output=$(PLAK_SSH_CONFIG="$tmpdir/ssh_config" pty_run --rows 24 --cols 100 \
    --send down --send down --send enter -- ./plak.sh remote list)
assert_contains "$(screen_of "$tty_output" FINAL)" "remote-03" "the selection does not match the remote under the cursor"
assert_contains "$tty_output" "=== EXIT: 0 ===" "selecting a remote has to end with a success status"

# Escape quits the selector without selecting anything.
tty_output=$(PLAK_SSH_CONFIG="$tmpdir/ssh_config" pty_run --rows 24 --cols 100 \
    --send esc -- ./plak.sh remote list)
assert_not_contains "$(screen_of "$tty_output" FINAL)" "remote-01" "escape has to leave the listing without a selection"
assert_contains "$tty_output" "=== EXIT: 1 ===" "escape has to end with a cancelled status"

# A short terminal shows fewer rows, but still shows them.
tty_output=$(PLAK_SSH_CONFIG="$tmpdir/ssh_config" pty_run --rows 12 --cols 100 -- ./plak.sh remote list)
assert_contains "$(screen_of "$tty_output" INITIAL)" "remote-01" "the selector does not show any row in a short terminal"
raw_bytes=$(raw_bytes_of "$tty_output")
[ "${raw_bytes:-0}" -lt 100000 ] || fail "the selector repaints in a loop in a short terminal ($raw_bytes bytes)"

# A narrow terminal truncates the rows instead of wrapping them.
tty_output=$(PLAK_SSH_CONFIG="$tmpdir/ssh_config" pty_run --rows 24 --cols 60 -- ./plak.sh remote list)
assert_contains "$(screen_of "$tty_output" INITIAL)" "remote-01" "the selector does not show any row in a narrow terminal"

# A single remote is listed and selectable.
make_ssh_config "$tmpdir/ssh_config" 1
tty_output=$(PLAK_SSH_CONFIG="$tmpdir/ssh_config" pty_run --rows 24 --cols 100 \
    --send enter -- ./plak.sh remote list)
assert_contains "$(screen_of "$tty_output" INITIAL)" "remote-01" "a single remote is not listed"
assert_contains "$tty_output" "=== EXIT: 0 ===" "a single remote is not selectable"

echo "Remote list regression tests passed."
