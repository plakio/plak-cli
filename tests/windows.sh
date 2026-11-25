#!/usr/bin/env bash
# Windows onboarding regression checks: Ubuntu 24.04, no Docker, deps and docs.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"
./compile.sh >/dev/null
for f in agent-setup/cli/prompt.md agent-setup/panel/prompt.md docs/windows.md commands/status commands/site/install install.sh; do
    [ -f "$f" ] || { echo "windows test failed: missing $f" >&2; exit 1; }
done

fail() { echo "windows test failed: $1" >&2; exit 1; }

for prompt in agent-setup/cli/prompt.md agent-setup/panel/prompt.md; do
    grep -q 'Ubuntu 24.04 LTS' "$prompt" || fail "$prompt lacks Ubuntu 24.04"
    grep -q 'wsl --install -d Ubuntu-24.04 --web-download' "$prompt" || fail "$prompt lacks web-download install"
    grep -q 'Do not switch to' "$prompt" || fail "$prompt lacks distro guard"
    grep -q 'Docker is not required' "$prompt" || fail "$prompt still implies Docker"
    grep -q 'plak trust' "$prompt" || fail "$prompt lacks plak trust"
    grep -q 'plak wsl-hosts' "$prompt" || fail "$prompt lacks plak wsl-hosts"
    grep -q 'systemd' "$prompt" || fail "$prompt lacks systemd check"
done

grep -q 'Docker is \*\*not\*\*' docs/windows.md || fail "windows doc lacks Docker clarification"
grep -q 'Ubuntu 24.04' docs/windows.md || fail "windows doc lacks Ubuntu"
grep -q 'plak trust' docs/windows.md || fail "windows doc lacks trust"

grep -q 'for dep in curl python3 gum' commands/status || fail "status lacks curl/python3"
grep -q 'install_dependency "python3"' commands/site/install || fail "installer lacks python3"
grep -q 'openssh-client' commands/site/install || fail "installer lacks openssh-client"
grep -q 'umask 022' commands/site/install || fail "installer does not normalize umask"
grep -q 'static-php\*.asc' commands/site/install || fail "installer does not normalize keyring"
grep -q 'python3 ssh' install.sh || fail "installer missing-deps lacks python3/ssh"

./plak.sh status --json > /tmp/plak-windows-status.$$ || fail "status --json"
python3 - /tmp/plak-windows-status.$$ <<'PY' || fail "status dependencies"
import json, sys
d = json.load(open(sys.argv[1]))
deps = d.get("dependencies") or {}
assert deps.get("curl") in ("found", "missing"), deps
assert deps.get("python3") in ("found", "missing"), deps
PY
rm -f /tmp/plak-windows-status.$$

echo "windows tests passed"
