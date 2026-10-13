#!/usr/bin/env bash
# Hermetic regression tests for the runner `find stuck-plugin` port (CLI-1).
# No WordPress, network or system service is touched: WP-CLI is a fixture
# script selected via RUNNER_WP_CLI_CMD, and the real `timeout` bounds every
# probe. Requires coreutils `timeout` (or macOS `gtimeout`).
# shellcheck disable=SC1091 # Runner sources are separate from plak.sh.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || {
    echo 'go-find test skipped: timeout/gtimeout missing'; exit 0;
}
(cd go && ./compile.sh >/dev/null)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() { echo "go-find regression failed: $*" >&2; exit 1; }

# Fixture WP-CLI. Behavior is driven by env, never by a real site:
# TEST_NOT_WP=1 makes `core is-installed` fail; TEST_HANG=1 makes plain
# `option get home` sleep (killed by timeout); TEST_CULPRIT names the plugin
# whose --skip-plugins run answers fast; TEST_FAIL_FAST=1 makes the baseline
# fail immediately with exit 1 (a WP-CLI error, not a hang).
cat > "$tmpdir/wp" <<'FAKEWP'
#!/usr/bin/env bash
if [ "$1 $2" = "core is-installed" ]; then
    [ -z "${TEST_NOT_WP:-}" ] || exit 3
    exit 0
fi
if [ "$1 $2 $3" = "plugin list --field=name" ]; then
    printf 'alpha\nbeta\n'
    exit 0
fi
if [ "$1 $2 $3" = "option get home" ]; then
    if [ -n "${TEST_FAIL_FAST:-}" ]; then
        echo 'Error: database connection failed.' >&2
        exit 1
    fi
    skipped=""
    for arg in "$@"; do
        case "$arg" in --skip-plugins=*) skipped="${arg#--skip-plugins=}" ;; esac
    done
    if [ -n "$skipped" ] && [ "$skipped" = "${TEST_CULPRIT:-}" ]; then
        echo 'https://example.test'
        exit 0
    fi
    if [ -z "$skipped" ] && [ -z "${TEST_HANG:-}" ]; then
        echo 'https://example.test'
        exit 0
    fi
    sleep 60
fi
echo "unexpected wp call: $*" >&2
exit 99
FAKEWP
chmod +x "$tmpdir/wp"
export RUNNER_WP_CLI_CMD="$tmpdir/wp"

run_go() { bash "$ROOT_DIR/go/go.sh" "$@"; }

# --- Healthy site: baseline answers, no plugin loop ---
out=$(TEST_HANG='' run_go find stuck-plugin 1) || fail "healthy site failed"
grep -q "doesn't appear to be hanging" <<<"$out" || fail "healthy message: $out"

# --- Hanging site with a culprit ---
out=$(TEST_HANG=1 TEST_CULPRIT=beta run_go find stuck-plugin 1) || fail "culprit run failed"
grep -q 'beta' <<<"$out" || fail "culprit not named: $out"
grep -q 'Found the culprit' <<<"$out" || fail "culprit banner: $out"

# --- Hanging site, no single culprit ---
out=$(TEST_HANG=1 run_go find stuck-plugin 1) || fail "no-culprit run failed"
grep -q 'No single plugin' <<<"$out" || fail "no-culprit message: $out"

# --- Fast WP-CLI error is not misdiagnosed as a hang ---
if TEST_FAIL_FAST=1 run_go find stuck-plugin 1 >"$tmpdir/out" 2>&1; then
    fail "fast failure reported success"
fi
grep -q 'not a timeout' "$tmpdir/out" || fail "fast failure message"
if grep -q 'Testing with' "$tmpdir/out"; then fail "plugin loop ran after a fast failure"; fi

# --- Not a WordPress install ---
if TEST_NOT_WP=1 run_go find stuck-plugin 1 >/dev/null 2>&1; then
    fail "non-WP directory reported success"
fi

# --- Missing timeout aborts actionably ---
# A PATH with a shell but without timeout/gtimeout: the fixture still runs
# (bash/env/sleep linked in), but the stuck-plugin probe must refuse.
mkdir -p "$tmpdir/notimeout"
ln -s "$(command -v bash)" "$(command -v env)" "$(command -v sleep)" "$tmpdir/notimeout/"
if PATH="$tmpdir/notimeout" RUNNER_WP_CLI_CMD="$tmpdir/wp" bash "$ROOT_DIR/go/go.sh" find stuck-plugin 1 >"$tmpdir/out" 2>&1; then
    fail "missing timeout reported success"
fi
grep -q "'timeout' command not found" "$tmpdir/out" || fail "missing timeout message"

# --- Bad timeout argument ---
if run_go find stuck-plugin 0 >/dev/null 2>&1; then fail "accepted zero timeout"; fi
if run_go find stuck-plugin abc >/dev/null 2>&1; then fail "accepted non-numeric timeout"; fi

# --- Wiring: help and unknown subcommand ---
run_go find stuck-plugin --help >/dev/null 2>&1 || true
run_go help find | grep -q 'stuck-plugin' || fail "help omits stuck-plugin"
if run_go find bogus >/dev/null 2>&1; then fail "unknown subcommand reported success"; fi

echo 'go-find regression tests passed'
