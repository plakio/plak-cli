#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

./compile.sh >/dev/null
(cd "$ROOT_DIR/go" && ./compile.sh >/dev/null)

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() {
    echo "import regression test failed: $1" >&2
    exit 1
}

source ./plak.sh >/dev/null

SITES_DIR="$tmpdir/sites"
export SITES_DIR
mkdir -p "$SITES_DIR"

# Stub engine: mimics go_migrate by moving files and touching the DB marker.
stub_go="$tmpdir/stub-go"
cat > "$stub_go" <<'STUB_GO'
#!/usr/bin/env bash
printf 'ENGINE %s\n' "$*" >> "$IMPORT_LOG"
case "${1:-}" in
    migrate)
        # Extract wp-content from the archive into the current site.
        url=""
        for arg in "$@"; do
            case "$arg" in --url=*) url="${arg#*=}" ;; esac
        done
        work=$(mktemp -d)
        unzip -q -o "$url" -d "$work" 2>/dev/null || tar xf "$url" -C "$work"
        src=$(find "$work" -type d -name wp-content -print -quit)
        mkdir -p ./wp-content
        cp -R "$src"/. ./wp-content/ 2>/dev/null || true
        for arg in "$@"; do
            case "$arg" in
                --destination-home=*) echo URLS_REWRITTEN >> "$IMPORT_LOG" ;;
            esac
        done
        rm -rf "$work"
        ;;
esac
exit 0
STUB_GO
chmod +x "$stub_go"

import_log="$tmpdir/import.log"
: > "$import_log"
export IMPORT_LOG="$import_log"
export PLAK_GO_RUNTIME="$stub_go"

# The destination site is created through the real `add` path in production;
# stub it here so the test focuses on import orchestration.
PLAK_SITE_CMD="$tmpdir/site-cmd"
cat > "$PLAK_SITE_CMD" <<'SITE_CMD'
#!/usr/bin/env bash
if [ "$1" = "add" ] && [ -n "${2:-}" ]; then
    mkdir -p "$SITES_DIR/$2.localhost/public"
    touch "$SITES_DIR/$2.localhost/public/wp-config.php"
fi
exit 0
SITE_CMD
chmod +x "$PLAK_SITE_CMD"

url_for() { echo "https://$1"; }
plak_terminal_link() { echo "$1"; }
inject_mu_plugin() { echo INJECT_MU >> "$IMPORT_LOG"; }
regenerate_caddyfile() { echo RELOAD >> "$IMPORT_LOG"; }
gum() { :; }

# --- Valid Plak-style ZIP export ---
make_zip() {
    local out="$1" root="$2"
    (cd "$root" && zip -qr "$out" source)
}

plak_root="$tmpdir/plak-export/source"
mkdir -p "$plak_root/wp-content/uploads" "$plak_root/wp-content/plugins/x"
echo "CREATE TABLE \`wp_options\` (\`option_id\` bigint);" > "$plak_root/db_export.sql"
echo upload > "$plak_root/wp-content/uploads/a.txt"
make_zip "$tmpdir/plak.zip" "$tmpdir/plak-export"

plak_site_import demo "$tmpdir/plak.zip" --yes
[ -f "$SITES_DIR/demo.localhost/public/wp-content/uploads/a.txt" ] || fail "import did not copy files into the site"
grep -q URLS_REWRITTEN "$import_log" || fail "import did not request URL rewriting"
grep -q RELOAD "$import_log" || fail "successful import did not regenerate the server config"

# --- Local-style archive with a top-level app/public directory ---
rm -rf "$SITES_DIR/demo2.localhost"
mkdir -p "$tmpdir/local-export/app/public/wp-content/themes"
echo "CREATE TABLE \`wp_options\` (\`option_id\` bigint);" > "$tmpdir/local-export/app/public/dump.sql"
echo theme > "$tmpdir/local-export/app/public/wp-content/themes/index.php"
(cd "$tmpdir/local-export" && tar czf "$tmpdir/local.tar.gz" app)
plak_site_import demo2 "$tmpdir/local.tar.gz" --yes --no-reload
[ -f "$SITES_DIR/demo2.localhost/public/wp-content/themes/index.php" ] || fail "import failed for a Local-style tar.gz archive"

# --- Custom table prefix and differing URL are passed through to the engine ---
cat > "$tmpdir/prefix-export.sql" <<'SQL'
CREATE TABLE `custom_options` (`option_id` bigint);
SQL
rm -rf "$SITES_DIR/demo3.localhost"
mkdir -p "$tmpdir/prefix/src/wp-content"
cp "$tmpdir/prefix-export.sql" "$tmpdir/prefix/src/custom_dump.sql"
(cd "$tmpdir/prefix/src" && zip -qr "$tmpdir/prefix.zip" .)
plak_site_import demo3 "$tmpdir/prefix.zip" --yes --no-reload
grep -q -- '--destination-home=https://demo3.localhost' "$import_log" || fail "import did not pass the destination URL"

# --- Reject existing destination before touching anything ---
if plak_site_import demo "$tmpdir/plak.zip" --yes 2>/dev/null; then
    fail "import overwrote an existing site"
fi

# --- Reject archives without an SQL dump ---
mkdir -p "$tmpdir/nosql/source/wp-content"
(cd "$tmpdir/nosql" && zip -qr "$tmpdir/nosql.zip" source)
if plak_site_import freshnosql "$tmpdir/nosql.zip" --yes 2>/dev/null; then
    fail "import accepted an archive without a SQL dump"
fi

# --- Reject multiple SQL dumps as ambiguous ---
mkdir -p "$tmpdir/multi/source/wp-content"
echo "CREATE TABLE a (id int);" > "$tmpdir/multi/source/one.sql"
echo "CREATE TABLE b (id int);" > "$tmpdir/multi/source/two.sql"
(cd "$tmpdir/multi" && zip -qr "$tmpdir/multi.zip" source)
if plak_site_import freshmulti "$tmpdir/multi.zip" --yes 2>/dev/null; then
    fail "import accepted an ambiguous archive"
fi

# --- Reject path traversal ---
mkdir -p "$tmpdir/evil"
echo "CREATE TABLE a (id int);" > "$tmpdir/evil/dump.sql"
(cd "$tmpdir/evil" && zip -q "$tmpdir/evil.zip" dump.sql)
python3 - "$tmpdir/evil.zip" <<'PY' 2>/dev/null || true
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "a") as z:
    z.writestr("../escape.php", "<?php")
    z.writestr("wp-content/index.php", "<?php")
PY
if plak_site_import freshevil "$tmpdir/evil.zip" --yes 2>/dev/null; then
    fail "import accepted an archive with escaping paths"
fi

# --- Reject multisite ---
mkdir -p "$tmpdir/ms/source/wp-content/uploads/sites/1"
echo "CREATE TABLE a (id int);" > "$tmpdir/ms/source/dump.sql"
echo "define('MULTISITE', true);" > "$tmpdir/ms/source/wp-config.php"
(cd "$tmpdir/ms" && zip -qr "$tmpdir/ms.zip" source)
if plak_site_import freshms "$tmpdir/ms.zip" --yes 2>/dev/null; then
    fail "import accepted a multisite backup"
fi

# --- Non-interactive without --yes must refuse destructive creation ---
# (import creates a new site, so it proceeds; deleting an existing site does not.)
if (exec 0</dev/null; plak_site_import demo "$tmpdir/plak.zip" 2>/dev/null); then
    fail "import overwrote an existing site without confirmation"
fi

echo "Import regression tests passed."
