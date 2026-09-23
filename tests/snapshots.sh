#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

./compile.sh >/dev/null

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() {
    echo "snapshot regression test failed: $1" >&2
    exit 1
}

source ./plak.sh >/dev/null

SITES_DIR="$tmpdir/sites"
export SITES_DIR
mkdir -p "$SITES_DIR/wp.localhost/public/wp-content/uploads" "$SITES_DIR/wp.localhost/private"
mkdir -p "$SITES_DIR/plain.localhost/public"
echo "original" > "$SITES_DIR/wp.localhost/public/wp-content/uploads/file.txt"
echo "original" > "$SITES_DIR/plain.localhost/public/index.php"
touch "$SITES_DIR/wp.localhost/public/wp-config.php"

wp_log="$tmpdir/wp.log"
: > "$wp_log"
fake_wp="$tmpdir/fake-wp"
cat > "$fake_wp" <<'FAKE_WP'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WP_TEST_LOG"
case "$*" in
    "db export "*)
        output="${3:-}"
        if [ -n "$output" ]; then
            printf 'CREATE TABLE `wp_options` (`option_id` bigint NOT NULL);\n' > "$output"
        fi
        ;;
    "db import "*)
        target="${3:-}"
        case "$target" in
            *pre-reset-backup.sql) [ "${SNAP_ROLLBACK_FAIL:-0}" = 1 ] && exit 1 ;;
            *) [ "${SNAP_IMPORT_FAIL:-0}" = 1 ] && exit 1 ;;
        esac
        ;;
esac
exit 0
FAKE_WP
chmod +x "$fake_wp"
export WP_TEST_LOG="$wp_log"
get_wp_cmd() { echo "$fake_wp"; }
regenerate_caddyfile() { :; }
gum() { :; }
source_config() { :; }

# --- create + list ---
create_json=$(plak_snapshot_create wp --note "first" --json)
id=$(printf '%s' "$create_json" | sed -E 's/.*"id":"([^"]+)".*/\1/')
[ -n "$id" ] || fail "snapshot create did not return an id"
plak_snapshot_valid_id "$id" || fail "snapshot id '$id' is not unique/valid"
[ -s "$SITES_DIR/wp.localhost/private/snapshots/$id/files.tar.gz" ] || fail "snapshot did not archive files"
[ -s "$SITES_DIR/wp.localhost/private/snapshots/$id/database.sql" ] || fail "snapshot did not export the database"
[ "$(plak_snapshot_meta "$SITES_DIR/wp.localhost/private/snapshots/$id" note)" = "first" ] || fail "snapshot note was not stored"

second_json=$(plak_snapshot_create wp --json)
second_id=$(printf '%s' "$second_json" | sed -E 's/.*"id":"([^"]+)".*/\1/')
[ "$second_id" != "$id" ] || fail "concurrent snapshot ids collided"

list_json=$(plak_snapshot_list wp --json)
grep -q "\"id\":\"$id\"" <<<"$list_json" || fail "list omitted the created snapshot"
grep -q "\"id\":\"$second_id\"" <<<"$list_json" || fail "list omitted the second snapshot"

# Plain sites capture files only, never a database.
plain_json=$(plak_snapshot_create plain --json)
plain_id=$(printf '%s' "$plain_json" | sed -E 's/.*"id":"([^"]+)".*/\1/')
[ ! -f "$SITES_DIR/plain.localhost/private/snapshots/$plain_id/database.sql" ] || fail "plain snapshot included a database"
grep -q '"type":"plain"' <<<"$plain_json" || fail "plain snapshot was not typed as plain"

# --- export ---
export_out="$tmpdir/export.zip"
plak_snapshot_export wp "$id" --output "$export_out" >/dev/null
[ -s "$export_out" ] || fail "snapshot export produced no archive"
unzip -Z1 "$export_out" | grep -q 'files.tar.gz' || fail "export is missing the files archive"

# --- restore (success) replaces files ---
echo "changed" > "$SITES_DIR/wp.localhost/public/wp-content/uploads/file.txt"
plak_snapshot_restore wp "$id" --yes >/dev/null
grep -q original "$SITES_DIR/wp.localhost/public/wp-content/uploads/file.txt" || fail "restore did not bring back the original files"
grep -Fq "db export" "$wp_log" || fail "restore did not snapshot the current database first"
grep -Fq "db reset" "$wp_log" || fail "restore did not reset the database"
grep -Fq "db import" "$wp_log" || fail "restore did not import the snapshot database"
[ ! -d "$SITES_DIR/wp.localhost/private/restore_recovery" ] || fail "successful restore kept recovery material"
# A safety snapshot of the pre-restore state must exist.
safety_count=$(plak_snapshot_list_ids wp | wc -l)
[ "$safety_count" -ge 3 ] || fail "restore did not keep a safety snapshot"

# --- restore failure rolls back ---
before_lines=$(wc -l < "$wp_log")
SNAP_IMPORT_FAIL=1 plak_snapshot_restore wp "$id" --yes >/dev/null 2>&1 && fail "restore succeeded despite a failed database import" || true
unset SNAP_IMPORT_FAIL
tail -n +"$((before_lines + 1))" "$wp_log" > "$tmpdir/restore-fail.log"
grep -Fq 'pre-reset-backup.sql' "$tmpdir/restore-fail.log" || fail "failed restore did not roll back to the pre-reset snapshot"
[ ! -d "$SITES_DIR/wp.localhost/private/restore_recovery" ] || fail "confirmed rollback kept recovery material"

# --- restore failure keeps recovery material when rollback also fails ---
before_lines=$(wc -l < "$wp_log")
rc=0
SNAP_IMPORT_FAIL=1 SNAP_ROLLBACK_FAIL=1 plak_snapshot_restore wp "$id" --yes >/dev/null 2>&1 || rc=$?
unset SNAP_IMPORT_FAIL SNAP_ROLLBACK_FAIL
[ "$rc" -ne 0 ] || fail "restore succeeded despite a failed import and rollback"
[ -s "$SITES_DIR/wp.localhost/private/restore_recovery/pre-reset-backup.sql" ] || fail "failed rollback discarded recovery material"
[ -f "$SITES_DIR/wp.localhost/private/restore_recovery/state" ] || fail "failed rollback discarded recovery state"
# Clear the interrupted state so delete can be tested.
rm -rf "$SITES_DIR/wp.localhost/private/restore_recovery"

# --- delete ---
plak_snapshot_delete wp "$id" --yes >/dev/null
[ ! -d "$SITES_DIR/wp.localhost/private/snapshots/$id" ] || fail "delete left the snapshot on disk"
plak_snapshot_delete wp "$id" --yes >/dev/null 2>&1 && fail "deleting a missing snapshot succeeded" || true

echo "Snapshot regression tests passed."
