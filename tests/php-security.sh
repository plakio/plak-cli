#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2181,SC2329
# Regression coverage for the PHP2Shell (CVE-2026-109618/CVE-2026-109619)
# version floor and for selecting/validating the FrankenPHP artifact that
# actually provides the runtime used by sites and WP-CLI.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/plak-php-security.XXXXXX")
cleanup() {
    rm -rf "$tmpdir"
}
trap cleanup EXIT

export HOME="$tmpdir/home"
mkdir -p "$HOME" "$tmpdir/bin" "$tmpdir/tmp"
export PLAK_NO_PATH_PRELUDE=1
BASE_PATH="$PATH"
source ./plak.sh >/dev/null
set +e

fail() {
    echo "php security regression test failed: $1" >&2
    exit 1
}

check_version_status() {
    local version="$1" expected="$2" expected_rc="$3" actual rc
    actual=$(plak_php_version_status "$version")
    rc=$?
    if [ "$actual" != "$expected" ] || [ "$rc" -ne "$expected_rc" ]; then
        fail "PHP $version => ${actual}/${rc}, expected ${expected}/${expected_rc}"
    fi
}

# A fake FrankenPHP must answer version and php-cli probes with the exact
# values we give it. No host PHP is allowed to leak into this fixture.
make_frankenphp() {
    local path="$1" php="$2" frank="$3"
    cat > "$path" <<FRANK
#!/usr/bin/env bash
case "\${1:-}" in
    version)
        echo "FrankenPHP v${frank} PHP ${php} Caddy v2.11.7 h1:fixture"
        ;;
    php-cli)
        shift
        [ "\${1:-}" = "-r" ] && shift
        case "\${1:-}" in
            *PHP_VERSION*) echo "${php}" ;;
            *get_loaded_extensions*) echo "mysqli,curl,mbstring" ;;
            *) echo "${php}" ;;
        esac
        ;;
esac
FRANK
    chmod +x "$path"
}

file_hash() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# A fake brew supplies only the metadata each regression needs. It records
# upgrade arguments and can replace a keg binary with a patched fixture.
fakebrew_dir="$tmpdir/fakebrew"
mkdir -p "$fakebrew_dir"
cat > "$fakebrew_dir/brew" <<'FAKE_BREW'
#!/usr/bin/env bash
case "${1:-}" in
    --prefix)
        printf '%s\n' "${FAKE_BREW_PREFIX:-}"
        exit 0
        ;;
    list)
        case "${2:-}" in
            --formula)
                [ "${FAKE_BREW_LIST_RC:-0}" -eq 0 ] || exit "${FAKE_BREW_LIST_RC:-1}"
                [ -n "${FAKE_BREW_FORMULAE:-}" ] && printf '%s\n' "$FAKE_BREW_FORMULAE"
                exit 0
                ;;
            --versions)
                [ "${FAKE_BREW_VERSIONS_RC:-0}" -eq 0 ] || exit "${FAKE_BREW_VERSIONS_RC:-1}"
                printf '%s %s\n' "${3:-frankenphp}" "${FAKE_BREW_VERSION:-1.12.4}"
                exit 0
                ;;
        esac
        ;;
    upgrade)
        printf '%s\n' "${2:-}" >> "${FAKE_BREW_UPGRADE_LOG:-/dev/null}"
        [ "${FAKE_BREW_UPGRADE_RC:-0}" -eq 0 ] || exit "${FAKE_BREW_UPGRADE_RC:-1}"
        if [ -n "${FAKE_BREW_UPGRADE_SOURCE:-}" ] && [ -n "${FAKE_BREW_UPGRADE_TARGET:-}" ]; then
            cp "$FAKE_BREW_UPGRADE_SOURCE" "$FAKE_BREW_UPGRADE_TARGET" || exit 1
            chmod +x "$FAKE_BREW_UPGRADE_TARGET" || exit 1
        fi
        exit 0
        ;;
esac
exit 0
FAKE_BREW
chmod +x "$fakebrew_dir/brew"

# --- Upstream security floors and non-version cases ---------------------
check_version_status 8.5.11 vulnerable 1
check_version_status 8.5.12 patched 0
check_version_status 8.5.12-1ubuntu0.1 patched 0
check_version_status 8.4.26 vulnerable 1
check_version_status 8.4.27 patched 0
check_version_status 8.3.35 vulnerable 1
check_version_status 8.3.36 patched 0
check_version_status 8.2.34 vulnerable 1
check_version_status 8.2.35 patched 0
# EOL branches and prereleases cannot be certified from a version string.
check_version_status 8.1.99 unverified 2
check_version_status 8.5.12RC1 unverified 2
check_version_status 8.5.12-dev unverified 2
check_version_status 9.0.0 patched 0

# --- The embedded PHP is probed, not the host PHP ----------------------
probe_bin="$tmpdir/probe-bin"
mkdir -p "$probe_bin"
make_frankenphp "$probe_bin/frankenphp" 8.5.11 1.13.1
cat > "$probe_bin/php" <<'PHP'
#!/usr/bin/env bash
echo 8.5.12
PHP
chmod +x "$probe_bin/php"
PATH="$probe_bin:$BASE_PATH"
plak_health_web() { return 1; }
runtime_php=$(plak_php_runtime_php_version "$probe_bin/frankenphp")
[ "$runtime_php" = "8.5.11" ] || fail "runtime probe used host PHP or wrong value: $runtime_php"
runtime_status=$(plak_php_runtime_status "$probe_bin/frankenphp")
runtime_rc=$?
[ "$runtime_status" = "vulnerable" ] && [ "$runtime_rc" -eq 1 ] || fail "static 8.5.11 was not vulnerable"
json=$(plak_health_php --json)
json_rc=$?
[ "$json_rc" -eq 1 ] || fail "plak health php did not return 1 for a vulnerable runtime"
printf '%s' "$json" | python3 -c '
import json, sys
r=json.load(sys.stdin)
assert r["php_version"] == "8.5.11", r
assert r["status"] == "vulnerable", r
assert r["channel"] == "static", r
' || fail "plak health php JSON did not report the vulnerable embedded runtime"
text=$(plak_health_php)
grep -q 'VULNERABLE' <<<"$text" || fail "vulnerable text report is missing"

make_frankenphp "$probe_bin/frankenphp" 8.5.12 1.13.2
patch_status=$(plak_php_runtime_status "$probe_bin/frankenphp")
[ "$patch_status" = "patched" ] || fail "patched runtime was not recognized"
plak_health_php --json >/dev/null
[ "$?" -eq 0 ] || fail "plak health php did not return 0 for a patched runtime"

# A binary update that did not restart the web process is still vulnerable.
plak_health_web() { printf '%s' '{"source":"web","php_version":"8.5.11"}'; }
json=$(plak_health_php --json)
json_rc=$?
[ "$json_rc" -eq 1 ] || fail "an old web process was not reported as vulnerable"
printf '%s' "$json" | python3 -c '
import json, sys
r=json.load(sys.stdin)
assert r["php_version"] == "8.5.12", r
assert r["status"] == "vulnerable", r
assert r["cli_status"] == "patched", r
assert r["web_php_version"] == "8.5.11", r
assert r["web_status"] == "vulnerable", r
' || fail "web-process version mismatch was not reported consistently"
text=$(plak_health_php)
text_rc=$?
[ "$text_rc" -eq 1 ] || fail "stale web process text report returned $text_rc"
grep -q 'PHP (CLI):    8.5.12 \[patched\]' <<<"$text" || fail "CLI line inherited the web status"
grep -q 'PHP (web):    8.5.11 \[vulnerable\]' <<<"$text" || fail "web line did not report the stale runtime"
grep -q 'Result:       VULNERABLE' <<<"$text" || fail "overall result did not report the stale web runtime"
plak_health_web() { return 1; }

# A distribution package below the floor is unverified, not called vulnerable;
# the upstream static-php/FrankenPHP repository is version-authoritative.
make_frankenphp "$probe_bin/frankenphp" 8.5.11 1.13.2
(
    set +e
    PATH="$probe_bin:$BASE_PATH"
    plak_php_runtime_channel() { echo apt; }
    status=$(plak_php_runtime_status "$probe_bin/frankenphp")
    [ "$status" = "unverified" ] || exit 1
    plak_php_runtime_channel() { echo apt-upstream; }
    status=$(plak_php_runtime_status "$probe_bin/frankenphp")
    [ "$status" = "vulnerable" ] || exit 1
) || fail "package backport classification failed"
plak_health_web() { return 1; }

# Homebrew reports the upstream PHP release it built. It does not carry the
# distro-style CVE backports that make a lower apt/dnf version "unverified".
check_channel_status() {
    local version="$1" channel="$2" expected="$3" expected_rc="$4" actual rc
    actual=$(plak_php_status_for_channel "$version" "$channel")
    rc=$?
    if [ "$actual" != "$expected" ] || [ "$rc" -ne "$expected_rc" ]; then
        fail "PHP $version on $channel => ${actual}/${rc}, expected ${expected}/${expected_rc}"
    fi
}
check_channel_status 8.5.7 apt unverified 2
check_channel_status 8.5.7 dnf unverified 2
check_channel_status 8.5.7 package unverified 2
check_channel_status 8.5.7 ambiguous unverified 2
check_channel_status 8.5.7 brew vulnerable 1
check_channel_status 8.5.7 static vulnerable 1
check_channel_status 8.5.12 brew patched 0

# --- Homebrew prefix is not formula ownership -----------------------------
# A static binary in bin/ is a regular file. Homebrew links formulae there,
# so the formula must be detected from the Cellar link and installed metadata,
# never from /opt/homebrew or /usr/local in the path alone.

# A fake prefix where brew is present but no frankenphp formula is installed:
# this is the reported Apple Silicon case (/opt/homebrew/bin/frankenphp).
arm_prefix="$tmpdir/opt-homebrew"
mkdir -p "$arm_prefix/bin" "$arm_prefix/Cellar"
make_frankenphp "$arm_prefix/bin/frankenphp" 8.5.7 1.12.4
(
    set +e
    export FAKE_BREW_PREFIX="$arm_prefix"
    export FAKE_BREW_FORMULAE=""
    export FAKE_BREW_LIST_RC=0
    export FAKE_BREW_VERSIONS_RC=1
    PATH="$fakebrew_dir:$arm_prefix/bin:$BASE_PATH"
    channel=$(plak_php_runtime_channel "$arm_prefix/bin/frankenphp")
    [ "$channel" = static ] || { echo "channel was $channel" >&2; exit 1; }
    formula=$(plak_php_runtime_brew_formula "$arm_prefix/bin/frankenphp")
    formula_rc=$?
    [ "$formula_rc" -eq 1 ] || exit 1
    status=$(plak_php_runtime_status "$arm_prefix/bin/frankenphp")
    status_rc=$?
    [ "$status" = vulnerable ] && [ "$status_rc" -eq 1 ] || exit 1
    label=$(plak_php_runtime_channel_label "$channel" "$arm_prefix/bin/frankenphp")
    grep -q 'no formula owns it' <<<"$label" || exit 1
) || fail "manual /opt/homebrew-style binary was not classified as static/vulnerable"

# The same decision must work for the literal Apple Silicon path, without
# consulting another brew prefix from the test host.
(
    set +e
    export FAKE_BREW_PREFIX="/opt/homebrew"
    export FAKE_BREW_FORMULAE=""
    export FAKE_BREW_LIST_RC=0
    PATH="$fakebrew_dir:$BASE_PATH"
    channel=$(plak_php_runtime_channel /opt/homebrew/bin/frankenphp)
    [ "$channel" = static ] || exit 1
) || fail "literal /opt/homebrew/bin/frankenphp was not classified from formula metadata"

# A symlink into an installed Cellar keg is formula-owned, including an
# unqualified formula on Apple Silicon.
formula_prefix="$tmpdir/opt-homebrew-formula"
mkdir -p "$formula_prefix/bin" "$formula_prefix/opt" "$formula_prefix/Cellar/frankenphp/1.12.4/bin"
make_frankenphp "$formula_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp" 8.5.7 1.12.4
ln -s ../Cellar/frankenphp/1.12.4 "$formula_prefix/opt/frankenphp"
ln -s ../Cellar/frankenphp/1.12.4/bin/frankenphp "$formula_prefix/bin/frankenphp"
(
    set +e
    export FAKE_BREW_PREFIX="$formula_prefix"
    export FAKE_BREW_FORMULAE="frankenphp"
    export FAKE_BREW_VERSION="1.12.4"
    export FAKE_BREW_LIST_RC=0
    export FAKE_BREW_VERSIONS_RC=0
    PATH="$fakebrew_dir:$formula_prefix/bin:$BASE_PATH"
    channel=$(plak_php_runtime_channel "$formula_prefix/bin/frankenphp")
    [ "$channel" = brew ] || { echo "channel was $channel" >&2; exit 1; }
    formula=$(plak_php_runtime_brew_formula "$formula_prefix/bin/frankenphp")
    [ "$formula" = frankenphp ] || { echo "formula was $formula" >&2; exit 1; }
    status=$(plak_php_runtime_status "$formula_prefix/bin/frankenphp")
    status_rc=$?
    [ "$status" = vulnerable ] && [ "$status_rc" -eq 1 ] || exit 1
) || fail "Cellar symlink was not detected as a Homebrew formula"

# A qualified formula from a tap keeps its full name so the upgrade cannot
# hit an equally named formula in another tap.
(
    set +e
    export FAKE_BREW_PREFIX="$formula_prefix"
    export FAKE_BREW_FORMULAE="dunglas/frankenphp/frankenphp"
    export FAKE_BREW_LIST_RC=0
    PATH="$fakebrew_dir:$formula_prefix/bin:$BASE_PATH"
    formula=$(plak_php_runtime_brew_formula "$formula_prefix/bin/frankenphp")
    [ "$formula" = "dunglas/frankenphp/frankenphp" ] || {
        echo "qualified formula was $formula" >&2
        exit 1
    }
) || fail "tapped formula name was not preserved"

# Homebrew's opt/<formula> is a directory symlink into Cellar. A path such
# as opt/frankenphp/bin/frankenphp is not itself a symlink, so it must be
# resolved through its parent directory before deciding ownership.
opt_prefix="$tmpdir/opt-homebrew-dir-symlink"
mkdir -p "$opt_prefix/Cellar/frankenphp/1.12.4/bin" "$opt_prefix/opt"
make_frankenphp "$opt_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp" 8.5.7 1.12.4
ln -s ../Cellar/frankenphp/1.12.4 "$opt_prefix/opt/frankenphp"
make_frankenphp "$tmpdir/opt-patched" 8.5.12 1.13.3
(
    set +e
    export FAKE_BREW_PREFIX="$opt_prefix"
    export FAKE_BREW_FORMULAE="dunglas/frankenphp/frankenphp"
    export FAKE_BREW_VERSION="1.12.4"
    export FAKE_BREW_LIST_RC=0
    export FAKE_BREW_VERSIONS_RC=0
    export FAKE_BREW_UPGRADE_LOG="$tmpdir/opt-brew-upgrade.log"
    export FAKE_BREW_UPGRADE_SOURCE="$tmpdir/opt-patched"
    export FAKE_BREW_UPGRADE_TARGET="$opt_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp"
    : > "$FAKE_BREW_UPGRADE_LOG"
    PATH="$fakebrew_dir:$opt_prefix/opt/frankenphp/bin:$BASE_PATH"
    resolved=$(plak_php_runtime_realpath "$opt_prefix/opt/frankenphp/bin/frankenphp")
    [ "$resolved" = "$opt_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp" ] || {
        echo "opt path resolved to $resolved" >&2
        exit 1
    }
    channel=$(plak_php_runtime_channel "$opt_prefix/opt/frankenphp/bin/frankenphp")
    [ "$channel" = brew ] || { echo "opt channel was $channel" >&2; exit 1; }
    SUDO_CMD=""
    CADDY_CMD="frankenphp"
    upgrade_frankenphp > "$tmpdir/opt-brew-upgrade.out" 2>&1
    [ "$?" -eq 0 ] || { cat "$tmpdir/opt-brew-upgrade.out"; exit 1; }
    grep -qx 'dunglas/frankenphp/frankenphp' "$FAKE_BREW_UPGRADE_LOG" || exit 1
    [ "$(plak_php_runtime_php_version "$opt_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp")" = "8.5.12" ] || exit 1
) || fail "opt directory symlink was not upgraded through its Cellar formula"

# With brew absent, the opt directory symlink still resolves to Cellar. It
# must be treated as Homebrew-managed and left untouched, not replaced as a
# standalone static binary.
opt_guard_prefix="$tmpdir/opt-homebrew-no-brew"
mkdir -p "$opt_guard_prefix/Cellar/frankenphp/1.12.4/bin" "$opt_guard_prefix/opt"
make_frankenphp "$opt_guard_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp" 8.5.7 1.12.4
ln -s ../Cellar/frankenphp/1.12.4 "$opt_guard_prefix/opt/frankenphp"
(
    set +e
    PATH="$opt_guard_prefix/opt/frankenphp/bin:/usr/bin:/bin"
    gum() { printf '%s\n' "$*"; }
    SUDO_CMD=""
    CADDY_CMD="frankenphp"
    resolved=$(plak_php_runtime_realpath "$opt_guard_prefix/opt/frankenphp/bin/frankenphp")
    [ "$resolved" = "$opt_guard_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp" ] || exit 1
    channel=$(plak_php_runtime_channel "$opt_guard_prefix/opt/frankenphp/bin/frankenphp")
    [ "$channel" = brew ] || { echo "no-brew opt channel was $channel" >&2; exit 1; }
    before=$(file_hash "$opt_guard_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp")
    upgrade_frankenphp > "$tmpdir/opt-no-brew-upgrade.out" 2>&1
    [ "$?" -ne 0 ] || exit 1
    [ "$(file_hash "$opt_guard_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp")" = "$before" ] || exit 1
    grep -q 'brew is not on PATH' "$tmpdir/opt-no-brew-upgrade.out" || exit 1

    plak_php_install_static_frankenphp \
        "$opt_guard_prefix/opt/frankenphp/bin/frankenphp" frankenphp-mac-arm64 v1.13.3 \
        > "$tmpdir/opt-guard.out" 2>&1
    [ "$?" -ne 0 ] || exit 1
    [ "$(file_hash "$opt_guard_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp")" = "$before" ] || exit 1
    grep -q 'Refusing to replace a Homebrew-managed path' "$tmpdir/opt-guard.out" || exit 1
    grep -q "$opt_guard_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp" "$tmpdir/opt-guard.out" || exit 1
) || fail "opt directory symlink bypassed Cellar protection without brew"

# Intel macOS uses /usr/local. The same symlink/metadata rule applies.
intel_prefix="$tmpdir/usr/local"
mkdir -p "$intel_prefix/bin" "$intel_prefix/Cellar/frankenphp/1.12.4/bin"
make_frankenphp "$intel_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp" 8.5.7 1.12.4
ln -s ../Cellar/frankenphp/1.12.4/bin/frankenphp "$intel_prefix/bin/frankenphp"
(
    set +e
    export FAKE_BREW_PREFIX="$intel_prefix"
    export FAKE_BREW_FORMULAE="frankenphp"
    export FAKE_BREW_LIST_RC=0
    PATH="$fakebrew_dir:$intel_prefix/bin:$BASE_PATH"
    channel=$(plak_php_runtime_channel "$intel_prefix/bin/frankenphp")
    [ "$channel" = brew ] || exit 1
) || fail "Intel /usr/local Cellar symlink was not detected"

# A formula is installed but the selected executable is a regular file that
# shadows it. Ownership is ambiguous: do not replace it automatically.
shadow_prefix="$tmpdir/opt-homebrew-shadow"
mkdir -p "$shadow_prefix/bin" "$shadow_prefix/Cellar/frankenphp/1.12.4/bin"
make_frankenphp "$shadow_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp" 8.5.7 1.12.4
make_frankenphp "$shadow_prefix/bin/frankenphp" 8.5.7 1.12.4
(
    set +e
    export FAKE_BREW_PREFIX="$shadow_prefix"
    export FAKE_BREW_FORMULAE="frankenphp"
    export FAKE_BREW_LIST_RC=0
    export FAKE_BREW_VERSIONS_RC=0
    PATH="$fakebrew_dir:$shadow_prefix/bin:$BASE_PATH"
    channel=$(plak_php_runtime_channel "$shadow_prefix/bin/frankenphp")
    [ "$channel" = ambiguous ] || { echo "channel was $channel" >&2; exit 1; }
    status=$(plak_php_runtime_status "$shadow_prefix/bin/frankenphp")
    status_rc=$?
    [ "$status" = unverified ] && [ "$status_rc" -eq 2 ] || exit 1

    before=$(file_hash "$shadow_prefix/bin/frankenphp")
    plak_php_confirm_ambiguous_static() { return 1; }
    SUDO_CMD=""
    CADDY_CMD="frankenphp"
    upgrade_frankenphp > "$tmpdir/upgrade-ambiguous.log" 2>&1
    [ "$?" -ne 0 ] || exit 1
    [ "$(file_hash "$shadow_prefix/bin/frankenphp")" = "$before" ] || exit 1
    grep -q 'No changes made' "$tmpdir/upgrade-ambiguous.log" || exit 1
) || fail "shadowed formula path was not treated as ambiguous"

# brew metadata unavailable: a regular file inside the prefix is ambiguous,
# never assumed static and overwritten.
metadata_prefix="$tmpdir/opt-homebrew-metadata"
mkdir -p "$metadata_prefix/bin"
make_frankenphp "$metadata_prefix/bin/frankenphp" 8.5.7 1.12.4
(
    set +e
    export FAKE_BREW_PREFIX="$metadata_prefix"
    export FAKE_BREW_LIST_RC=1
    PATH="$fakebrew_dir:$metadata_prefix/bin:$BASE_PATH"
    channel=$(plak_php_runtime_channel "$metadata_prefix/bin/frankenphp")
    [ "$channel" = ambiguous ] || exit 1
    status=$(plak_php_runtime_status "$metadata_prefix/bin/frankenphp")
    [ "$?" -eq 2 ] && [ "$status" = unverified ] || exit 1
) || fail "missing brew metadata was not treated as ambiguous"

# A Cellar path stays formula-owned even when brew metadata is unavailable.
(
    set +e
    export FAKE_BREW_PREFIX="$formula_prefix"
    export FAKE_BREW_LIST_RC=1
    PATH="$fakebrew_dir:$formula_prefix/bin:$BASE_PATH"
    channel=$(plak_php_runtime_channel "$formula_prefix/bin/frankenphp")
    [ "$channel" = brew ] || exit 1
    formula=$(plak_php_runtime_brew_formula "$formula_prefix/bin/frankenphp")
    [ "$formula" = frankenphp ] || exit 1
) || fail "Cellar path lost Homebrew protection when metadata failed"

# Defence in depth: the static installer itself refuses keg/cask paths even if
# a caller reaches it with a bad channel decision.
protected_cellar="$tmpdir/protected/Cellar/frankenphp/1.12.4/bin"
mkdir -p "$protected_cellar"
make_frankenphp "$protected_cellar/frankenphp" 8.5.7 1.12.4
(
    set +e
    before=$(file_hash "$protected_cellar/frankenphp")
    SUDO_CMD=""
    plak_php_install_static_frankenphp "$protected_cellar/frankenphp" frankenphp-mac-arm64 v1.13.3 \
        > "$tmpdir/protected-cellar.log" 2>&1
    [ "$?" -ne 0 ] || exit 1
    [ "$(file_hash "$protected_cellar/frankenphp")" = "$before" ] || exit 1
    grep -q 'Refusing to replace a Homebrew-managed path' "$tmpdir/protected-cellar.log" || exit 1
) || fail "static installer did not protect a Homebrew keg path"

# A Cellar path whose formula is no longer installed still belongs to
# Homebrew: upgrade must fail without replacing it with a static binary.
stale_prefix="$tmpdir/stale-cellar"
mkdir -p "$stale_prefix/Cellar/frankenphp/1.12.4/bin"
make_frankenphp "$stale_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp" 8.5.7 1.12.4
(
    set +e
    export FAKE_BREW_PREFIX="$stale_prefix"
    export FAKE_BREW_FORMULAE=""
    export FAKE_BREW_LIST_RC=0
    export FAKE_BREW_VERSIONS_RC=1
    PATH="$fakebrew_dir:$stale_prefix/Cellar/frankenphp/1.12.4/bin:$BASE_PATH"
    channel=$(plak_php_runtime_channel "$stale_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp")
    [ "$channel" = brew ] || exit 1
    before=$(file_hash "$stale_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp")
    SUDO_CMD=""
    CADDY_CMD="frankenphp"
    upgrade_frankenphp > "$tmpdir/stale-cellar.log" 2>&1
    [ "$?" -ne 0 ] || exit 1
    [ "$(file_hash "$stale_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp")" = "$before" ] || exit 1
    grep -q 'but that formula is not installed' "$tmpdir/stale-cellar.log" || exit 1
) || fail "missing formula for a Cellar path was overwritten"

# A tapped formula is upgraded by its full name, and the installed PHP is
# re-probed after the package manager runs.
brew_upgrade_prefix="$tmpdir/brew-upgrade"
mkdir -p "$brew_upgrade_prefix/bin" "$brew_upgrade_prefix/Cellar/frankenphp/1.12.4/bin"
make_frankenphp "$brew_upgrade_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp" 8.5.7 1.12.4
ln -s ../Cellar/frankenphp/1.12.4/bin/frankenphp "$brew_upgrade_prefix/bin/frankenphp"
make_frankenphp "$tmpdir/brew-patched" 8.5.12 1.13.3
(
    set +e
    export FAKE_BREW_PREFIX="$brew_upgrade_prefix"
    export FAKE_BREW_FORMULAE="dunglas/frankenphp/frankenphp"
    export FAKE_BREW_VERSION="1.12.4"
    export FAKE_BREW_LIST_RC=0
    export FAKE_BREW_VERSIONS_RC=0
    export FAKE_BREW_UPGRADE_LOG="$tmpdir/brew-upgrade.log"
    export FAKE_BREW_UPGRADE_SOURCE="$tmpdir/brew-patched"
    export FAKE_BREW_UPGRADE_TARGET="$brew_upgrade_prefix/Cellar/frankenphp/1.12.4/bin/frankenphp"
    : > "$FAKE_BREW_UPGRADE_LOG"
    PATH="$fakebrew_dir:$brew_upgrade_prefix/bin:$BASE_PATH"
    SUDO_CMD=""
    CADDY_CMD="frankenphp"
    upgrade_frankenphp > "$tmpdir/brew-upgrade.out" 2>&1
    [ "$?" -eq 0 ] || { cat "$tmpdir/brew-upgrade.out"; exit 1; }
    grep -qx 'dunglas/frankenphp/frankenphp' "$FAKE_BREW_UPGRADE_LOG" || exit 1
    grep -q 'Updating the Homebrew formula dunglas/frankenphp/frankenphp' "$tmpdir/brew-upgrade.out" || exit 1
    [ "$(plak_php_runtime_php_version "$brew_upgrade_prefix/bin/frankenphp")" = "8.5.12" ] || exit 1
) || fail "qualified Homebrew formula upgrade failed"

# A standalone binary in a Homebrew prefix is replaced via the static asset
# path, never with brew upgrade, and only after PHP validation.
manual_upgrade_prefix="$tmpdir/opt-homebrew-manual-upgrade"
mkdir -p "$manual_upgrade_prefix/bin"
make_frankenphp "$manual_upgrade_prefix/bin/frankenphp" 8.5.7 1.12.4
make_frankenphp "$tmpdir/manual-brew-asset" 8.5.12 1.13.3
(
    set +e
    export FAKE_BREW_PREFIX="$manual_upgrade_prefix"
    export FAKE_BREW_FORMULAE=""
    export FAKE_BREW_LIST_RC=0
    export FAKE_BREW_VERSIONS_RC=1
    export FAKE_BREW_UPGRADE_LOG="$tmpdir/manual-brew-upgrade.log"
    : > "$FAKE_BREW_UPGRADE_LOG"
    PATH="$fakebrew_dir:$manual_upgrade_prefix/bin:$BASE_PATH"
    SUDO_CMD=""
    CADDY_CMD="frankenphp"
    setcap() { :; }
    fake_asset="$tmpdir/manual-brew-asset"
    download_fails=0
    curl() {
        local out="" prev="" url="" arg
        for arg in "$@"; do
            [ "$prev" = "-o" ] && out="$arg"
            case "$arg" in http*) url="$arg" ;; esac
            prev="$arg"
        done
        case " $* " in
            *url_effective*)
                printf '%s\n' 'https://github.com/php/frankenphp/releases/tag/v1.13.3'
                return 0
                ;;
        esac
        case " $* " in
            *" -fsIL "*) return 0 ;;
        esac
        [ "$download_fails" -eq 1 ] && return 22
        case "$url" in
            */download/*) cp "$fake_asset" "$out"; return 0 ;;
        esac
        return 22
    }
    upgrade_frankenphp > "$tmpdir/manual-brew-upgrade.out" 2>&1
    [ "$?" -eq 0 ] || { cat "$tmpdir/manual-brew-upgrade.out"; exit 1; }
    grep -q 'standalone binary in a Homebrew prefix' "$tmpdir/manual-brew-upgrade.out" || exit 1
    [ ! -s "$FAKE_BREW_UPGRADE_LOG" ] || exit 1
    [ "$(plak_php_runtime_php_version "$manual_upgrade_prefix/bin/frankenphp")" = "8.5.12" ] || exit 1

    # A vulnerable downloaded artifact or a failed download must leave the
    # working standalone binary untouched, exactly as for any static runtime.
    make_frankenphp "$tmpdir/manual-brew-bad-asset" 8.5.7 1.13.3
    make_frankenphp "$manual_upgrade_prefix/bin/frankenphp" 8.5.7 1.12.4
    before=$(file_hash "$manual_upgrade_prefix/bin/frankenphp")
    fake_asset="$tmpdir/manual-brew-bad-asset"
    upgrade_frankenphp > "$tmpdir/manual-brew-bad.out" 2>&1
    [ "$?" -ne 0 ] || exit 1
    [ "$(file_hash "$manual_upgrade_prefix/bin/frankenphp")" = "$before" ] || exit 1
    grep -q 'refusing to install' "$tmpdir/manual-brew-bad.out" || exit 1

    fake_asset="$tmpdir/manual-brew-asset"
    download_fails=1
    upgrade_frankenphp > "$tmpdir/manual-brew-download-fail.out" 2>&1
    [ "$?" -ne 0 ] || exit 1
    [ "$(file_hash "$manual_upgrade_prefix/bin/frankenphp")" = "$before" ] || exit 1
) || fail "standalone Homebrew-prefix binary was not updated through the static channel"

# --- Static artifact selection: validate before replacing --------------
static_bin="$tmpdir/static-bin"
mkdir -p "$static_bin"
make_frankenphp "$static_bin/frankenphp" 8.5.11 1.13.1
make_frankenphp "$tmpdir/good-asset" 8.5.12 1.13.2
make_frankenphp "$tmpdir/bad-asset" 8.5.11 1.13.2

(
    set +e
    PATH="$static_bin:$BASE_PATH"
    SUDO_CMD=""
    CADDY_CMD="frankenphp"
    setcap() { :; }
    fake_asset="$tmpdir/good-asset"
    download_fails=0
    asset_missing_latest=0
    curl() {
        local out="" prev="" url="" arg
        for arg in "$@"; do
            [ "$prev" = "-o" ] && out="$arg"
            case "$arg" in http*) url="$arg" ;; esac
            prev="$arg"
        done
        case " $* " in
            *url_effective*)
                printf '%s\n' 'https://github.com/php/frankenphp/releases/tag/v1.13.2'
                return 0
                ;;
        esac
        case " $* " in
            *" -fsIL "*)
                if [ "$asset_missing_latest" = 1 ]; then
                    case "$url" in *v1.13.2*) return 22 ;; esac
                fi
                return 0
                ;;
        esac
        [ "$download_fails" = 1 ] && return 22
        case "$url" in
            */download/*) cp "$fake_asset" "$out"; return 0 ;;
        esac
        return 22
    }

    upgrade_frankenphp > "$tmpdir/upgrade-good.log" 2>&1
    [ "$?" -eq 0 ] || { cat "$tmpdir/upgrade-good.log"; exit 1; }
    [ "$(plak_php_runtime_php_version "$static_bin/frankenphp")" = "8.5.12" ] || exit 1

    # `plak install` healing: the first probe fails, the upgrade succeeds, and
    # the second probe must reset the old exit status instead of refusing.
    make_frankenphp "$static_bin/frankenphp" 8.5.11 1.13.1
    fake_asset="$tmpdir/good-asset"
    plak_php_ensure_safe_runtime > "$tmpdir/ensure-healed.log" 2>&1
    [ "$?" -eq 0 ] || { cat "$tmpdir/ensure-healed.log"; exit 1; }
    [ "$(plak_php_runtime_php_version "$static_bin/frankenphp")" = "8.5.12" ] || exit 1

    # A downloaded artifact with vulnerable PHP must never replace the old one.
    make_frankenphp "$static_bin/frankenphp" 8.5.11 1.13.1
    before=$(file_hash "$static_bin/frankenphp")
    fake_asset="$tmpdir/bad-asset"
    upgrade_frankenphp > "$tmpdir/upgrade-bad.log" 2>&1
    [ "$?" -ne 0 ] || exit 1
    after=$(file_hash "$static_bin/frankenphp")
    [ "$before" = "$after" ] || exit 1
    grep -q 'refusing to install' "$tmpdir/upgrade-bad.log" || exit 1

    # `plak install` must stop rather than proceed with this runtime.
    plak_php_ensure_safe_runtime > "$tmpdir/ensure-bad.log" 2>&1
    [ "$?" -ne 0 ] || exit 1

    # An artifact whose version does not match the selected release is rejected.
    make_frankenphp "$tmpdir/mismatch-asset" 8.5.12 1.13.1
    fake_asset="$tmpdir/mismatch-asset"
    upgrade_frankenphp > "$tmpdir/upgrade-mismatch.log" 2>&1
    [ "$?" -ne 0 ] || exit 1
    after=$(file_hash "$static_bin/frankenphp")
    [ "$before" = "$after" ] || exit 1
    grep -q 'expected 1.13.2' "$tmpdir/upgrade-mismatch.log" || exit 1

    # A failed download also leaves the working binary intact.
    fake_asset="$tmpdir/good-asset"
    download_fails=1
    upgrade_frankenphp > "$tmpdir/upgrade-download-fail.log" 2>&1
    [ "$?" -ne 0 ] || exit 1
    after=$(file_hash "$static_bin/frankenphp")
    [ "$before" = "$after" ] || exit 1
) || fail "static artifact validation/replacement branch failed"

# --- Intel macOS: latest has no asset; only the validated fallback -----
intel_bin="$tmpdir/intel-bin"
mkdir -p "$intel_bin"
make_frankenphp "$intel_bin/frankenphp" 8.5.11 1.13.1
make_frankenphp "$tmpdir/fallback-asset" 8.5.12 1.13.1
(
    set +e
    PATH="$intel_bin:$BASE_PATH"
    SUDO_CMD=""
    CADDY_CMD="frankenphp"
    setcap() { :; }
    fake_asset="$tmpdir/fallback-asset"
    uname() {
        case "${1:-}" in
            -s) echo Darwin ;;
            -m) echo x86_64 ;;
            *) echo Darwin ;;
        esac
    }
    curl() {
        local out="" prev="" url="" arg
        for arg in "$@"; do
            [ "$prev" = "-o" ] && out="$arg"
            case "$arg" in http*) url="$arg" ;; esac
            prev="$arg"
        done
        case " $* " in
            *url_effective*)
                printf '%s\n' 'https://github.com/php/frankenphp/releases/tag/v1.13.2'
                return 0
                ;;
        esac
        case " $* " in
            *" -fsIL "*)
                case "$url" in *v1.13.2*) return 22 ;; esac
                return 0
                ;;
        esac
        case "$url" in
            */download/*) cp "$fake_asset" "$out"; return 0 ;;
        esac
        return 22
    }
    upgrade_frankenphp > "$tmpdir/upgrade-intel.log" 2>&1
    [ "$?" -eq 0 ] || { cat "$tmpdir/upgrade-intel.log"; exit 1; }
    grep -q 'does not include the FrankenPHP fixes' "$tmpdir/upgrade-intel.log" || exit 1
    [ "$(plak_php_runtime_php_version "$intel_bin/frankenphp")" = "8.5.12" ] || exit 1
) || fail "Intel macOS fallback branch failed"

# --- Package-managed runtime: equal FrankenPHP version is not enough ---
apt_bin="$tmpdir/apt-bin"
mkdir -p "$apt_bin"
make_frankenphp "$apt_bin/frankenphp" 8.5.11 1.13.2
(
    set +e
    PATH="$apt_bin:$BASE_PATH"
    SUDO_CMD=""
    PKG_MANAGER="apt"
    CADDY_CMD="frankenphp"
    plak_php_runtime_channel() { echo apt-upstream; }
    apt-get() {
        if [ "${1:-}" = "install" ]; then
            make_frankenphp "$apt_bin/frankenphp" 8.5.12 1.13.2
        fi
        return 0
    }
    upgrade_frankenphp > "$tmpdir/upgrade-apt.log" 2>&1
    [ "$?" -eq 0 ] || { cat "$tmpdir/upgrade-apt.log"; exit 1; }
    [ "$(plak_php_runtime_php_version "$apt_bin/frankenphp")" = "8.5.12" ] || exit 1
    grep -q 'Updating the apt package' "$tmpdir/upgrade-apt.log" || exit 1
) || fail "package upgrade branch failed"

# --- plak upgrade decision: PHP 8.5.11 triggers even at FrankenPHP 1.13.2
# plak_frankenphp_needs_update returns 0 when an update is required.
plak_frankenphp_needs_update 1.13.2 1.13.2 1
[ "$?" -eq 0 ] || fail "a stale PHP at an equal FrankenPHP version was not selected for update"
plak_frankenphp_needs_update 1.13.2 1.13.2 0
[ "$?" -ne 0 ] || fail "a patched runtime at the latest version was selected for update"
plak_frankenphp_needs_update 1.13.1 1.13.2 0
[ "$?" -eq 0 ] || fail "an older FrankenPHP was not selected for update"
plak_frankenphp_needs_update 1.13.2 1.13.1 0
[ "$?" -ne 0 ] || fail "a locally newer FrankenPHP was selected for downgrade"

echo 'php security regression tests passed'
