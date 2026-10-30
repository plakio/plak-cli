#!/usr/bin/env bash
# No native Windows store, hosts file or system packages are modified.
# shellcheck disable=SC1091,SC2034,SC2329 # Sourced runtime consumes globals and test functions.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
source "$ROOT_DIR/commands/site/trust"
export HOME="$tmpdir/home" XDG_DATA_HOME="$tmpdir/data"
mkdir -p "$XDG_DATA_HOME/caddy/pki/authorities/local"
root="$XDG_DATA_HOME/caddy/pki/authorities/local/root.crt"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=Isolated Plak Test CA' -addext 'basicConstraints=critical,CA:TRUE' -keyout "$tmpdir/key" -out "$root" >/dev/null 2>&1
IS_WSL=true
powershell.exe() { printf '%s\n' "$@" >> "$tmpdir/interop"; return "${TEST_PS_RC:-0}"; }
plak_site_trust --windows > "$tmpdir/preview"
grep -qi 'sha256 Fingerprint' "$tmpdir/preview"
[ ! -e "$tmpdir/interop" ]
plak_site_trust --windows --yes > "$tmpdir/result"
grep -q "X509Store('Root','CurrentUser')" "$tmpdir/interop"
grep -q 'FindByThumbprint' "$tmpdir/interop"
grep -q 'FromBase64String' "$tmpdir/interop"
if TEST_PS_RC=1 plak_site_trust --windows --yes > /dev/null 2>&1; then exit 1; fi
if IS_WSL=false plak_site_trust --windows > /dev/null 2>&1; then exit 1; fi
cat "$tmpdir/key" >> "$root"
if plak_site_trust --windows --yes > /dev/null 2>&1; then exit 1; fi
printf 'invalid certificate\n' > "$root"
if plak_site_trust --windows --yes > /dev/null 2>&1; then exit 1; fi
source "$ROOT_DIR/shared/site/runtime"
SITES_DIR="$tmpdir/sites"
getent() { printf '127.0.0.1 STREAM %s\n' "$2"; }
sudo() { echo forbidden >> "$tmpdir/sudo"; return 1; }
IS_WSL=true
update_etc_hosts > /dev/null
[ ! -e "$tmpdir/sudo" ]
getent() { return 2; }
if update_etc_hosts > "$tmpdir/hosts-out" 2> "$tmpdir/hosts-error"; then exit 1; fi
grep -q 'update failed' "$tmpdir/hosts-error"
if grep -q 'Done' "$tmpdir/hosts-out"; then exit 1; fi
echo 'Windows trust authorization/interop/certificate and WSL hosts regressions passed'
