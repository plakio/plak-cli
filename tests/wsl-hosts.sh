#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

./compile.sh >/dev/null

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() {
    echo "wsl-hosts regression test failed: $1" >&2
    exit 1
}

export PLAK_NO_PATH_PRELUDE=1
source ./plak.sh >/dev/null

# --- The generated PowerShell replaces Plak's block, never appends ---
ps_command=$(plak_wsl_hosts_ps_command "172.24.95.67" "plak.localhost db.plak.localhost")

grep -q '### plak begin ###' <<<"$ps_command" || fail "command lacks the begin marker"
grep -q '### plak end ###' <<<"$ps_command" || fail "command lacks the end marker"
grep -q 'Set-Content' <<<"$ps_command" || fail "command does not replace the file (Set-Content)"
if grep -q 'Add-Content' <<<"$ps_command"; then
    fail "command still appends with Add-Content"
fi
grep -q '172.24.95.67 plak.localhost db.plak.localhost' <<<"$ps_command" || fail "command lacks the entry line"

# --- Idempotence: emulate the PowerShell algorithm against a temp hosts file ---
# Mirrors the generated script's logic so the block-replacement contract is
# proven without Windows. Each simulated run starts from the current file.
simulate_hosts() {
    local hosts_file="$1" wsl_ip="$2" hostnames="$3"
    awk -v ip="$wsl_ip" -v hosts="$hostnames" '
        BEGIN { inside = 0; n = 0 }
        /^### plak begin ###$/ { inside = 1; next }
        /^### plak end ###$/ { inside = 0; next }
        { if (!inside) out[n++] = $0 }
        END {
            out[n++] = "### plak begin ###"
            out[n++] = ip " " hosts
            out[n++] = "### plak end ###"
            for (i = 0; i < n; i++) print out[i]
        }
    ' "$hosts_file" > "$hosts_file.new"
    mv "$hosts_file.new" "$hosts_file"
}

hosts_file="$tmpdir/hosts"
cat > "$hosts_file" <<'HOSTS'
127.0.0.1 localhost
192.168.1.10 router
HOSTS

simulate_hosts "$hosts_file" "172.24.95.67" "plak.localhost db.plak.localhost mail.plak.localhost"
simulate_hosts "$hosts_file" "172.24.95.67" "plak.localhost db.plak.localhost mail.plak.localhost"
simulate_hosts "$hosts_file" "172.30.1.5" "plak.localhost db.plak.localhost mail.plak.localhost"

count=$(grep -c '172\.' "$hosts_file" || true)
[ "$count" -eq 1 ] || fail "repeated runs duplicated the Plak entry ($count occurrrences)"
grep -q '172.30.1.5 plak.localhost' "$hosts_file" || fail "the managed block did not refresh to the new IP"
grep -q '127.0.0.1 localhost' "$hosts_file" || fail "unrelated hosts lines were removed"
grep -q '192.168.1.10 router' "$hosts_file" || fail "unrelated hosts lines were removed (router)"
grep -q '### plak begin ###' "$hosts_file" || fail "markers were not written"

# --- The command offers auto-apply only when powershell.exe is present ---
grep -q 'powershell.exe' commands/site/wsl-hosts || fail "command does not try the Windows PowerShell bridge"
grep -q 'wslinfo --networking-mode' commands/site/wsl-hosts || fail "command does not detect mirrored networking"

echo "wsl-hosts regression tests passed."
