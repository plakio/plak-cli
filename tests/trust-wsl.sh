#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

./compile.sh >/dev/null

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

export HOME="$tmpdir/home"
mkdir -p "$HOME" "$tmpdir/bin-certutil" "$tmpdir/bin-powershell"
echo cert > "$tmpdir/root.crt"

cat > "$tmpdir/bin-certutil/wslpath" <<'WSLPATH'
#!/usr/bin/env bash
printf '%s\n' 'C:\Users\Test\plak-root.crt'
WSLPATH
cat > "$tmpdir/bin-certutil/certutil.exe" <<'CERTUTIL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CERTUTIL_LOG"
exit 0
CERTUTIL
chmod +x "$tmpdir/bin-certutil/wslpath" "$tmpdir/bin-certutil/certutil.exe"

source ./plak.sh >/dev/null

export CERTUTIL_LOG="$tmpdir/certutil.log"
PATH="$tmpdir/bin-certutil:$PATH"
plak_site_trust_wsl "$tmpdir/root.crt" > "$tmpdir/certutil.out"
grep -Fq -- '-user -addstore -f Root C:\Users\Test\plak-root.crt' "$CERTUTIL_LOG" ||
    { echo 'trust-wsl test failed: certutil did not receive the Windows path' >&2; exit 1; }
grep -q 'Trusted for the current Windows user' "$tmpdir/certutil.out" ||
    { echo 'trust-wsl test failed: certutil success was not reported' >&2; exit 1; }

cat > "$tmpdir/bin-powershell/wslpath" <<'WSLPATH'
#!/usr/bin/env bash
printf '%s\n' 'C:\Users\Test\plak-root.crt'
WSLPATH
cat > "$tmpdir/bin-powershell/powershell.exe" <<'POWERSHELL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$POWERSHELL_LOG"
exit 0
POWERSHELL
chmod +x "$tmpdir/bin-powershell/wslpath" "$tmpdir/bin-powershell/powershell.exe"

export POWERSHELL_LOG="$tmpdir/powershell.log"
PATH="$tmpdir/bin-powershell:/usr/bin:/bin"
plak_site_trust_wsl "$tmpdir/root.crt" > "$tmpdir/powershell.out"
grep -Fq 'Cert:\CurrentUser\Root' "$POWERSHELL_LOG" ||
    { echo 'trust-wsl test failed: PowerShell fallback did not target CurrentUser Root' >&2; exit 1; }
grep -Fq 'Import-Certificate' "$POWERSHELL_LOG" ||
    { echo 'trust-wsl test failed: PowerShell fallback did not import the certificate' >&2; exit 1; }
grep -q 'Trusted for the current Windows user' "$tmpdir/powershell.out" ||
    { echo 'trust-wsl test failed: PowerShell success was not reported' >&2; exit 1; }

# WSL integration: plak_site_trust must call the Windows importer only in WSL.
is_caddy_running() { return 0; }
plak_site_trust_nss() { return 0; }
plak_site_caddy_root_cert() { printf '%s\n' "$tmpdir/root.crt"; }
certutil() { return 0; }
CADDY_CMD=true
SUDO_CMD=""
trust_log="$tmpdir/wsl-called.log"
plak_site_trust_wsl() { printf 'called\n' >> "$trust_log"; return 0; }
PATH="$tmpdir/bin-certutil:/usr/bin:/bin"

IS_WSL=true
OS=linux
plak_site_trust >/dev/null
grep -q '^called$' "$trust_log" ||
    { echo 'trust-wsl test failed: plak trust did not call the WSL importer' >&2; exit 1; }

: > "$trust_log"
IS_WSL=false
plak_site_trust >/dev/null
[ ! -s "$trust_log" ] ||
    { echo 'trust-wsl test failed: plak trust called the WSL importer outside WSL' >&2; exit 1; }

echo 'WSL trust tests passed.'
