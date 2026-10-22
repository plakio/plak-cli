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
assert r["web_php_version"] == "8.5.11", r
assert r["web_status"] == "vulnerable", r
' || fail "web-process version mismatch was not reported"
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
