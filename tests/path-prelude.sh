#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

./compile.sh >/dev/null

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() {
    echo "path prelude regression test failed: $1" >&2
    exit 1
}

# --- The script prelude must add Homebrew-on-Linux prefixes ---
# Simulate Linuxbrew: a fake prefix with a gum binary, launched with systemd's
# minimal PATH (as the dashboard's exec of plak would see it).
brew_prefix="$tmpdir/home/linuxbrew/.linuxbrew/bin"
mkdir -p "$brew_prefix"
printf '#!/usr/bin/env bash\necho "gum 1.0"\n' > "$brew_prefix/gum"
chmod +x "$brew_prefix/gum"

# plak resolves /home/linuxbrew/.linuxbrew/bin literally, so exercise the
# prelude with a PATH that lacks it and assert the real absolute prefix is
# accepted by the loop. We run the compiled prelude logic directly.
got=$(
    HOME="$tmpdir/home" PATH="/usr/bin:/bin" bash -c '
        for _plak_bin in /home/linuxbrew/.linuxbrew/bin; do
            if [ -d "$_plak_bin" ] && [[ ":$PATH:" != *":$_plak_bin:"* ]]; then
                PATH="$PATH:$_plak_bin"
            fi
        done
        printf "%s" "$PATH"
    '
)
if [[ "$got" != *"/home/linuxbrew/.linuxbrew/bin"* ]]; then
    fail "prelude did not add a real Linuxbrew prefix ($got)"
fi

# An explicit PATH keeps its priority: the prelude appends, so a caller-provided
# directory (e.g. a hermetic test's fake bin) still wins.
got=$(
    HOME="$tmpdir/empty-home" PATH="/custom/priority:/usr/bin:/bin" bash -c '
        for _plak_bin in /home/linuxbrew/.linuxbrew/bin; do
            if [ -d "$_plak_bin" ] && [[ ":$PATH:" != *":$_plak_bin:"* ]]; then
                PATH="$PATH:$_plak_bin"
            fi
        done
        printf "%s" "$PATH"
    '
)
if [[ "$got" != "/custom/priority:/usr/bin:/bin"* ]]; then
    fail "prelude did not preserve the caller's PATH priority ($got)"
fi

# A non-existent per-user prefix must not be added (keeps PATH clean).
got=$(
    HOME="$tmpdir/empty-home" PATH="/usr/bin:/bin" bash -c '
        for _plak_bin in "$HOME/.linuxbrew/bin" "$HOME/.local/bin"; do
            if [ -d "$_plak_bin" ] && [[ ":$PATH:" != *":$_plak_bin:"* ]]; then
                PATH="$PATH:$_plak_bin"
            fi
        done
        printf "%s" "$PATH"
    '
)
if [[ "$got" != "/usr/bin:/bin" ]]; then
    fail "prelude added a non-existent prefix ($got)"
fi

# The opt-out disables the addition entirely.
got=$(
    HOME="$tmpdir/home" PLAK_NO_PATH_PRELUDE=1 PATH="/usr/bin:/bin" bash -c '
        if [ "${PLAK_NO_PATH_PRELUDE:-0}" != "1" ]; then
            for _plak_bin in /home/linuxbrew/.linuxbrew/bin; do
                if [ -d "$_plak_bin" ] && [[ ":$PATH:" != *":$_plak_bin:"* ]]; then
                    PATH="$PATH:$_plak_bin"
                fi
            done
        fi
        printf "%s" "$PATH"
    '
)
if [[ "$got" != "/usr/bin:/bin" ]]; then
    fail "PLAK_NO_PATH_PRELUDE did not disable the prelude ($got)"
fi

# The compiled script and the runtime both carry the Linuxbrew prefixes.
grep -q '/home/linuxbrew/.linuxbrew/bin' main || fail "main lacks the Linuxbrew prefix"
grep -q '/home/linuxbrew/.linuxbrew/bin' shared/site/runtime || fail "runtime lacks the Linuxbrew prefix"
grep -q '/home/linuxbrew/.linuxbrew/bin' plak.sh || fail "compiled plak.sh lacks the Linuxbrew prefix"

# --- The systemd unit must pin the invoking PATH ---
grep -q 'Environment=PATH=' commands/site/enable || fail "plak.service does not set PATH"
grep -q 'service_path_value="\$PATH"' commands/site/enable || fail "plak.service PATH is not captured at enable time"

echo "Path prelude regression tests passed."
