#!/usr/bin/env bash

# Stable release channel tests: tag selection, installer, and `plak upgrade`
# with controlled GitHub API and download responses. No real network is used.

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/plak-release-channel.XXXXXX")
trap 'rm -rf "$tmpdir"' EXIT

fail() {
    echo "release channel test failed: $1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    [ "$actual" = "$expected" ] || fail "$label: expected '$expected', got '$actual'"
}

assert_contains() {
    local file="$1" text="$2" label="$3"
    grep -Fq -- "$text" "$file" || fail "$label: '$text' not found in $file"
}

assert_no_temps() {
    local dir="$1" label="$2"
    local found
    found=$(find "$dir" -name '.plak-install.*' -o -name '.plak-upgrade.*' 2>/dev/null || true)
    [ -z "$found" ] || fail "$label left temporary files: $found"
}

assert_no_main_fallback() {
    local log="$1" label="$2"
    if grep -Fq 'raw.githubusercontent.com/plakio/plak-cli/main/plak.sh' "$log"; then
        fail "$label fell back to main/plak.sh"
    fi
    if grep -Fq 'releases/latest' "$log"; then
        fail "$label used releases/latest"
    fi
}

file_mode() {
    if stat -c '%a' "$1" >/dev/null 2>&1; then
        stat -c '%a' "$1"
    else
        stat -f '%Lp' "$1"
    fi
}

mkdir -p "$tmpdir/home" "$tmpdir/tmp" "$tmpdir/fakebin" "$tmpdir/install" "$tmpdir/upgrade-bin"
export HOME="$tmpdir/home"
export TMPDIR="$tmpdir/tmp"
export PLAK_NO_PATH_PRELUDE=1
unset GITHUB_TOKEN GH_TOKEN PLAK_INSTALL_URL PLAK_INSTALL_DIR
unset FAKE_CURL_MODE FAKE_TAGS_JSON_PAGE2 FAKE_MISMATCH_PAYLOAD FAKE_CURL_STAT_LOG

# --- Controlled network ----------------------------------------------------
# fake curl serves API JSON and script payloads from fixtures. It records the
# URL and output path, and keeps the HTTP status handling of the real code.
cat > "$tmpdir/fakebin/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -u

out=""
url=""
write=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -w) write="$2"; shift 2 ;;
        -H|--connect-timeout|--max-time|--retry|--retry-delay) shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done

log="${FAKE_CURL_LOG:-/dev/null}"
printf '%s\t%s\n' "$url" "${out:-}" >> "$log"

mode="${FAKE_CURL_MODE:-ok}"

case "$url" in
    file://*)
        source_file=${url#file://}
        if [ "$mode" = "download-404" ]; then
            exit 22
        fi
        if [ ! -f "$source_file" ]; then
            echo "fake curl: missing local file $source_file" >&2
            exit 37
        fi
        if [ -n "$out" ]; then cp "$source_file" "$out"; else cat "$source_file"; fi
        ;;
    *api.github.com*)
        page=$(printf '%s' "$url" | sed -n 's/.*[?&]page=\([0-9][0-9]*\).*/\1/p')
        [ -n "$page" ] || page=1
        code=200
        case "$mode" in
            api-401) code=401; body='{"message":"Bad credentials"}' ;;
            api-403) code=403; body='{"message":"API rate limit exceeded"}' ;;
            api-500) code=500; body='{"message":"Server Error"}' ;;
            api-network) exit 7 ;;
            *)
                fixture="${FAKE_TAGS_JSON:-}"
                if [ "$page" != "1" ] && [ -n "${FAKE_TAGS_JSON_PAGE2:-}" ]; then
                    fixture="$FAKE_TAGS_JSON_PAGE2"
                fi
                [ -n "$fixture" ] || { echo "fake curl: no tags fixture" >&2; exit 2; }
                body=$(cat "$fixture")
                ;;
        esac
        printf '%s' "$body"
        if [ -n "$write" ]; then
            printf '\n%s' "$code"
        fi
        ;;
    *raw.githubusercontent.com*)
        case "$mode" in
            download-network) exit 18 ;;
            download-404) exit 22 ;;
            download-empty) : > "${out:-/dev/null}"; exit 0 ;;
            download-truncated) printf '#!/usr/bin/env bash\n' > "${out:-/dev/null}"; exit 0 ;;
            download-partial) printf '#!/usr/bin/env bash\n' > "${out:-/dev/null}"; exit 18 ;;
            download-slow)
                printf '#!/usr/bin/env bash\n' > "${out:-/dev/null}"
                [ -z "${FAKE_SLOW_MARKER:-}" ] || : > "$FAKE_SLOW_MARKER"
                sleep 2
                exit 18
                ;;
            download-mismatch) payload="${FAKE_MISMATCH_PAYLOAD:-}" ;;
            *) payload="${FAKE_PAYLOAD:-}" ;;
        esac
        [ -n "$payload" ] && [ -f "$payload" ] || { echo "fake curl: no payload" >&2; exit 2; }
        if [ -n "$out" ]; then cp "$payload" "$out"; else cat "$payload"; fi
        ;;
    *)
        echo "fake curl: unexpected URL $url" >&2
        exit 2
        ;;
esac

if [ -n "${FAKE_CURL_STAT_LOG:-}" ] && [ -n "$out" ] && [ -f "$out" ]; then
    if stat -c '%a' "$out" >/dev/null 2>&1; then
        stat -c '%a' "$out" >> "$FAKE_CURL_STAT_LOG" 2>/dev/null || true
    else
        stat -f '%Lp' "$out" >> "$FAKE_CURL_STAT_LOG" 2>/dev/null || true
    fi
fi
exit 0
FAKE_CURL
chmod +x "$tmpdir/fakebin/curl"
export PATH="$tmpdir/fakebin:$PATH"

tags_json() {
    local first=true tag
    printf '[\n'
    for tag in "$@"; do
        if [ "$first" = true ]; then first=false; else printf ',\n'; fi
        printf '  {"name": "%s"}\n' "$tag"
    done
    printf ']\n'
}

# --- Shared helper and contract -------------------------------------------
# shellcheck disable=SC1091
source ./plak.sh >/dev/null

sed -n '/^# BEGIN plak-release-channel$/,/^# END plak-release-channel$/p' install.sh > "$tmpdir/install-block"
sed -n '/^# BEGIN plak-release-channel$/,/^# END plak-release-channel$/p' shared/release > "$tmpdir/shared-block"
cmp -s "$tmpdir/install-block" "$tmpdir/shared-block" \
    || fail "install.sh and shared/release stable-channel blocks differ"

if grep -Eq 'mapfile|readarray|declare -A|wait -n|\$\{[A-Za-z_][A-Za-z0-9_]*,,|\$\{[A-Za-z_][A-Za-z0-9_]*\^\^' install.sh shared/release commands/site/upgrade; then
    fail "stable channel uses a Bash 4+ construct (macOS ships Bash 3.2)"
fi
if grep -Fq 'sort -V' shared/release install.sh; then
    fail "stable channel still relies on sort -V"
fi

# --- Tag selection ---------------------------------------------------------
tag=$(printf '%s\n' v0.4.9 v0.4.10 v0.4.67 v0.4.8 v0.4.100-rc1 v0.5.0 nightly | plak_release_latest_stable_tag)
assert_eq "v0.5.0" "$tag" "numeric tag ordering"

tag=$(printf '%s\n' v0.4.9 v0.4.10 v0.5.0 v0.4.8 | plak_release_latest_stable_tag)
assert_eq "v0.5.0" "$tag" "out-of-order tag selection"

tag=$(printf '%s\n' v1.9.9 v2.0.0-rc1 v10.0.0-rc1 v2.0.0 v0.9.9 | plak_release_latest_stable_tag)
assert_eq "v2.0.0" "$tag" "prereleases are excluded"

tag=$(printf '%s\n' v1.0.0 v999999999999999999999.0.0 v2.0.0 | plak_release_latest_stable_tag)
assert_eq "v999999999999999999999.0.0" "$tag" "numeric components larger than 64-bit"

if printf '%s\n' nightly release-9.9.9 v01.2.3 v1.2 v1.2.3.4 v1.2.3+build v1.2.3-rc1 | plak_release_latest_stable_tag >/dev/null; then
    fail "foreign/prerelease tags were accepted"
fi
if printf '' | plak_release_latest_stable_tag >/dev/null; then
    fail "empty tag list was accepted"
fi

# API selection, pagination, and failure modes.
page1="$tmpdir/page1.json"
page2="$tmpdir/page2.json"
{
    printf '[\n'
    i=1
    while [ "$i" -le 100 ]; do
        [ "$i" -eq 1 ] || printf ',\n'
        printf '  {"name": "v0.0.%d"}\n' "$i"
        i=$((i + 1))
    done
    printf ']\n'
} > "$page1"
tags_json v0.1.0 > "$page2"

api_log="$tmpdir/api.log"
: > "$api_log"
export FAKE_CURL_LOG="$api_log" FAKE_TAGS_JSON="$page1" FAKE_TAGS_JSON_PAGE2="$page2"
tag=$(plak_release_resolve_latest_tag) || fail "API pagination resolution failed"
assert_eq "v0.1.0" "$tag" "highest tag on the second API page"
[ "$(grep -c 'api.github.com' "$api_log")" -eq 2 ] || fail "API pagination did not request two pages"

out_of_order="$tmpdir/out-of-order.json"
tags_json v0.4.9 v0.4.67 v0.4.10 v0.4.68-rc1 nightly > "$out_of_order"
: > "$api_log"
export FAKE_TAGS_JSON="$out_of_order"
unset FAKE_TAGS_JSON_PAGE2
tag=$(plak_release_resolve_latest_tag) || fail "API out-of-order resolution failed"
assert_eq "v0.4.67" "$tag" "API out-of-order tag selection"

if tag=$(FAKE_CURL_MODE=api-403 plak_release_resolve_latest_tag 2>"$tmpdir/api-err"); then
    fail "API rate limit was accepted"
fi
assert_contains "$tmpdir/api-err" "rate limit" "API rate limit message"
assert_eq "" "$tag" "API rate limit output"

if FAKE_CURL_MODE=api-401 plak_release_resolve_latest_tag >/dev/null 2>"$tmpdir/api-err"; then
    fail "API authentication failure was accepted"
fi
assert_contains "$tmpdir/api-err" "authentication failed" "API auth message"

if FAKE_CURL_MODE=api-network plak_release_resolve_latest_tag >/dev/null 2>"$tmpdir/api-err"; then
    fail "API network failure was accepted"
fi
assert_contains "$tmpdir/api-err" "Could not reach the GitHub API" "API network message"

if FAKE_CURL_MODE=api-500 plak_release_resolve_latest_tag >/dev/null 2>"$tmpdir/api-err"; then
    fail "API server error was accepted"
fi
assert_contains "$tmpdir/api-err" "unavailable" "API server error message"

only_foreign="$tmpdir/only-foreign.json"
tags_json nightly release-9.9.9 v1.0.0-rc1 v1.0.0+build > "$only_foreign"
export FAKE_TAGS_JSON="$only_foreign"
if plak_release_resolve_latest_tag >/dev/null 2>"$tmpdir/api-err"; then
    fail "API without a stable tag was accepted"
fi
assert_contains "$tmpdir/api-err" "No stable Plak release tag" "no stable tag message"

# --- Installer -------------------------------------------------------------
current_tag=$(./plak.sh version | awk '{print $2}')
current_payload="$ROOT_DIR/plak.sh"
new_tag="v9.9.9"
new_version="9.9.9"
new_payload="$tmpdir/plak-9.9.9.sh"
sed "s/^PLAK_VERSION=\".*\"/PLAK_VERSION=\"${new_version}\"/" "$current_payload" > "$new_payload"
chmod +x "$new_payload"
assert_eq "plak v${new_version}" "$("$new_payload" version)" "new test payload version"

current_tags="$tmpdir/current-tags.json"
tags_json v0.0.1 "$current_tag" v9.9.9-rc1 nightly v1.0.0+build > "$current_tags"
new_tags="$tmpdir/new-tags.json"
tags_json v0.4.9 "$new_tag" v9.9.10-rc1 v9.9.8 > "$new_tags"

run_installer() {
    local log="$1" tags="$2" payload="$3" mode="${4:-ok}"
    PLAK_INSTALL_DIR="$tmpdir/install" \
    FAKE_CURL_LOG="$log" FAKE_TAGS_JSON="$tags" FAKE_PAYLOAD="$payload" \
    FAKE_CURL_MODE="$mode" \
    bash "$ROOT_DIR/install.sh"
}

reset_install_prior() {
    rm -rf "$tmpdir/install"
    mkdir -p "$tmpdir/install"
    cp "$current_payload" "$tmpdir/install/plak"
    chmod 755 "$tmpdir/install/plak"
    cp "$tmpdir/install/plak" "$tmpdir/prior-plak"
}

assert_install_preserved() {
    local label="$1"
    cmp -s "$tmpdir/prior-plak" "$tmpdir/install/plak" \
        || fail "$label changed the existing executable"
    assert_no_temps "$tmpdir/install" "$label"
    assert_no_temps "$tmpdir/tmp" "$label"
}

# Successful stable install, including mode checks and the exact tag URL.
rm -rf "$tmpdir/install"
mkdir -p "$tmpdir/install"
install_log="$tmpdir/install.log"
stat_log="$tmpdir/install-stat.log"
: > "$install_log"
: > "$stat_log"
FAKE_CURL_STAT_LOG="$stat_log" run_installer "$install_log" "$current_tags" "$current_payload" \
    > "$tmpdir/install.out" 2>&1 || fail "stable installer failed: $(cat "$tmpdir/install.out")"
cmp -s "$current_payload" "$tmpdir/install/plak" || fail "installer installed different bytes"
assert_eq "755" "$(file_mode "$tmpdir/install/plak")" "installed executable mode"
assert_contains "$tmpdir/install.out" "Installed Plak to" "installer success message"
assert_contains "$install_log" "raw.githubusercontent.com/plakio/plak-cli/${current_tag}/plak.sh" "installer tag URL"
assert_no_main_fallback "$install_log" "installer"
assert_no_temps "$tmpdir/install" "successful installer"
assert_no_temps "$tmpdir/tmp" "successful installer"
grep -q '^600$' "$stat_log" || fail "downloaded script was not created with mode 0600"

# Every API/download/validation failure leaves the previous executable intact.
for case_name in api-403 api-401 api-network api-500 download-404 download-network download-partial download-truncated download-empty mismatch; do
    reset_install_prior
    : > "$install_log"
    mode="$case_name"
    payload="$new_payload"
    if [ "$case_name" = "mismatch" ]; then
        payload="$current_payload"
        mode="download-mismatch"
        export FAKE_MISMATCH_PAYLOAD="$current_payload"
    fi
    if run_installer "$install_log" "$new_tags" "$payload" "$mode" > "$tmpdir/install.out" 2>&1; then
        fail "installer accepted failure case $case_name"
    fi
    assert_install_preserved "installer $case_name"
    assert_no_main_fallback "$install_log" "installer $case_name"
done

# Interrupting a slow download cleans up and preserves the executable.
reset_install_prior
: > "$install_log"
slow_marker="$tmpdir/slow-marker"
rm -f "$slow_marker"
PLAK_INSTALL_DIR="$tmpdir/install" FAKE_CURL_LOG="$install_log" FAKE_TAGS_JSON="$new_tags" \
FAKE_PAYLOAD="$new_payload" FAKE_CURL_MODE=download-slow FAKE_SLOW_MARKER="$slow_marker" \
    bash "$ROOT_DIR/install.sh" > "$tmpdir/install.out" 2>&1 &
slow_pid=$!
slow_waited=0
while [ ! -f "$slow_marker" ] && [ "$slow_waited" -lt 50 ]; do
    sleep 1
    slow_waited=$((slow_waited + 1))
done
if [ ! -f "$slow_marker" ]; then
    kill -TERM "$slow_pid" 2>/dev/null || true
    wait "$slow_pid" 2>/dev/null || true
    fail "slow download did not start"
fi
kill -TERM "$slow_pid"
wait "$slow_pid" 2>/dev/null || true
assert_install_preserved "interrupted installer"

# Downloading a 404 must surface the tag, not fall back.
reset_install_prior
: > "$install_log"
if run_installer "$install_log" "$new_tags" "$new_payload" download-404 > "$tmpdir/install.out" 2>&1; then
    fail "installer accepted a missing tag"
fi
assert_contains "$tmpdir/install.out" "could not download" "missing tag message"
assert_contains "$tmpdir/install.out" "Nothing was installed" "missing tag preservation message"

# A tag with no stable match is an error, not a main install.
only_foreign="$tmpdir/only-foreign.json"
tags_json nightly release-9.9.9 v1.0.0-rc1 > "$only_foreign"
reset_install_prior
: > "$install_log"
if run_installer "$install_log" "$only_foreign" "$new_payload" > "$tmpdir/install.out" 2>&1; then
    fail "installer accepted a tag list without a stable tag"
fi
assert_contains "$tmpdir/install.out" "No stable Plak release tag" "installer no stable tag message"
assert_install_preserved "installer no stable tag"

# Explicit PLAK_INSTALL_URL remains a test/advanced override, without an API call.
reset_install_prior
: > "$install_log"
PLAK_INSTALL_URL="file://$current_payload" run_installer "$install_log" "$current_tags" "$current_payload" \
    > "$tmpdir/install.out" 2>&1 || fail "explicit PLAK_INSTALL_URL install failed"
cmp -s "$current_payload" "$tmpdir/install/plak" || fail "explicit URL installed different bytes"
if grep -Fq 'api.github.com' "$install_log"; then
    fail "explicit PLAK_INSTALL_URL still called the tags API"
fi

# Invalid explicit payload is rejected and preserved.
reset_install_prior
: > "$install_log"
truncated_payload="$tmpdir/truncated.sh"
printf '#!/usr/bin/env bash\n' > "$truncated_payload"
if PLAK_INSTALL_URL="file://$truncated_payload" run_installer "$install_log" "$current_tags" "$current_payload" \
    > "$tmpdir/install.out" 2>&1; then
    fail "explicit invalid payload was installed"
fi
assert_install_preserved "installer explicit invalid payload"

# Local --dev install: no network, and the repository plak.sh is not deleted.
reset_install_prior
: > "$install_log"
PLAK_INSTALL_DIR="$tmpdir/install" FAKE_CURL_LOG="$install_log" \
    bash "$ROOT_DIR/install.sh" --dev > "$tmpdir/install.out" 2>&1 \
    || fail "--dev install failed"
cmp -s "$current_payload" "$tmpdir/install/plak" || fail "--dev installed different bytes"
[ -f "$current_payload" ] || fail "--dev deleted the repository plak.sh"
[ ! -s "$install_log" ] || fail "--dev unexpectedly used curl"

# Piped bootstrap (the same entrypoint as https://plak.sh/install | bash).
reset_install_prior
: > "$install_log"
PLAK_INSTALL_DIR="$tmpdir/install" \
FAKE_CURL_LOG="$install_log" FAKE_TAGS_JSON="$current_tags" FAKE_PAYLOAD="$current_payload" \
    bash < "$ROOT_DIR/install.sh" > "$tmpdir/install.out" 2>&1 \
    || fail "piped installer failed"
cmp -s "$current_payload" "$tmpdir/install/plak" || fail "piped installer installed different bytes"

# Concurrent installers use unique staging paths and never corrupt the result.
rm -rf "$tmpdir/install"
mkdir -p "$tmpdir/install"
payload_a="$current_payload"
payload_b="$tmpdir/plak-9.9.8.sh"
sed 's/^PLAK_VERSION=".*"/PLAK_VERSION="9.9.8"/' "$current_payload" > "$payload_b"
chmod +x "$payload_b"
tags_a="$tmpdir/tags-a.json"
tags_b="$tmpdir/tags-b.json"
tags_json "$current_tag" v0.0.1 > "$tags_a"
tags_json v9.9.8 v0.0.1 > "$tags_b"
: > "$tmpdir/log-a"
: > "$tmpdir/log-b"
PLAK_INSTALL_DIR="$tmpdir/install" FAKE_CURL_LOG="$tmpdir/log-a" FAKE_TAGS_JSON="$tags_a" \
FAKE_PAYLOAD="$payload_a" bash "$ROOT_DIR/install.sh" > "$tmpdir/out-a" 2>&1 &
pid_a=$!
PLAK_INSTALL_DIR="$tmpdir/install" FAKE_CURL_LOG="$tmpdir/log-b" FAKE_TAGS_JSON="$tags_b" \
FAKE_PAYLOAD="$payload_b" bash "$ROOT_DIR/install.sh" > "$tmpdir/out-b" 2>&1 &
pid_b=$!
wait "$pid_a" || fail "concurrent installer A failed: $(cat "$tmpdir/out-a")"
wait "$pid_b" || fail "concurrent installer B failed: $(cat "$tmpdir/out-b")"
final_version=$("$tmpdir/install/plak" version)
case "$final_version" in
    "plak v${current_tag#v}"|"plak v9.9.8") ;;
    *) fail "concurrent installers left an invalid executable: $final_version" ;;
esac
if ! cmp -s "$tmpdir/install/plak" "$payload_a" && ! cmp -s "$tmpdir/install/plak" "$payload_b"; then
    fail "concurrent installers left bytes from neither payload"
fi
unique_temps=$(awk -F'\t' '$2 ~ /plak-install\./ {print $2}' "$tmpdir/log-a" "$tmpdir/log-b" | sort -u | wc -l | tr -d ' ')
[ "$unique_temps" -eq 2 ] || fail "concurrent installers shared a staging path"
assert_no_temps "$tmpdir/install" "concurrent installers"

# A pre-existing /tmp/plak.sh.latest-like file is never touched.
printf 'third-party\n' > "$tmpdir/tmp/plak.sh.latest"
reset_install_prior
: > "$install_log"
run_installer "$install_log" "$current_tags" "$current_payload" > "$tmpdir/install.out" 2>&1 \
    || fail "install with third-party temp file failed"
assert_eq "third-party" "$(cat "$tmpdir/tmp/plak.sh.latest")" "third-party fixed temp file"
if grep -Fq '/tmp/plak.sh.latest' install.sh commands/site/upgrade plak.sh; then
    fail "the fixed /tmp/plak.sh.latest path is still referenced"
fi

# --- Upgrade ---------------------------------------------------------------
old_version="0.4.66"
old_script="$tmpdir/plak-old.sh"
sed "s/^PLAK_VERSION=\".*\"/PLAK_VERSION=\"${old_version}\"/" "$current_payload" > "$old_script"
chmod +x "$old_script"
assert_eq "plak v${old_version}" "$("$old_script" version)" "old test payload version"

reset_upgrade_prior() {
    rm -rf "$tmpdir/upgrade-bin"
    mkdir -p "$tmpdir/upgrade-bin"
    cp "$old_script" "$tmpdir/upgrade-bin/plak"
    chmod 755 "$tmpdir/upgrade-bin/plak"
    cp "$tmpdir/upgrade-bin/plak" "$tmpdir/prior-upgrade-plak"
}

run_upgrade() {
    local log="$1" tags="$2" payload="$3" mode="${4:-ok}"
    PATH="$tmpdir/fakebin:$tmpdir/upgrade-bin:/usr/bin:/bin" \
    PLAK_NO_PATH_PRELUDE=1 HOME="$tmpdir/home" TMPDIR="$tmpdir/tmp" \
    FAKE_CURL_LOG="$log" FAKE_TAGS_JSON="$tags" FAKE_PAYLOAD="$payload" \
    FAKE_CURL_MODE="$mode" \
    "$tmpdir/upgrade-bin/plak" upgrade
}

assert_upgrade_preserved() {
    local label="$1"
    cmp -s "$tmpdir/prior-upgrade-plak" "$tmpdir/upgrade-bin/plak" \
        || fail "$label changed the existing executable"
    assert_no_temps "$tmpdir/upgrade-bin" "$label"
    assert_no_temps "$tmpdir/tmp" "$label"
}

# Successful upgrade from an older script to the newest stable tag.
reset_upgrade_prior
upgrade_log="$tmpdir/upgrade.log"
: > "$upgrade_log"
run_upgrade "$upgrade_log" "$new_tags" "$new_payload" > "$tmpdir/upgrade.out" 2>&1 \
    || fail "upgrade failed: $(cat "$tmpdir/upgrade.out")"
cmp -s "$new_payload" "$tmpdir/upgrade-bin/plak" || fail "upgrade installed different bytes"
assert_eq "755" "$(file_mode "$tmpdir/upgrade-bin/plak")" "upgraded executable mode"
assert_contains "$tmpdir/upgrade.out" "Upgrading Plak to version ${new_version}" "upgrade message"
assert_contains "$upgrade_log" "raw.githubusercontent.com/plakio/plak-cli/${new_tag}/plak.sh" "upgrade tag URL"
assert_no_main_fallback "$upgrade_log" "upgrade"
assert_no_temps "$tmpdir/upgrade-bin" "successful upgrade"

# Already current: no script download at all.
reset_upgrade_prior
: > "$upgrade_log"
same_tags="$tmpdir/same-tags.json"
tags_json "v${old_version}" > "$same_tags"
run_upgrade "$upgrade_log" "$same_tags" "$new_payload" > "$tmpdir/upgrade.out" 2>&1 \
    || fail "upgrade at current version failed"
assert_contains "$tmpdir/upgrade.out" "already using the latest stable version" "already current message"
if grep -Fq 'raw.githubusercontent.com' "$upgrade_log"; then
    fail "already-current upgrade downloaded a script"
fi
cmp -s "$tmpdir/prior-upgrade-plak" "$tmpdir/upgrade-bin/plak" || fail "already-current upgrade changed the executable"

# Current is newer than the stable channel: never downgrade.
newer_script="$tmpdir/plak-newer.sh"
sed 's/^PLAK_VERSION=".*"/PLAK_VERSION="9.9.9"/' "$current_payload" > "$newer_script"
chmod +x "$newer_script"
rm -rf "$tmpdir/upgrade-bin"
mkdir -p "$tmpdir/upgrade-bin"
cp "$newer_script" "$tmpdir/upgrade-bin/plak"
: > "$upgrade_log"
older_tags="$tmpdir/older-tags.json"
tags_json "v${old_version}" > "$older_tags"
run_upgrade "$upgrade_log" "$older_tags" "$new_payload" > "$tmpdir/upgrade.out" 2>&1 \
    || fail "newer-than-stable upgrade failed"
assert_contains "$tmpdir/upgrade.out" "newer than the latest stable release" "newer-than-stable message"
if grep -Fq 'raw.githubusercontent.com' "$upgrade_log"; then
    fail "newer-than-stable upgrade downloaded a script"
fi

# Unknown local version: refuse to replace it.
unknown_script="$tmpdir/plak-unknown.sh"
sed 's/^PLAK_VERSION=".*"/PLAK_VERSION="dev"/' "$current_payload" > "$unknown_script"
chmod +x "$unknown_script"
rm -rf "$tmpdir/upgrade-bin"
mkdir -p "$tmpdir/upgrade-bin"
cp "$unknown_script" "$tmpdir/upgrade-bin/plak"
cp "$tmpdir/upgrade-bin/plak" "$tmpdir/prior-upgrade-plak"
: > "$upgrade_log"
if run_upgrade "$upgrade_log" "$new_tags" "$new_payload" > "$tmpdir/upgrade.out" 2>&1; then
    fail "upgrade accepted a non-semver local version"
fi
assert_contains "$tmpdir/upgrade.out" "not a stable semantic version" "unknown version message"
assert_upgrade_preserved "upgrade unknown version"

# API and download failures preserve the installed script.
for case_name in api-403 api-network api-500 download-404 download-network download-partial download-truncated download-empty; do
    reset_upgrade_prior
    : > "$upgrade_log"
    if run_upgrade "$upgrade_log" "$new_tags" "$new_payload" "$case_name" > "$tmpdir/upgrade.out" 2>&1; then
        fail "upgrade accepted failure case $case_name"
    fi
    assert_upgrade_preserved "upgrade $case_name"
    assert_no_main_fallback "$upgrade_log" "upgrade $case_name"
done

# Tag/embedded-version mismatch is rejected and preserved.
reset_upgrade_prior
: > "$upgrade_log"
export FAKE_MISMATCH_PAYLOAD="$old_script"
if run_upgrade "$upgrade_log" "$new_tags" "$new_payload" download-mismatch > "$tmpdir/upgrade.out" 2>&1; then
    fail "upgrade accepted a version mismatch"
fi
assert_contains "$tmpdir/upgrade.out" "does not match embedded version" "upgrade mismatch message"
assert_upgrade_preserved "upgrade mismatch"

# A failed chmod during replacement must not swap in a non-executable file.
# The helper runs under `if !`, which suppresses `set -e`, so the chmod step
# needs its own explicit check: without it the upgrade reported success after
# replacing a working executable with mode 0600.
REAL_CHMOD=$(PATH=/usr/bin:/bin command -v chmod)
export REAL_CHMOD
cat > "$tmpdir/fakebin/chmod" <<'CHMOD'
#!/usr/bin/env bash
for arg in "$@"; do
    case "$arg" in
        *.plak-upgrade.*)
            if [ "${FAKE_CHMOD_FAIL_UPGRADE:-0}" = "1" ]; then
                echo "fake chmod: refusing $arg" >&2
                exit 1
            fi
            ;;
    esac
done
exec "$REAL_CHMOD" "$@"
CHMOD
chmod +x "$tmpdir/fakebin/chmod"
reset_upgrade_prior
: > "$upgrade_log"
if FAKE_CHMOD_FAIL_UPGRADE=1 run_upgrade "$upgrade_log" "$new_tags" "$new_payload" > "$tmpdir/upgrade.out" 2>&1; then
    fail "upgrade accepted a chmod failure"
fi
assert_contains "$tmpdir/upgrade.out" "Could not set permissions" "upgrade chmod failure message"
if grep -q 'successfully upgraded' "$tmpdir/upgrade.out"; then
    fail "upgrade reported success after a chmod failure"
fi
assert_upgrade_preserved "upgrade chmod failure"
assert_eq "plak v${old_version}" "$("$tmpdir/upgrade-bin/plak" version)" "prior executable still runs after chmod failure"

# A pre-existing /tmp/plak.sh.latest-like file is never touched by upgrade.
printf 'third-party\n' > "$tmpdir/tmp/plak.sh.latest"
reset_upgrade_prior
: > "$upgrade_log"
run_upgrade "$upgrade_log" "$new_tags" "$new_payload" > "$tmpdir/upgrade.out" 2>&1 \
    || fail "upgrade with third-party temp file failed"
assert_eq "third-party" "$(cat "$tmpdir/tmp/plak.sh.latest")" "upgrade third-party fixed temp file"

# Concurrent replacements of the same executable use unique staging paths.
concurrent_dir="$tmpdir/concurrent-upgrade"
mkdir -p "$concurrent_dir"
concurrent_target="$concurrent_dir/plak"
cp "$old_script" "$concurrent_target"
chmod 755 "$concurrent_target"
payload_a="$new_payload"
payload_b="$tmpdir/plak-9.9.8.sh"
: > "$tmpdir/upgrade-log-a"
: > "$tmpdir/upgrade-log-b"
FAKE_CURL_LOG="$tmpdir/upgrade-log-a" FAKE_PAYLOAD="$payload_a" FAKE_CURL_MODE=ok \
    plak_upgrade_replace_plak_script v9.9.9 "$concurrent_target" &
pid_a=$!
FAKE_CURL_LOG="$tmpdir/upgrade-log-b" FAKE_PAYLOAD="$payload_b" FAKE_CURL_MODE=ok \
    plak_upgrade_replace_plak_script v9.9.8 "$concurrent_target" &
pid_b=$!
wait "$pid_a" || fail "concurrent upgrade replacement A failed"
wait "$pid_b" || fail "concurrent upgrade replacement B failed"
final_version=$("$concurrent_target" version)
case "$final_version" in
    "plak v9.9.9"|"plak v9.9.8") ;;
    *) fail "concurrent upgrades left an invalid executable: $final_version" ;;
esac
if ! cmp -s "$concurrent_target" "$payload_a" && ! cmp -s "$concurrent_target" "$payload_b"; then
    fail "concurrent upgrades left bytes from neither payload"
fi
unique_temps=$(awk -F'\t' '$2 ~ /plak-upgrade\./ {print $2}' "$tmpdir/upgrade-log-a" "$tmpdir/upgrade-log-b" | sort -u | wc -l | tr -d ' ')
[ "$unique_temps" -eq 2 ] || fail "concurrent upgrades shared a staging path"
assert_no_temps "$concurrent_dir" "concurrent upgrade replacements"

# --- Optional macOS default-path check in an isolated mount namespace ------
mac_bin="$tmpdir/macbin"
mkdir -p "$mac_bin"
cat > "$mac_bin/uname" <<'MAC_UNAME'
#!/usr/bin/env bash
case "${1:-}" in
    -s) echo Darwin ;;
    -m) echo arm64 ;;
    *) echo Darwin ;;
esac
MAC_UNAME
chmod +x "$mac_bin/uname"
ln -s "$tmpdir/fakebin/curl" "$mac_bin/curl"

mac_log="$tmpdir/mac.log"
mac_install_out="$tmpdir/mac-install.out"
: > "$mac_log"
if unshare -rm true 2>/dev/null; then
    # shellcheck disable=SC2016
    if unshare -rm bash -c '
        set -e
        mount -t tmpfs tmpfs /opt
        mkdir -p /opt/homebrew/bin
        PATH="$1:$2:$PATH" PLAK_NO_PATH_PRELUDE=1 HOME="$3" TMPDIR="$4" \
        FAKE_CURL_LOG="$5" FAKE_TAGS_JSON="$6" FAKE_PAYLOAD="$7" \
            bash "$8/install.sh" > "$9" 2>&1
        test -x /opt/homebrew/bin/plak
        /opt/homebrew/bin/plak version
    ' _ "$mac_bin" "$tmpdir/fakebin" "$tmpdir/home" "$tmpdir/tmp" "$mac_log" "$current_tags" "$current_payload" "$ROOT_DIR" "$mac_install_out" > "$tmpdir/mac.out" 2>&1; then
        assert_contains "$tmpdir/mac.out" "plak v${current_tag#v}" "macOS arm64 default path"
    else
        echo "release channel test: skipped macOS default-path check (mount namespace unavailable)" >&2
    fi
else
    echo "release channel test: skipped macOS default-path check (user namespaces unavailable)" >&2
fi

echo "Release channel tests passed."
