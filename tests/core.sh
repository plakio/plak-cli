#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home"
mkdir -p "$HOME"
source ./plak.sh >/dev/null
export CORE_TEST_LOG="$tmpdir/commands"
for site in demo fail; do
    public="$SITES_DIR/$site.localhost/public"
    mkdir -p "$public/wp-includes" "$public/wp-content"
    echo keep > "$public/wp-config.php"
    echo plugin > "$public/wp-content/keep.txt"
    echo 6.8.1 > "$public/wp-includes/version.php"
done
cat > "$tmpdir/wp" <<'WP'
#!/usr/bin/env bash
set -euo pipefail
echo "$PWD $*" >> "$CORE_TEST_LOG"
case "$1 $2" in
    'core version') cat wp-includes/version.php ;;
    'core update')
        [ "${FAIL_UPDATE:-0}" = 0 ] || exit 9
        shift 2
        for arg in "$@"; do
            case "$arg" in
                --version=*) version=${arg#*=}; [ "$version" != nightly ] || version=6.9-alpha; echo "$version" > wp-includes/version.php ;;
            esac
        done ;;
    'eval '*) echo "${CORE_TEST_MULTISITE:-0}" ;;
    'core update-db')
        [[ "$PWD" != *fail.localhost* ]] || exit 8 ;;
    *) exit 2 ;;
esac
WP
chmod +x "$tmpdir/wp"
plak_wp_resolve_command() { PLAK_WP_COMMAND=("$tmpdir/wp"); }
plak_core_latest() { return 1; }
plak_core demo --check > "$tmpdir/out" 2> "$tmpdir/err"
grep -q 'installed=6.8.1' "$tmpdir/out"
grep -q 'unknown' "$tmpdir/err"
if plak_core update demo --version 6.7 >/dev/null 2>&1; then exit 1; fi
! grep -q 'core update ' "$CORE_TEST_LOG"
plak_core update demo --version 6.7 --allow-downgrade > "$tmpdir/out"
grep -q DOWNGRADE "$tmpdir/out"
grep -q effective=6.7 "$tmpdir/out"
grep -q -- --force "$CORE_TEST_LOG"
cmp <(echo keep) "$SITES_DIR/demo.localhost/public/wp-config.php"
cmp <(echo plugin) "$SITES_DIR/demo.localhost/public/wp-content/keep.txt"
plak_core update demo --version 6.8.1 > /dev/null
export CORE_TEST_MULTISITE=1
plak_core update demo --version 6.8.2 >/dev/null
grep -q 'core update-db --network' "$CORE_TEST_LOG"
unset CORE_TEST_MULTISITE
if plak_core update --all --version 6.9 > "$tmpdir/out" 2> "$tmpdir/err"; then exit 1; fi
grep -q 'demo.localhost: effective=6.9' "$tmpdir/out"
grep -q 'fail.localhost: FAILED' "$tmpdir/err"
if plak_core update demo --version nightly > /dev/null 2>&1; then exit 1; fi
plak_core update demo --version nightly --allow-downgrade >/dev/null
export FAIL_UPDATE=1
if plak_core update demo --version 6.8 --allow-downgrade >/dev/null 2>&1; then exit 1; fi
unset FAIL_UPDATE
if plak_core update demo > /dev/null 2>&1; then exit 1; fi
if plak_core update --version 6.9 >/dev/null 2>&1; then exit 1; fi
source commands/site/core
core_php() { shift; php "$@"; }
CADDY_CMD=core_php
curl() {
    printf '%s\n' "$*" > "$tmpdir/remote-args"
    echo '{"offers":[{"response":"upgrade","version":"6.9.1"}]}'
}
[ "$(plak_core_latest)" = 6.9.1 ]
grep -q -- '--max-time 10' "$tmpdir/remote-args"
echo 6.8.2 > "$SITES_DIR/demo.localhost/public/wp-includes/version.php"
plak_core update demo >/dev/null
[ "$(cat "$SITES_DIR/demo.localhost/public/wp-includes/version.php")" = 6.9.1 ]
curl() { echo '{"offers":[]}'; }
if plak_core_latest >/dev/null; then exit 1; fi
echo 'core tests passed'
