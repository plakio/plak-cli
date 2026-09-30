#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home"
mkdir -p "$HOME"
source ./plak.sh >/dev/null
source shared/ui
export NSS_LOG="$tmpdir/nss.log"
for profile in '.pki/nssdb' '.local/share/pki/nssdb' '.mozilla/firefox/demo' 'snap/firefox/common/.mozilla/firefox/demo' 'snap/chromium/common/.pki/nssdb' '.var/app/org.mozilla.firefox/.mozilla/firefox/demo' '.var/app/org.chromium.Chromium/.pki/nssdb'; do
    mkdir -p "$HOME/$profile"; touch "$HOME/$profile/cert9.db"
done
mkdir -p "$HOME/.mozilla/firefox/legacy"
touch "$HOME/.mozilla/firefox/legacy/cert8.db"
certutil() {
    echo "$*" >> "$NSS_LOG"
    case "$1" in
        -L) return 0 ;;
        -A) [[ "${FAIL_NSS:-}" != "$3" ]] || return 1 ;;
    esac
}
echo cert > "$tmpdir/root"
plak_site_trust_nss "$tmpdir/root" > /dev/null
[ "$(grep -c '^-A' "$NSS_LOG")" = 8 ]
[ "$(grep -c '^-D' "$NSS_LOG")" = 16 ]
grep -q "dbm:$HOME/.mozilla/firefox/legacy" "$NSS_LOG"
export FAIL_NSS="sql:$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox/demo"
if plak_site_trust_nss "$tmpdir/root" > /dev/null 2> "$tmpdir/errors"; then exit 1; fi
grep -q 'profile not updated' "$tmpdir/errors"
is_caddy_running() { return 1; }
if plak_site_trust > /dev/null 2> "$tmpdir/errors"; then exit 1; fi
grep -q unavailable "$tmpdir/errors"
is_caddy_running() { return 0; }
printf '#!/usr/bin/env bash\nexit 7\n' > "$tmpdir/frank"
chmod +x "$tmpdir/frank"
CADDY_CMD="$tmpdir/frank"; SUDO_CMD=""
if plak_site_trust > /dev/null 2> "$tmpdir/errors"; then exit 1; fi
grep -q 'System trust installation failed' "$tmpdir/errors"
echo 'NSS trust tests passed'
