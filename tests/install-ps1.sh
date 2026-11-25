#!/usr/bin/env bash
# Static contract checks for the Windows install.ps1 bootstrapper.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
for f in install.ps1 agent-setup/README.md docs/windows.md; do
    [ -f "$f" ] || { echo "install-ps1 test failed: missing $f" >&2; exit 1; }
done
fail() { echo "install-ps1 test failed: $1" >&2; exit 1; }

grep -q 'Ubuntu-24.04' install.ps1 || fail "missing Ubuntu 24.04"
grep -q -- '--web-download' install.ps1 || fail "missing web-download install"
grep -q 'VirtualMachinePlatform' install.ps1 || fail "missing VirtualMachinePlatform"
grep -q 'Enable-WindowsOptionalFeature' install.ps1 || fail "missing feature enable"
grep -q 'Verb RunAs' install.ps1 || fail "missing UAC elevation"
grep -q 'systemd=true' install.ps1 || fail "missing systemd setup"
grep -q 'PLAK_YES=1 bash' install.ps1 || fail "missing Linux installer handoff"
grep -q 'plak trust' install.ps1 || fail "missing trust hint"
grep -q 'plak wsl-hosts' install.ps1 || fail "missing wsl-hosts hint"
grep -q 'Docker was not installed' install.ps1 || fail "missing Docker clarification"
if grep -q -- 'wsl.exe --install -d Debian' install.ps1; then fail "bootstrapper installs Debian"; fi
if grep -q 'Docker Desktop' install.ps1; then fail "bootstrapper mentions installing Docker Desktop"; fi
grep -q 'install.ps1' agent-setup/README.md || fail "redirect documentation missing"
grep -q 'plak.sh/install.ps1' docs/windows.md || fail "Windows docs missing one-liner"

if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -Command '$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "install.ps1").Path, [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Error ("line " + $_.Extent.StartLineNumber + ": " + $_.Message) }; exit 1 }' \
        || fail "PowerShell parser rejected install.ps1"
fi

echo "install-ps1 tests passed"
