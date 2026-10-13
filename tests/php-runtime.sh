#!/usr/bin/env bash
# Deterministic runtime selection fixtures; actual binaries are tested opt-in.
# shellcheck disable=SC2016 # Deliberately literal metacharacters in argv fixture.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/runtime with spaces"
export TEST_RUNTIME_DIR="$tmpdir/runtime with spaces"
cat > "$TEST_RUNTIME_DIR/frankenphp" <<'FRANK'
#!/usr/bin/env bash
if [ "$1" = version ]; then echo "FrankenPHP v${TEST_FRANK_VERSION:-1.13.0} PHP 8.5 Caddy test"; exit; fi
[ "$1" = php-cli ] || exit 89
shift
if grep -q PLAK_PHP_PROBE "$1"; then
    printf 'PLAK_PHP_PROBE|%s|%s\n' "${TEST_FINGERPRINT:-matching}" "${TEST_DIRECT_STATUS:-shifted}"; exit
fi
exec /usr/bin/php "$@"
FRANK
cat > "$TEST_RUNTIME_DIR/php-zts" <<'PHPZTS'
#!/usr/bin/env bash
if grep -q PLAK_PHP_PROBE "$1"; then
    printf 'PLAK_PHP_PROBE|%s|%s\n' "${TEST_COMPANION_FINGERPRINT:-matching}" "${TEST_COMPANION_STATUS:-ok}"; exit
fi
exec /usr/bin/php "$@"
PHPZTS
chmod +x "$TEST_RUNTIME_DIR/"*
source "$ROOT_DIR/shared/site/wp-cli"
PLAK_PHP_COMMAND=()
plak_php_cli_resolve "$TEST_RUNTIME_DIR/frankenphp"
[ "${#PLAK_PHP_COMMAND[@]}" -eq 1 ] && [ "${PLAK_PHP_COMMAND[0]}" = "$TEST_RUNTIME_DIR/php-zts" ]
cat > "$tmpdir/streams.php" <<'PHP'
<?php
echo json_encode([$argv,$argc,$_SERVER['argv'],$_SERVER['argc']]),"\n";
echo stream_get_contents(STDIN);
fwrite(STDERR,"original error\n"); exit(37);
PHP
rc=0
printf 'original input\n' | "${PLAK_PHP_COMMAND[@]}" "$tmpdir/streams.php" 'a b' '' '$(touch SHOULD_NOT_EXIST)' --flag > "$tmpdir/out" 2> "$tmpdir/err" || rc=$?
[ "$rc" -eq 37 ]
grep -q '^original error$' "$tmpdir/err"
python3 - "$tmpdir/out" "$tmpdir/streams.php" <<'PY'
import json,sys
lines=open(sys.argv[1]).readlines(); r=json.loads(lines[0]); expected=[sys.argv[2],'a b','','$(touch SHOULD_NOT_EXIST)','--flag']
assert r==[expected,len(expected),expected,len(expected)] and lines[1]=='original input\n'
PY
for mismatch in fingerprint argv; do
    if [ "$mismatch" = fingerprint ]; then export TEST_COMPANION_FINGERPRINT=different; else export TEST_COMPANION_STATUS=shifted; fi
    if plak_php_cli_resolve "$TEST_RUNTIME_DIR/frankenphp" > "$tmpdir/out" 2> "$tmpdir/err"; then exit 1; else [ "$?" -eq 78 ]; fi
    grep -q 'No matching sibling' "$tmpdir/err"
    unset TEST_COMPANION_FINGERPRINT TEST_COMPANION_STATUS
done
mv "$TEST_RUNTIME_DIR/php-zts" "$TEST_RUNTIME_DIR/companion"
if plak_php_cli_resolve "$TEST_RUNTIME_DIR/frankenphp" 2> "$tmpdir/err"; then exit 1; else [ "$?" -eq 78 ]; fi
mv "$TEST_RUNTIME_DIR/companion" "$TEST_RUNTIME_DIR/php-zts"
TEST_DIRECT_STATUS=ok plak_php_cli_resolve "$TEST_RUNTIME_DIR/frankenphp"
[ "${PLAK_PHP_COMMAND[1]}" = php-cli ]
TEST_FRANK_VERSION=1.12.7 plak_php_cli_resolve "$TEST_RUNTIME_DIR/frankenphp"
[ "${PLAK_PHP_COMMAND[1]}" = php-cli ]
echo 'PHP runtime selection, mismatch rejection and argv/streams/status tests passed'
