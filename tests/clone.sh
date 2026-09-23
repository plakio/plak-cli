#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

./compile.sh >/dev/null

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() {
    echo "clone regression test failed: $1" >&2
    exit 1
}

source ./plak.sh >/dev/null

SITES_DIR="$tmpdir/sites"
export SITES_DIR
CUSTOM_CADDY_DIR="$tmpdir/directives"
export CUSTOM_CADDY_DIR
mkdir -p "$SITES_DIR" "$CUSTOM_CADDY_DIR"

# Fake mysql/mysqldump record calls and maintain a simple database registry.
bin="$tmpdir/bin"
mkdir -p "$bin"
cat > "$bin/mysql" <<'MYSQL'
#!/usr/bin/env bash
printf 'mysql %s\n' "$*" >> "$CLONE_LOG"
sql=""
for arg in "$@"; do
    case "$arg" in
        *CREATE\ DATABASE*|*DROP\ DATABASE*) sql="$arg" ;;
    esac
done
case "$sql" in
    *CREATE\ DATABASE*) echo "created" >> "$CLONE_DBS" ;;
esac
[ "${CLONE_MYSQL_FAIL:-0}" = 1 ] && exit 1
exit 0
MYSQL
cat > "$bin/mysqldump" <<'MYSQLDUMP'
#!/usr/bin/env bash
printf 'mysqldump %s\n' "$*" >> "$CLONE_LOG"
[ "${CLONE_DUMP_FAIL:-0}" = 1 ] && exit 1
echo "-- dump"
exit 0
MYSQLDUMP
chmod +x "$bin/mysql" "$bin/mysqldump"
export PATH="$bin:$PATH"

clone_log="$tmpdir/clone.log"
export CLONE_LOG="$clone_log"
export CLONE_DBS="$tmpdir/dbs.log"
: > "$clone_log"
: > "$CLONE_DBS"

wp_log="$tmpdir/wp.log"
: > "$wp_log"
fake_wp="$tmpdir/fake-wp"
cat > "$fake_wp" <<'FAKE_WP'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WP_TEST_LOG"
case "$*" in
    "config get DB_NAME"*) echo "custom_source_db" ;;
    "option get home"*) echo "https://src.localhost:8453/wp" ;;
    "option get siteurl"*) echo "https://src.localhost:8453" ;;
esac
exit 0
FAKE_WP
chmod +x "$fake_wp"
export WP_TEST_LOG="$wp_log"
get_wp_cmd() { echo "$fake_wp"; }
regenerate_caddyfile() { echo RELOAD >> "$CLONE_LOG"; }
url_for() { echo "https://$1"; }
plak_terminal_link() { echo "$1"; }
source_config() { DB_HOST=127.0.0.1; DB_PORT=3306; DB_USER=root; DB_PASSWORD=secret; }
gum() { :; }

# --- WordPress source ---
src="$SITES_DIR/src.localhost"
mkdir -p "$src/public/wp-content/uploads" "$src/logs" "$src/private"
touch "$src/public/wp-config.php"
echo original > "$src/public/wp-content/uploads/a.txt"
echo secret > "$src/logs/app.log"
echo "production" > "$src/.remote"
echo "reverse_proxy https://src.localhost/wp" > "$CUSTOM_CADDY_DIR/src.localhost"
echo "extra.localhost" > "$src/mappings"

plak_site_clone src dest --yes

dst="$SITES_DIR/dest.localhost"
[ -f "$dst/public/wp-content/uploads/a.txt" ] || fail "clone did not copy files"
grep -q "mysql .*CREATE DATABASE \`plak_site_dest_\`" "$clone_log" || fail "clone did not create an independent database"
grep -q "mysqldump .*custom_source_db" "$clone_log" || fail "clone did not read the source DB name from its real configuration"
grep -Fq "config set DB_NAME plak_site_dest_" "$wp_log" || fail "clone did not point the copy at its own database"
grep -Fq "search-replace https://src.localhost:8453 https://dest.localhost:8453" "$wp_log" || fail "clone did not rewrite siteurl preserving the port"
grep -Fq "search-replace https://src.localhost:8453/wp https://dest.localhost:8453/wp" "$wp_log" || fail "clone did not rewrite home preserving distinct values"
grep -Fq "option update home https://dest.localhost:8453/wp" "$wp_log" || fail "clone did not finalize destination home"
grep -Fq "option update siteurl https://dest.localhost:8453" "$wp_log" || fail "clone did not finalize destination siteurl"

[ ! -f "$dst/.remote" ] || fail "clone carried the remote binding over"
[ ! -f "$dst/logs/app.log" ] || fail "clone did not start with empty logs"
[ -f "$CUSTOM_CADDY_DIR/dest.localhost" ] || fail "clone did not copy custom directives"
if grep -q 'src.localhost' "$CUSTOM_CADDY_DIR/dest.localhost"; then
    fail "cloned directives still reference the source hostname"
fi
grep -q 'dest.localhost' "$CUSTOM_CADDY_DIR/dest.localhost" || fail "cloned directives did not target the destination"
[ ! -f "$dst/mappings" ] || fail "clone copied exclusive domains"
grep -q RELOAD "$clone_log" || fail "clone did not regenerate the server config"

# --- The source is untouched ---
[ -f "$src/public/wp-config.php" ] || fail "clone removed source files"
[ -f "$src/logs/app.log" ] || fail "clone removed source logs"
[ -f "$src/.remote" ] || fail "clone removed the source remote binding"

# --- Static source uses files only ---
plain_src="$SITES_DIR/plain.localhost"
mkdir -p "$plain_src/public"
echo "<h1>plain</h1>" > "$plain_src/public/index.php"
plak_site_clone plain plaincopy --yes
[ -f "$SITES_DIR/plaincopy.localhost/public/index.php" ] || fail "clone failed for a static site"

# --- Existing destination is rejected before any work ---
if plak_site_clone src dest --yes 2>/dev/null; then
    fail "clone overwrote an existing destination"
fi

# --- Missing source is rejected ---
if plak_site_clone ghost dest2 --yes 2>/dev/null; then
    fail "clone accepted a missing source"
fi

# --- Database creation failure cleans up without touching the source ---
: > "$clone_log"
if CLONE_MYSQL_FAIL=1 plak_site_clone src destfail --yes 2>/dev/null; then
    fail "clone succeeded despite a database failure"
fi
unset CLONE_MYSQL_FAIL
if [ -d "$SITES_DIR/destfail.localhost" ]; then
    fail "failed clone left its directory behind"
fi
[ -f "$src/public/wp-content/uploads/a.txt" ] || fail "failed clone damaged the source"

# --- Database dump failure cleans up ---
if CLONE_DUMP_FAIL=1 plak_site_clone src destdumpfail --yes 2>/dev/null; then
    fail "clone succeeded despite a dump failure"
fi
unset CLONE_DUMP_FAIL
if [ -d "$SITES_DIR/destdumpfail.localhost" ]; then
    fail "dump-failed clone left its directory behind"
fi

echo "Clone regression tests passed."
