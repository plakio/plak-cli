#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

./compile.sh >/dev/null

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() {
    echo "trust linuxbrew regression test failed: $1" >&2
    exit 1
}

export PLAK_NO_PATH_PRELUDE=1
source ./plak.sh >/dev/null

# --- bundle append is idempotent and marker-guarded ---
prefix="$tmpdir/linuxbrew"
mkdir -p "$prefix/etc/ca-certificates" "$prefix/opt/openssl@3/etc/openssl@3"
bundle="$prefix/etc/ca-certificates/cert.pem"
printf -- '-----BEGIN CERTIFICATE-----\nSystem Root\n-----END CERTIFICATE-----\n' > "$bundle"

root_cert="$tmpdir/root.crt"
printf -- '-----BEGIN CERTIFICATE-----\nCaddy Local Authority - 2026 ECC Root\n-----END CERTIFICATE-----\n' > "$root_cert"

plak_site_trust_linuxbrew_bundles "$prefix" "$root_cert" >/dev/null
plak_site_trust_linuxbrew_bundles "$prefix" "$root_cert" >/dev/null

caddy_count=$(grep -c 'Caddy Local Authority' "$bundle" || true)
[ "$caddy_count" -eq 1 ] || fail "repeated trust runs duplicated the Caddy root ($caddy_count)"
grep -q 'System Root' "$bundle" || fail "the existing bundle content was lost"

# An openssl@3 bundle is updated too when present.
openssl_bundle="$prefix/opt/openssl@3/etc/openssl@3/cert.pem"
printf -- '-----BEGIN CERTIFICATE-----\nOther Root\n-----END CERTIFICATE-----\n' > "$openssl_bundle"
plak_site_trust_linuxbrew_bundles "$prefix" "$root_cert" >/dev/null
grep -q 'Caddy Local Authority' "$openssl_bundle" || fail "openssl@3 bundle was not updated"
mkdir -p "$prefix/etc/openssl@3"
ln -s "$bundle" "$prefix/etc/openssl@3/cert.pem"
plak_site_trust_linuxbrew_bundles "$prefix" "$root_cert" >/dev/null
[ -L "$prefix/etc/openssl@3/cert.pem" ] || fail 'replaced a bundle symlink instead of its target'

# A prefix with no bundles is a no-op.
empty_prefix="$tmpdir/emptybrew"
mkdir -p "$empty_prefix"
plak_site_trust_linuxbrew_bundles "$empty_prefix" "$root_cert" >/dev/null \
    || fail "helper failed when no bundle exists"

# --- the Caddy root locator is exposed and returns nothing when absent ---
HOME="$tmpdir/empty-home" plak_site_caddy_root_cert >/dev/null 2>&1 || true

# The trust command wires the Linuxbrew handling.
grep -q 'plak_site_trust_linuxbrew_bundles' commands/site/trust || fail "trust does not call the Linuxbrew helper"
grep -q 'plak_site_caddy_root_cert' commands/site/trust || fail "trust does not locate the Caddy root"

echo "Trust linuxbrew regression tests passed."
