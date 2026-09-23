#!/usr/bin/env bash

# Hermetic regression tests: subprocess-level argv/streams and provisioning
# failures, using a fake runtime/database so no real site or service is touched.
# shellcheck disable=SC2016,SC1091 # Literal shell fixtures; runtime is compiled separately.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home with spaces"
mkdir -p "$HOME/.local/bin" "$HOME/Plak/Sites/demo.localhost/public/wp-includes" "$tmpdir/databases"
export PATH="$HOME/.local/bin:$PATH"
export WP_ARGV_LOG="$tmpdir/argv" WP_STEPS="$tmpdir/steps" WP_CWD_LOG="$tmpdir/cwd" WP_INI_LOG="$tmpdir/ini"
export MYSQL_LOG="$tmpdir/mysql" TEST_DATABASES="$tmpdir/databases" WP_RECORD_ONLY=1
export PLAK_TERMINAL_LINKS=0

fail() { echo "WP-CLI regression failed: $*" >&2; exit 1; }

cat > "$HOME/.local/bin/frankenphp" <<'FRANK'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = php-cli ] || exit 90
printf '%s\0' "$@" > "$WP_ARGV_LOG"
pwd -P > "$WP_CWD_LOG"
printf '%s\n' "${PHPRC:-}" > "$WP_INI_LOG"
shift 2
if [ "${1:-}" = --allow-root ]; then shift; fi
if [ "${WP_RECORD_ONLY:-0}" = 1 ]; then
    printf '%s' "${WP_STDOUT:-}"
    printf '%s' "${WP_STDERR:-}" >&2
    [ -z "${WP_STDIN_LOG:-}" ] || cat > "$WP_STDIN_LOG"
    exit "${WP_EXIT:-0}"
fi
stage="${1:-} ${2:-}"
printf '%s\n' "$stage" >> "$WP_STEPS"
if [ "${FAIL_STAGE:-}" = "$stage" ]; then
    echo "Error: simulated $stage failure" >&2
    exit 23
fi
case "$stage" in
    'core download')
        [ "${FAIL_STAGE:-}" != empty-download ] || exit 0
        mkdir -p wp-includes
        printf '<?php\n' > wp-includes/version.php
        printf '<?php\n' > wp-settings.php
        ;;
    'config create')
        if [ "${FAIL_STAGE:-}" = empty-config ]; then cat >/dev/null; exit 0; fi
        { printf '<?php\n'; cat; } > wp-config.php
        printf '%s\n' "$@" > .config-args
        ;;
    'core install')
        [ "${FAIL_STAGE:-}" != empty-install ] || exit 0
        touch .installed
        ;;
    'core is-installed') test -f .installed ;;
    'plugin delete') ;;
    'user login')
        [ "${FAIL_STAGE:-}" != empty-login ] || exit 0
        echo 'https://new.localhost:8453/wp-login.php?token=one-time'
        ;;
    *) echo "unexpected fake WP command: $*" >&2; exit 91 ;;
esac
FRANK
cat > "$HOME/.local/bin/mysql" <<'MYSQL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MYSQL_LOG"
sql="${!#}"
case "$sql" in
    'CREATE DATABASE '*)
        [ "${FAIL_STAGE:-}" != database ] || exit 22
        name="${sql#*\`}"
        name="${name%%\`*}"
        mkdir "$TEST_DATABASES/$name"
        ;;
    'DROP DATABASE '*)
        name="${sql#*\`}"
        name="${name%%\`*}"
        rm -r "$TEST_DATABASES/$name"
        ;;
    *) exit 92 ;;
esac
MYSQL
cat > "$HOME/.local/bin/gum" <<'GUM'
#!/usr/bin/env bash
printf '%s\n' "$*"
GUM
for bin in mariadb mailpit; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME/.local/bin/$bin"
done
chmod +x "$HOME/.local/bin/"*
printf '#!/usr/bin/env php\n<?php\n' > "$HOME/.local/bin/wp"
chmod +x "$HOME/.local/bin/wp"
touch "$HOME/Plak/Sites/demo.localhost/public/wp-config.php" "$HOME/Plak/Sites/demo.localhost/public/wp-includes/version.php"
cat > "$HOME/Plak/config" <<'CONFIG'
DB_USER='plak_test'
DB_PASSWORD='test-only'
DB_HOST='127.0.0.2'
DB_PORT='3317'
HTTPS_PORT='8453'
CONFIG

# The actual compiled router must not eat any argument after `wp <site>`.
export WP_STDOUT='{"ok":true}' WP_STDERR='a WP warning' WP_EXIT=37 WP_STDIN_LOG="$tmpdir/stdin"
args=(eval 'printf("%s", "a b");' --quiet --json --help -h -q --format=json '' '*.php' '$(touch SHOULD_NOT_EXIST)' 'a; b')
rc=0
printf 'input for wp\n' | ./plak.sh wp demo "${args[@]}" > "$tmpdir/out" 2> "$tmpdir/err" || rc=$?
[ "$rc" = 37 ] || fail "exit code was $rc, expected WP-CLI status 37"
[ "$(cat "$tmpdir/out")" = "$WP_STDOUT" ] || fail 'stdout changed'
[ "$(cat "$tmpdir/err")" = "$WP_STDERR" ] || fail 'stderr changed'
[ "$(cat "$WP_STDIN_LOG")" = 'input for wp' ] || fail 'stdin changed'
[ "$(cat "$WP_CWD_LOG")" = "$HOME/Plak/Sites/demo.localhost/public" ] || fail 'wrong working directory'
[ "$(cat "$WP_INI_LOG")" = "$HOME/Plak/php.ini" ] || fail 'PHPRC not inherited'
expected=(php-cli "$HOME/.local/bin/wp")
[ "$(id -u)" -ne 0 ] || expected+=(--allow-root)
expected+=("${args[@]}")
printf '%s\0' "${expected[@]}" > "$tmpdir/expected"
cmp "$tmpdir/expected" "$WP_ARGV_LOG" || fail 'arguments were split, expanded or consumed'

unset WP_STDOUT WP_STDERR WP_STDIN_LOG
export WP_EXIT=0
./plak.sh --json --quiet wp demo.localhost --version
expected=(php-cli "$HOME/.local/bin/wp")
[ "$(id -u)" -ne 0 ] || expected+=(--allow-root)
expected+=(--version)
printf '%s\0' "${expected[@]}" > "$tmpdir/expected"
cmp "$tmpdir/expected" "$WP_ARGV_LOG" || fail 'global flags leaked into WP-CLI'
./plak.sh wp --help | grep -q 'Usage: plak wp' || fail 'missing wrapper help'
for site in ../demo missing plain; do
    mkdir -p "$HOME/Plak/Sites/plain.localhost/public"
    if ./plak.sh wp "$site" --info >"$tmpdir/out" 2>"$tmpdir/err"; then fail "accepted invalid site $site"; fi
done
if ./plak.sh wp >"$tmpdir/out" 2>"$tmpdir/err"; then fail 'accepted missing site'; fi
if ./plak.sh wp demo >"$tmpdir/out" 2>"$tmpdir/err"; then fail 'accepted missing WP arguments'; fi

# Resolver and legacy shell callers use the same argv-safe runtime invocation.
source shared/site/wp-cli
source shared/validate
source shared/site/runtime
source commands/site/add
mkdir -p "$HOME/runtime files"
mv "$HOME/.local/bin/wp" "$HOME/runtime files/wp-cli.phar"
ln -s '../../runtime files/wp-cli.phar' "$HOME/.local/bin/wp"
[ "$(plak_wp_resolve_phar)" = "$HOME/runtime files/wp-cli.phar" ] || fail 'relative symlink with spaces'
rm "$HOME/.local/bin/wp"
cat > "$HOME/.local/bin/wp" <<'WRAPPER'
#!/usr/bin/env bash
exec /not/the/site/php "$HOME/runtime files/wp-cli.phar" "$@"
WRAPPER
chmod +x "$HOME/.local/bin/wp"
[ "$(plak_wp_resolve_phar)" = "$HOME/runtime files/wp-cli.phar" ] || fail 'HOME wrapper with spaces'
wp_cmd=$(get_wp_cmd)
$wp_cmd --info
IFS= read -r -d '' recorded < "$WP_ARGV_LOG" || true
[ "$recorded" = php-cli ] || fail 'legacy callers bypassed FrankenPHP'
printf '#!/bin/sh\nexec php "%s" "$@"\n' "$HOME/runtime files/wp-cli.phar" > "$HOME/.local/bin/wp"
[ "$(plak_wp_resolve_phar)" = "$HOME/runtime files/wp-cli.phar" ] || fail 'absolute quoted wrapper'
printf '#!/bin/sh\nexec php ../../runtime.phar "$@"\n' > "$HOME/.local/bin/wp"
ln -s 'runtime files/wp-cli.phar' "$HOME/runtime.phar"
[ "$(plak_wp_resolve_phar)" = "$HOME/runtime.phar" ] && fail 'resolver did not resolve final symlink'
[ "$(plak_wp_resolve_phar)" = "$HOME/runtime files/wp-cli.phar" ] || fail 'relative wrapper'
printf '#!/bin/sh\nexec "$SOME_PHP" "$COMPUTED_PHAR" "$@"\n' > "$HOME/.local/bin/wp"
if plak_wp_resolve_phar >"$tmpdir/out" 2>"$tmpdir/err"; then fail 'accepted opaque shell wrapper as PHP'; fi
grep -q 'cannot resolve' "$tmpdir/err" || fail 'opaque wrapper lacks actionable error'
rm "$HOME/.local/bin/wp"
ln -s wp "$HOME/.local/bin/wp"
if plak_wp_realpath "$HOME/.local/bin/wp" >"$tmpdir/out" 2>"$tmpdir/err"; then fail 'accepted symlink loop'; fi
rm "$HOME/.local/bin/wp"
printf '#!/bin/sh\nexec php "%s" "$@"\n' "$HOME/runtime files/wp-cli.phar" > "$HOME/.local/bin/wp"
chmod +x "$HOME/.local/bin/wp"

# Each failing stage must halt before later stages, remove its own resources,
# return nonzero, and never print the success banner.
export WP_RECORD_ONLY=0
db_name=plak_site_new_
for stage in database 'core download' empty-download 'config create' empty-config 'core install' empty-install 'plugin delete' 'user login' empty-login; do
    : > "$MYSQL_LOG"
    : > "$WP_STEPS"
    export FAIL_STAGE="$stage"
    if ./plak.sh add new --no-reload >"$tmpdir/out" 2>"$tmpdir/err"; then fail "success after failure: $stage"; fi
    [ ! -e "$SITES_DIR/new.localhost" ] || fail "left site after $stage"
    [ ! -e "$TEST_DATABASES/$db_name" ] || fail "left database after $stage"
    if grep -q 'created successfully' "$tmpdir/out"; then fail "false success after $stage"; fi
    case "$stage" in
        database)
            if grep -q DROP "$MYSQL_LOG"; then fail 'dropped DB after failed CREATE'; fi
            ;;
        'core download'|empty-download|'config create'|empty-config)
            if grep -q 'core install' "$WP_STEPS"; then fail "continued installation after $stage"; fi
            ;;
        'core install'|empty-install)
            if grep -q 'plugin delete' "$WP_STEPS"; then fail "continued after $stage"; fi
            ;;
    esac
done
unset FAIL_STAGE

# A pre-existing DB must not be reused or removed if its name collides.
mkdir "$TEST_DATABASES/$db_name"
touch "$TEST_DATABASES/$db_name/keep"
: > "$MYSQL_LOG"
if ./plak.sh add new --no-reload >"$tmpdir/out" 2>"$tmpdir/err"; then fail 'reused pre-existing database'; fi
test -f "$TEST_DATABASES/$db_name/keep" || fail 'destroyed pre-existing database'
if grep -q DROP "$MYSQL_LOG"; then fail 'attempted to drop pre-existing database'; fi
rm -r "${TEST_DATABASES:?}/${db_name:?}"

mkdir "$SITES_DIR/new.localhost"
touch "$SITES_DIR/new.localhost/keep"
if ./plak.sh add new --no-reload >"$tmpdir/out" 2>"$tmpdir/err"; then fail 'accepted existing site'; fi
test -f "$SITES_DIR/new.localhost/keep" || fail 'destroyed pre-existing site'
rm -r "$SITES_DIR/new.localhost"
if ./plak.sh add new --unknown >"$tmpdir/out" 2>"$tmpdir/err"; then fail 'ignored an unsupported option'; fi
[ ! -e "$SITES_DIR/new.localhost" ] || fail 'created resources with an unsupported option'

# Exercise the real MU-plugin/landing writers and successful provisioning.
./plak.sh add new --no-reload >"$tmpdir/out" 2>"$tmpdir/err"
grep -q "WP_ENVIRONMENT_TYPE', 'local'" "$SITES_DIR/new.localhost/public/wp-config.php" || fail 'missing local environment'
grep -q 'WP_DEBUG_LOG' "$SITES_DIR/new.localhost/public/wp-config.php" || fail 'lost debug settings'
grep -q -- '--dbhost=127.0.0.2:3317' "$SITES_DIR/new.localhost/public/.config-args" || fail 'lost database host/port'
test -s "$SITES_DIR/new.localhost/public/wp-content/mu-plugins/plak-cli-helper.php" || fail 'missing helper'
test -d "$TEST_DATABASES/$db_name" || fail 'cleaned successful database'
grep -q 'created successfully' "$tmpdir/out" || fail 'no success after valid install'
./plak.sh add landing --plain --no-reload >"$tmpdir/out" 2>"$tmpdir/err"
test -s "$SITES_DIR/landing.localhost/public/index.php" || fail 'static creation regressed'

# Failure after a completed install must keep the valid site for reload retry.
regenerate_caddyfile() { return 19; }
if plak_site_add reload-fail >"$tmpdir/out" 2>"$tmpdir/err"; then fail 'ignored reload failure'; fi
test -f "$SITES_DIR/reload-fail.localhost/public/.installed" || fail 'deleted complete site after reload failure'
test -d "$TEST_DATABASES/plak_site_reload_fail_" || fail 'deleted complete DB after reload failure'
grep -q 'plak reload' "$tmpdir/err" || fail 'missing reload recovery hint'

echo 'WP-CLI and site creation regression tests passed.'
