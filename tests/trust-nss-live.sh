#!/usr/bin/env bash
set -euo pipefail
command -v openssl >/dev/null || { echo 'live NSS test skipped: openssl missing'; exit 0; }
if [ -n "${PLAK_TEST_CERTUTIL:-}" ]; then
    certutil() { "$PLAK_TEST_CERTUTIL" "$@"; }
fi
command -v certutil >/dev/null || { echo 'live NSS test skipped: certutil missing'; exit 0; }
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
tmpdir=$(mktemp -d)
trap 'chmod -R u+w "$tmpdir"; rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home"
mkdir -p "$HOME"
source ./plak.sh >/dev/null
for kind in old current unrelated; do
    openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=Plak test $kind" -keyout "$tmpdir/$kind.key" -out "$tmpdir/$kind.crt" > /dev/null 2>&1
done
profiles=('.pki/nssdb' '.local/share/pki/nssdb' '.mozilla/firefox/demo' 'snap/firefox/common/.mozilla/firefox/demo' 'snap/chromium/common/.pki/nssdb' '.var/app/org.mozilla.firefox/.mozilla/firefox/demo' '.var/app/org.chromium.Chromium/.pki/nssdb')
for profile in "${profiles[@]}"; do
    mkdir -p "$HOME/$profile"
    certutil -N -d "sql:$HOME/$profile" --empty-password
    certutil -A -d "sql:$HOME/$profile" -n 'Caddy Local Authority' -t 'C,,' -i "$tmpdir/old.crt"
    certutil -A -d "sql:$HOME/$profile" -n 'Unrelated Root' -t 'C,,' -i "$tmpdir/unrelated.crt"
done
for _ in 1 2; do plak_site_trust_nss "$tmpdir/current.crt" > /dev/null; done
expected=$(openssl x509 -in "$tmpdir/current.crt" -noout -fingerprint -sha256)
for profile in "${profiles[@]}"; do
    certutil -L -d "sql:$HOME/$profile" -n 'Unrelated Root' > /dev/null
    if certutil -L -d "sql:$HOME/$profile" -n 'Caddy Local Authority' > /dev/null 2>&1; then exit 1; fi
    certutil -L -d "sql:$HOME/$profile" -n 'Plak Local Authority' -a > "$tmpdir/export.crt"
    [ "$(openssl x509 -in "$tmpdir/export.crt" -noout -fingerprint -sha256)" = "$expected" ]
    [ "$(certutil -L -d "sql:$HOME/$profile" | grep -c 'Plak Local Authority')" = 1 ]
done
prefix="$tmpdir/brew"
mkdir -p "$prefix/etc/ca-certificates"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj '/CN=Caddy Local Authority - old root' -keyout "$tmpdir/caddy.key" -out "$tmpdir/caddy.crt" > /dev/null 2>&1
cat "$tmpdir/unrelated.crt" "$tmpdir/caddy.crt" "$tmpdir/caddy.crt" > "$prefix/etc/ca-certificates/cert.pem"
for _ in 1 2; do plak_site_trust_linuxbrew_bundles "$prefix" "$tmpdir/current.crt" >/dev/null; done
bundle="$prefix/etc/ca-certificates/cert.pem"
[ "$(grep -c 'BEGIN CERTIFICATE' "$bundle")" = 2 ]
openssl crl2pkcs7 -nocrl -certfile "$bundle" | openssl pkcs7 -print_certs -noout > "$tmpdir/subjects"
grep -q 'Plak test unrelated' "$tmpdir/subjects"
grep -q 'Plak test current' "$tmpdir/subjects"
! grep -q 'Caddy Local Authority' "$tmpdir/subjects"
plak_site_trust_linuxbrew_bundles "$prefix" "$tmpdir/old.crt" >/dev/null
[ "$(grep -c 'BEGIN CERTIFICATE' "$bundle")" = 2 ]
if [ "$(id -u)" -ne 0 ]; then
    chmod -R a-w "$HOME/.mozilla/firefox/demo"
    if plak_site_trust_nss "$tmpdir/old.crt" > /dev/null 2> "$tmpdir/errors"; then exit 1; fi
    grep -q 'not updated\|Could not remove' "$tmpdir/errors"
fi
echo 'Real NSS profile CA rotation/idempotence/failure tests passed'
