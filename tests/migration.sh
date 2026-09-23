#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() {
    echo "migration regression test failed: $1" >&2
    exit 1
}

assert_before() {
    local first="$1" second="$2" file="$3"
    local first_line second_line
    first_line=$(grep -n -m1 "$first" "$file" | cut -d: -f1)
    second_line=$(grep -n -m1 "$second" "$file" | cut -d: -f1)
    if [ -z "$first_line" ] || [ -z "$second_line" ] || [ "$first_line" -ge "$second_line" ]; then
        fail "'$first' did not occur before '$second'"
    fi
}

# Exercise go_migrate with explicit URL context. The fake WP-CLI records every
# call, allowing the test to prove that home/siteurl are not queried around the
# reset and that distinct values survive as distinct mappings.
source go/shared/logging
source go/shared/archive
source go/shared/private-dir
source go/shared/database
source go/shared/wp-cli
source go/commands/migrate

wp_log="$tmpdir/wp.log"
fake_wp="$tmpdir/fake-wp"
cat > "$fake_wp" <<'FAKE_WP'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WP_TEST_LOG"
case "$*" in
    "option get blog_public"*) echo 1 ;;
    "config get table_prefix"*) echo wp_ ;;
    "db export"*)
        output="${3:-}"
        [ -n "$output" ] && cat > "$output" <<'SQL'
CREATE TABLE `wp_options` (`option_id` bigint NOT NULL);
SQL
        ;;
    "plugin is-installed"*|"plugin is-active"*) exit 1 ;;
esac
exit 0
FAKE_WP
chmod +x "$fake_wp"

archive_root="$tmpdir/archive/source"
mkdir -p "$archive_root/wp-content/uploads" "$archive_root/wp-content/themes" "$archive_root/wp-content/plugins"
echo upload > "$archive_root/wp-content/uploads/image.txt"
cat > "$archive_root/db_export.sql" <<'SQL'
DROP TABLE IF EXISTS `wp_options`;
CREATE TABLE `wp_options` (`option_id` bigint NOT NULL);
INSERT INTO `wp_options` VALUES (1);
SQL
(cd "$tmpdir/archive" && zip -qr "$tmpdir/migration.zip" source)
# The engine moves a local backup into its private directory, so keep a
# pristine copy to seed each recoverable-replacement scenario.
cp "$tmpdir/migration.zip" "$tmpdir/migration-scenarios.zip"

destination="$tmpdir/destination"
mkdir -p "$destination/wp-content"
export RUNNER_WP_CLI_CMD="$fake_wp"
export RUNNER_PRIVATE_DIR="$tmpdir/private"
export WP_TEST_LOG="$wp_log"
mkdir -p "$RUNNER_PRIVATE_DIR"

migrate_output=$(cd "$destination" && go_migrate \
    --url="$tmpdir/migration.zip" \
    --update-urls \
    --source-home="https://source.example" \
    --source-siteurl="https://source.example/wordpress" \
    --destination-home="https://local.localhost" \
    --destination-siteurl="https://local.localhost/wordpress")

grep -q 'Migrating files...' <<<"$migrate_output" || fail "successful migration did not reach the files phase"
[ -f "$destination/wp-content/uploads/image.txt" ] || fail "normal migration did not copy uploads"
if grep -Eq '^option get (home|siteurl)' "$wp_log"; then
    fail "migrator queried home/siteurl despite explicit URL arguments"
fi
grep -Fq 'search-replace https://source.example/wordpress https://local.localhost/wordpress' "$wp_log" || fail "siteurl mapping was not preserved"
grep -Fq 'search-replace https://source.example https://local.localhost' "$wp_log" || fail "home mapping was not preserved"
grep -Fq 'option update home https://local.localhost' "$wp_log" || fail "destination home was not finalized"
grep -Fq 'option update siteurl https://local.localhost/wordpress' "$wp_log" || fail "destination siteurl was not finalized"
assert_before 'db reset' 'db import' "$wp_log"
assert_before 'db export' 'db reset' "$wp_log"
[ ! -d "$RUNNER_PRIVATE_DIR/restore_recovery" ] || fail "confirmed migration kept recovery material"

# --- Recoverable database replacement regression tests ---
# A fake WP-CLI lets each destructive step fail on demand so the engine's
# snapshot-before-reset and automatic rollback can be verified independently.
make_recover_wp() {
    cat > "$1" <<'RECOVER_WP'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WP_TEST_LOG"
case "$*" in
    "option get blog_public"*) echo 1 ;;
    "config get table_prefix"*) echo wp_ ;;
    "db export"*)
        output="${3:-}"
        [ "${RECOVER_EXPORT_FAIL:-0}" = 1 ] && exit 1
        [ -n "$output" ] && cat > "$output" <<'SQL'
CREATE TABLE `wp_options` (`option_id` bigint NOT NULL);
SQL
        ;;
    "db import"*)
        target="${3:-}"
        case "$target" in
            *pre-reset-backup.sql) [ "${RECOVER_ROLLBACK_FAIL:-0}" = 1 ] && exit 1 ;;
            *) [ "${RECOVER_IMPORT_FAIL:-0}" = 1 ] && exit 1 ;;
        esac
        ;;
    "core is-installed"*) [ "${RECOVER_VERIFY_FAIL:-0}" = 1 ] && exit 1 ;;
    "plugin is-installed"*|"plugin is-active"*) exit 1 ;;
esac
exit 0
RECOVER_WP
    chmod +x "$1"
}

recover_fake_wp="$tmpdir/recover-fake-wp"
make_recover_wp "$recover_fake_wp"

run_recoverable_migrate() (
    local scenario_dir="$tmpdir/recover-$1"
    mkdir -p "$scenario_dir/destination/wp-content" "$scenario_dir/private"
    cp "$tmpdir/migration-scenarios.zip" "$scenario_dir/migration.zip"
    export RUNNER_PRIVATE_DIR="$scenario_dir/private"
    export RUNNER_WP_CLI_CMD="$recover_fake_wp"
    export WP_TEST_LOG="$scenario_dir/wp.log"
    cd "$scenario_dir/destination" || exit 1
    go_migrate \
        --url="$scenario_dir/migration.zip" \
        --update-urls \
        --source-home="https://source.example" \
        --source-siteurl="https://source.example/wordpress" \
        --destination-home="https://local.localhost" \
        --destination-siteurl="https://local.localhost/wordpress"
)

# Failure before the reset: the snapshot itself fails, so nothing destructive
# may run and no recovery material is left behind.
scenario_dir="$tmpdir/recover-snapshot-fail"
export RECOVER_EXPORT_FAIL=1
rc=0
run_recoverable_migrate snapshot-fail >"$tmpdir/recover-snapshot-fail.out" 2>&1 || rc=$?
unset RECOVER_EXPORT_FAIL
[ "$rc" -ne 0 ] || fail "migration continued despite a failed pre-reset snapshot"
grep -q 'db export' "$scenario_dir/wp.log" || fail "engine did not attempt a pre-reset snapshot"
if grep -Eq 'db reset|db import' "$scenario_dir/wp.log"; then
    fail "a failed snapshot still reached a destructive step"
fi
[ ! -d "$scenario_dir/private/restore_recovery" ] || fail "failed snapshot left recovery material behind"

# Import failure: the engine must roll back to the pre-reset snapshot and then
# discard the recovery material once the rollback is confirmed.
scenario_dir="$tmpdir/recover-import-fail"
export RECOVER_IMPORT_FAIL=1
rc=0
run_recoverable_migrate import-fail >"$tmpdir/recover-import-fail.out" 2>&1 || rc=$?
unset RECOVER_IMPORT_FAIL
[ "$rc" -ne 0 ] || fail "migration succeeded despite a failed import"
grep -Fq 'Database import failed.' "$tmpdir/recover-import-fail.out" || fail "import failure was not reported"
grep -Fq 'pre-reset-backup.sql' "$scenario_dir/wp.log" || fail "rollback did not import the pre-reset snapshot"
grep -q 'restored to its pre-migration state' "$tmpdir/recover-import-fail.out" || fail "successful rollback was not reported"
[ ! -d "$scenario_dir/private/restore_recovery" ] || fail "confirmed rollback kept recovery material"

# Rollback failure: the snapshot and state must survive and the operator must
# be told where they are and how to recover.
scenario_dir="$tmpdir/recover-rollback-fail"
export RECOVER_IMPORT_FAIL=1 RECOVER_ROLLBACK_FAIL=1
rc=0
run_recoverable_migrate rollback-fail >"$tmpdir/recover-rollback-fail.out" 2>&1 || rc=$?
unset RECOVER_IMPORT_FAIL RECOVER_ROLLBACK_FAIL
[ "$rc" -ne 0 ] || fail "migration succeeded despite a failed import"
grep -q 'Automatic recovery failed' "$tmpdir/recover-rollback-fail.out" || fail "failed rollback was not reported"
[ -s "$scenario_dir/private/restore_recovery/pre-reset-backup.sql" ] || fail "failed rollback discarded the recovery snapshot"
[ -f "$scenario_dir/private/restore_recovery/state" ] || fail "failed rollback discarded the recovery state"
grep -q '_go migrate --recover' "$tmpdir/recover-rollback-fail.out" || fail "failed rollback did not point at the recover command"

# Verification failure after a successful import must also roll back.
scenario_dir="$tmpdir/recover-verify-fail"
export RECOVER_VERIFY_FAIL=1
rc=0
run_recoverable_migrate verify-fail >"$tmpdir/recover-verify-fail.out" 2>&1 || rc=$?
unset RECOVER_VERIFY_FAIL
[ "$rc" -ne 0 ] || fail "migration succeeded despite a failed verification"
grep -q 'could not be verified' "$tmpdir/recover-verify-fail.out" || fail "verification failure was not reported"
grep -Fq 'pre-reset-backup.sql' "$scenario_dir/wp.log" || fail "verification failure did not trigger a rollback"
[ ! -d "$scenario_dir/private/restore_recovery" ] || fail "confirmed rollback kept recovery material"

# An interrupted restore must block a new run and be recoverable explicitly.
scenario_dir="$tmpdir/recover-interrupted"
mkdir -p "$scenario_dir/destination/wp-content" "$scenario_dir/private/restore_recovery"
cp "$tmpdir/migration-scenarios.zip" "$scenario_dir/migration.zip"
printf 'CREATE TABLE `wp_options` (`option_id` bigint NOT NULL);\n' > "$scenario_dir/private/restore_recovery/pre-reset-backup.sql"
cat > "$scenario_dir/private/restore_recovery/state" <<EOF
stage=importing
recovery_dump=$scenario_dir/private/restore_recovery/pre-reset-backup.sql
table_prefix=
current_table_prefix=wp_
EOF
rc=0
(
    export RUNNER_PRIVATE_DIR="$scenario_dir/private"
    export RUNNER_WP_CLI_CMD="$recover_fake_wp"
    export WP_TEST_LOG="$scenario_dir/wp.log"
    cd "$scenario_dir/destination" || exit 1
    go_migrate --url="$scenario_dir/migration.zip"
) >"$tmpdir/recover-interrupted.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "a new migration proceeded over an interrupted restore"
grep -q 'interrupted' "$tmpdir/recover-interrupted.out" || fail "interrupted restore was not reported"
if grep -Eq 'db reset|db import|db export' "$scenario_dir/wp.log" 2>/dev/null; then
    fail "interrupted restore was not detected before destructive steps"
fi
[ -f "$scenario_dir/private/restore_recovery/state" ] || fail "interrupted restore lost its state"

rc=0
(
    export RUNNER_PRIVATE_DIR="$scenario_dir/private"
    export RUNNER_WP_CLI_CMD="$recover_fake_wp"
    export WP_TEST_LOG="$scenario_dir/recover.log"
    cd "$scenario_dir/destination" || exit 1
    go_migrate --recover
) >"$tmpdir/recover-run.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "explicit recovery failed"
grep -Fq 'pre-reset-backup.sql' "$scenario_dir/recover.log" || fail "recovery did not import the preserved snapshot"
[ ! -d "$scenario_dir/private/restore_recovery" ] || fail "successful recovery kept its material"
grep -q 'Database recovery complete' "$tmpdir/recover-run.out" || fail "successful recovery was not reported"

# Verify the backup primitive used by pull keeps uploads normally and excludes
# only that directory when --proxy-uploads translates to --exclude.
source go/commands/backup
backup_wp="$tmpdir/backup-wp"
cat > "$backup_wp" <<'BACKUP_WP'
#!/usr/bin/env bash
case "$*" in
    "option get home"*) echo https://source.example ;;
    "option get blogname"*) echo Source ;;
    "db export"*)
        output="${3}"
        cat > "$output" <<'SQL'
CREATE TABLE `wp_options` (`option_id` bigint NOT NULL);
SQL
        ;;
esac
BACKUP_WP
chmod +x "$backup_wp"
export RUNNER_WP_CLI_CMD="$backup_wp"
backup_site="$tmpdir/backup-site"
mkdir -p "$backup_site/wp-content/uploads" "$backup_site/wp-content/plugins/example"
echo upload > "$backup_site/wp-content/uploads/image.txt"
echo plugin > "$backup_site/wp-content/plugins/example/plugin.php"

proxy_archive=$(go_backup "$backup_site" --quiet --format=filename --exclude=wp-content/uploads)
if unzip -Z1 "$backup_site/$proxy_archive" | grep -q 'wp-content/uploads/'; then
    fail "proxy backup included wp-content/uploads"
fi
unzip -Z1 "$backup_site/$proxy_archive" | grep -q 'wp-content/plugins/example/plugin.php' || fail "proxy backup lost normal content"

normal_archive=$(go_backup "$backup_site" --quiet --format=filename)
unzip -Z1 "$backup_site/$normal_archive" | grep -q 'wp-content/uploads/image.txt' || fail "normal backup excluded uploads"

# Pull orchestration test. Fake SSH, curl and WP-CLI record the phase order.
# The first run fails its download; no reset/import or migration may occur.
./compile.sh >/dev/null
source ./plak.sh >/dev/null

pull_bin="$tmpdir/pull-bin"
mkdir -p "$pull_bin"
pull_events="$tmpdir/pull-events.log"
cat > "$pull_bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
command_line="${*: -1}"
case "$command_line" in
    *"option get home"*) echo REMOTE_HOME >> "$PULL_EVENTS"; echo https://remote.example ;;
    *"option get siteurl"*) echo REMOTE_SITEURL >> "$PULL_EVENTS"; echo https://remote.example/wp ;;
    *" backup "*) echo "BACKUP_GENERATED $command_line" >> "$PULL_EVENTS"; echo https://remote.example/plak-backup.zip ;;
    *"rm -f"*) echo REMOTE_CLEANUP >> "$PULL_EVENTS" ;;
    *"cat >"*) cat >/dev/null; echo UPLOAD >> "$PULL_EVENTS" ;;
    *" migrate "*) echo "PUSH_MIGRATE $command_line" >> "$PULL_EVENTS" ;;
esac
FAKE_SSH
chmod +x "$pull_bin/ssh"

cat > "$pull_bin/mysql" <<'FAKE_MYSQL'
#!/usr/bin/env bash
echo "MYSQL $*" >> "$PULL_EVENTS"
FAKE_MYSQL
chmod +x "$pull_bin/mysql"

cat > "$pull_bin/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
output=""
previous=""
for arg in "$@"; do
    if [ "$previous" = "-o" ]; then output="$arg"; fi
    previous="$arg"
done
if [ -n "$output" ]; then
    echo DOWNLOAD >> "$PULL_EVENTS"
    if [ "${PULL_DOWNLOAD_FAIL:-0}" = 1 ]; then exit 22; fi
    cp "$PULL_FIXTURE" "$output"
    exit 0
fi
cat <<'MIGRATOR'
#!/usr/bin/env bash
if [ "${1:-}" = "backup" ]; then
    cp "$PULL_FIXTURE" ./push-backup.zip
    echo push-backup.zip
else
    printf 'MIGRATE %s\n' "$*" >> "$PULL_EVENTS"
    echo "Migrating files..."
fi
MIGRATOR
FAKE_CURL
chmod +x "$pull_bin/curl"

local_wp="$tmpdir/local-wp"
cat > "$local_wp" <<'LOCAL_WP'
#!/usr/bin/env bash
case "$*" in
    "option get home"*) echo DEST_HOME >> "$PULL_EVENTS"; echo https://destination.localhost ;;
    "option get siteurl"*) echo DEST_SITEURL >> "$PULL_EVENTS"; echo https://destination.localhost/wp ;;
esac
LOCAL_WP
chmod +x "$local_wp"

site_command="$tmpdir/site-command"
cat > "$site_command" <<'SITE_COMMAND'
#!/usr/bin/env bash
if [ "$1 $2" = "directive add" ]; then
    echo PROXY_DIRECTIVE >> "$PULL_EVENTS"
    cat >> "$PULL_EVENTS"
fi
SITE_COMMAND
chmod +x "$site_command"

pull_fixture_root="$tmpdir/pull-fixture/source"
mkdir -p "$pull_fixture_root/wp-content/uploads"
echo upload > "$pull_fixture_root/wp-content/uploads/image.txt"
cat > "$pull_fixture_root/db_export.sql" <<'SQL'
CREATE TABLE `wp_options` (`option_id` bigint NOT NULL);
SQL
(cd "$tmpdir/pull-fixture" && zip -qr "$tmpdir/pull-fixture.zip" source)

run_pull() (
    export PATH="$pull_bin:$PATH"
    export PULL_EVENTS="$pull_events"
    export PULL_FIXTURE="$tmpdir/pull-fixture.zip"
    export PULL_DOWNLOAD_FAIL="${1:-0}"
    SITES_DIR="$tmpdir/sites"
    PLAK_SITE_CMD="$site_command"
    mkdir -p "$SITES_DIR/demo.localhost/public"
    touch "$SITES_DIR/demo.localhost/public/wp-config.php"
    source_config() { :; }
    plak_remote_get_binding() { echo 'production|public'; }
    get_wp_cmd() { echo "$local_wp"; }
    inject_mu_plugin() { :; }
    regenerate_caddyfile() { :; }
    gum() { :; }
    local pull_args=(demo --yes)
    [ -z "${2:-}" ] || pull_args+=("$2")
    plak_site_pull "${pull_args[@]}"
)

: > "$pull_events"
if run_pull 1 >/dev/null 2>&1; then
    fail "pull succeeded despite failed backup download"
fi
if grep -Eq 'MIGRATE|MYSQL|db reset|db import' "$pull_events"; then
    fail "failed backup reached a destructive migration phase"
fi
assert_before REMOTE_HOME BACKUP_GENERATED "$pull_events"
assert_before REMOTE_SITEURL BACKUP_GENERATED "$pull_events"
assert_before DEST_HOME BACKUP_GENERATED "$pull_events"
assert_before DEST_SITEURL BACKUP_GENERATED "$pull_events"

: > "$pull_events"
pull_output=$(run_pull 0)
grep -q 'Migrating files...' <<<"$pull_output" || fail "successful pull did not reach file migration"
grep -Fq -- '--source-home=https://remote.example' "$pull_events" || fail "pull did not pass source home"
grep -Fq -- '--source-siteurl=https://remote.example/wp' "$pull_events" || fail "pull did not pass source siteurl"
grep -Fq -- '--destination-home=https://destination.localhost' "$pull_events" || fail "pull did not pass destination home"
grep -Fq -- '--destination-siteurl=https://destination.localhost/wp' "$pull_events" || fail "pull did not pass destination siteurl"
if grep -q PROXY_DIRECTIVE "$pull_events"; then
    fail "normal pull configured an uploads proxy"
fi
if grep -Fq -- '--exclude="wp-content/uploads"' "$pull_events"; then
    fail "normal pull excluded uploads from its backup"
fi
assert_before DOWNLOAD MIGRATE "$pull_events"

: > "$pull_events"
run_pull 0 --proxy-uploads >/dev/null
grep -q PROXY_DIRECTIVE "$pull_events" || fail "proxy pull did not configure its directive"
grep -Fq 'reverse_proxy https://remote.example' "$pull_events" || fail "proxy directive did not target source home"
grep -Fq -- '--exclude="wp-content/uploads"' "$pull_events" || fail "proxy pull did not exclude uploads from its backup"

# Push did not previously reset the remote database before reading home, but it
# shares the migrator contract. Verify it captures both sides before restore and
# passes the same four explicit values symmetrically.
run_push() (
    export PATH="$pull_bin:$PATH"
    export PULL_EVENTS="$pull_events"
    export PULL_FIXTURE="$tmpdir/pull-fixture.zip"
    SITES_DIR="$tmpdir/sites"
    mkdir -p "$SITES_DIR/demo.localhost/public"
    touch "$SITES_DIR/demo.localhost/public/wp-config.php"
    plak_remote_get_binding() { echo 'production|public'; }
    get_wp_cmd() { echo "$local_wp"; }
    gum() { :; }
    plak_site_push demo --yes
)

: > "$pull_events"
run_push >/dev/null
grep -Fq -- '--source-home=https://destination.localhost' "$pull_events" || fail "push did not pass local home"
grep -Fq -- '--source-siteurl=https://destination.localhost/wp' "$pull_events" || fail "push did not pass local siteurl"
grep -Fq -- '--destination-home=https://remote.example' "$pull_events" || fail "push did not pass remote home"
grep -Fq -- '--destination-siteurl=https://remote.example/wp' "$pull_events" || fail "push did not pass remote siteurl"
assert_before REMOTE_HOME PUSH_MIGRATE "$pull_events"
assert_before REMOTE_SITEURL PUSH_MIGRATE "$pull_events"

echo "Migration regression tests passed."
