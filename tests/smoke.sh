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

domain_output=$(PLAK_HOSTS_FILE="$hosts_file" bash -c 'source ./plak.sh >/dev/null; plak_domain_add_entry 127.0.0.1 new.localhost; plak_domain_remove_entry app.localhost; plak_domain_entries')
grep -q 'new.localhost' <<<"$domain_output"

if grep -q 'app.localhost' "$hosts_file"; then
    echo "domain removal failed" >&2
    exit 1
fi

test_home="$tmpdir/home"
mkdir -p "$test_home/.ssh"
ssh-keygen -t ed25519 -f "$test_home/.ssh/test_key" -N '' -q
key_output=$(HOME="$test_home" ./plak.sh sshkey list)
grep -q 'test_key' <<<"$key_output"

echo "Smoke tests passed."
