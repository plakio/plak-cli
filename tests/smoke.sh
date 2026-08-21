#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

./compile.sh >/dev/null
bash -n main shared/* commands/* compile.sh install.sh plak.sh

version_output=$(./plak.sh version)
grep -q 'plak v' <<<"$version_output"

status_output=$(./plak.sh status)
grep -q 'Dependencies:' <<<"$status_output"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

hosts_file="$tmpdir/hosts"
cat > "$hosts_file" <<'HOSTS'
127.0.0.1 localhost
192.168.1.10 app.localhost old.localhost # dev entries
HOSTS

hosts_output=$(PLAK_HOSTS_FILE="$hosts_file" bash -c 'source ./plak.sh >/dev/null; plak_hosts_add_entry 127.0.0.1 new.localhost; plak_hosts_remove_entry app.localhost; plak_hosts_entries')
grep -q 'new.localhost' <<<"$hosts_output"

if grep -q 'app.localhost' "$hosts_file"; then
    echo "hosts removal failed" >&2
    exit 1
fi

test_home="$tmpdir/home"
mkdir -p "$test_home/.ssh"
ssh-keygen -t ed25519 -f "$test_home/.ssh/test_key" -N '' -q
key_output=$(HOME="$test_home" ./plak.sh sshkey list)
grep -q 'test_key' <<<"$key_output"

# Exercise HTTPS URL migration without a real WordPress database.
source ./plak.sh >/dev/null
migration_sites="$tmpdir/sites"
migration_log="$tmpdir/wp.log"
fake_wp="$tmpdir/wp"
mkdir -p "$migration_sites/site.localhost/public" "$migration_sites/plain.localhost/public"
touch "$migration_sites/site.localhost/public/wp-config.php"

cat > "$fake_wp" <<'FAKE_WP'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WP_TEST_LOG"
if [[ "$*" == *fail.localhost* ]]; then
    echo "Fatal error: simulated MU-plugin collision" >&2
    exit 1
fi
echo 3
FAKE_WP
chmod +x "$fake_wp"

SITES_DIR="$migration_sites"
WP_TEST_LOG="$migration_log"
export WP_TEST_LOG
get_wp_cmd() {
    echo "$fake_wp"
}
gum() {
    shift
    echo "$*"
}

migration_output=$(update_wp_site_urls_for_port_change 8453 443)
grep -q 'https://site.localhost:8453 https://site.localhost ' "$migration_log"
grep -q 'site.localhost: replaced 3 occurrence(s)' <<<"$migration_output"
if grep -q 'plain.localhost' "$migration_log"; then
    echo "plain site was unexpectedly migrated" >&2
    exit 1
fi

: > "$migration_log"
dry_run_output=$(update_wp_site_urls_for_port_change 443 8453 --dry-run)
grep -q 'https://site.localhost https://site.localhost:8453 ' "$migration_log"
grep -q -- '--dry-run' "$migration_log"
grep -q 'would replace 3 occurrence(s)' <<<"$dry_run_output"

echo 'fail.localhost' > "$migration_sites/site.localhost/mappings"
if update_wp_site_urls_for_port_change 8453 443 >"$tmpdir/migration.out" 2>"$tmpdir/migration.err"; then
    echo "migration failure was not propagated" >&2
    exit 1
fi
grep -q 'Fatal error: simulated MU-plugin collision' "$tmpdir/migration.err"

grep -q "function plak_cli_maybe_override_site_url" plak.sh
if grep -q 'maxdepth 2.*wp-config.php' commands/site/install; then
    echo "install still uses the shallow WordPress site check" >&2
    exit 1
fi

echo "Smoke tests passed."
