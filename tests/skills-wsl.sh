#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/linux-home" XDG_CONFIG_HOME="$tmpdir/linux-config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$tmpdir/Windows Profile" "$tmpdir/skill-source" "$tmpdir/tools"
printf '%s\n' '---' 'name: plak-cli' 'description: Plak test fixture' '---' 'Run Plak' > "$tmpdir/skill-source/SKILL.md"
PLAK_WPMCP_VERSION=v0.0.0
source "$ROOT_DIR/commands/skill"
plak_ui_error() { echo "$*" >&2; }
plak_ui_warn() { echo "$*" >&2; }
plak_ui_success() { echo "$*"; }
plak_command_exists() { command -v "$1" >/dev/null; }
plak_skill_source_dir() { echo "$tmpdir/skill-source"; }
curl() {
    local dest="${!#}"
    [ "${FAIL_DOWNLOAD:-false}" = false ] || { printf partial > "$dest"; return 22; }
    printf '%s\n' '---' 'name: wp-mcp' 'description: companion fixture' '---' > "$dest"
}
wp-mcp() { echo delegated >> "$tmpdir/delegation"; return 0; }
IS_WSL=false
[ "$(plak_skill path codex)" = "$HOME/.agents/skills/plak-cli" ]
[ "$(plak_skill path opencode)" = "$XDG_CONFIG_HOME/opencode/skills/plak-cli" ]
plak_skill install codex >/dev/null
[ -f "$HOME/.agents/skills/plak-cli/SKILL.md" ]
[ -f "$HOME/.agents/skills/wp-mcp/SKILL.md" ]
[ ! -e "$tmpdir/delegation" ]
IS_WSL=true
plak_skill install claude-code > "$tmpdir/local-output" 2> "$tmpdir/local-warning"
grep -q 'WSL-local' "$tmpdir/local-warning"
[ ! -d "$tmpdir/Windows Profile/.claude" ]
if plak_skill install codex --windows > "$tmpdir/output" 2>&1; then exit 1; fi
grep -q 'Windows profile is unavailable' "$tmpdir/output"
cat > "$tmpdir/tools/cmd.exe" <<'CMD'
#!/usr/bin/env bash
printf '%s\r\n' "${TEST_PROFILE:-C:\Users\Test User}"
CMD
cat > "$tmpdir/tools/wslpath" <<'WSLPATH'
#!/usr/bin/env bash
[ "$1" = -u ] && [ "$2" = 'C:\Users\Test User' ] || exit 1
echo "$TEST_WINDOWS_HOME"
WSLPATH
chmod +x "$tmpdir/tools/"*
export PATH="$tmpdir/tools:$PATH" TEST_WINDOWS_HOME="$tmpdir/Windows Profile"
for target in codex claude-code opencode global; do
    dest=$(plak_skill path "$target" --windows)
    [[ "$dest" = "$TEST_WINDOWS_HOME/"* ]]
    plak_skill install "$target" --windows > "$tmpdir/output"
    [ -s "$dest/SKILL.md" ]
    grep -q 'Native Windows host with Plak in WSL' "$dest/SKILL.md"
    [ -s "$(dirname "$dest")/wp-mcp/SKILL.md" ]
    cp "$dest/SKILL.md" "$tmpdir/installed"
    plak_skill install "$target" --windows >/dev/null
    cmp "$dest/SKILL.md" "$tmpdir/installed"
done
[ ! -d "$HOME/.config/opencode" ]
[ ! -e "$TEST_WINDOWS_HOME/$XDG_CONFIG_HOME" ]
# Delegation came only from the initial local Claude install.
[ "$(wc -l < "$tmpdir/delegation")" -eq 1 ]
for target in pi hermes all; do
    if plak_skill install "$target" --windows > "$tmpdir/output" 2>&1; then exit 1; fi
    grep -q 'not verified' "$tmpdir/output"
done
if TEST_PROFILE='%USERPROFILE%' plak_skill path codex --windows > "$tmpdir/output" 2>&1; then exit 1; fi
grep -q 'not an absolute' "$tmpdir/output"
if TEST_WINDOWS_HOME="$tmpdir/not-mounted" plak_skill path codex --windows > "$tmpdir/output" 2>&1; then exit 1; fi
grep -q 'not mounted' "$tmpdir/output"
plak_skill install pi --directory "$tmpdir/custom skills" >/dev/null
[ -f "$tmpdir/custom skills/plak-cli/SKILL.md" ]
[ -f "$tmpdir/custom skills/wp-mcp/SKILL.md" ]
for args in 'pi --directory relative' 'all --directory /unused' 'codex --windows --directory /unused'; do
    # Intentional word splitting: these are fixed negative parser fixtures.
    # shellcheck disable=SC2086
    if plak_skill install $args > "$tmpdir/output" 2>&1; then exit 1; fi
done
# Reject a failed remote download even when an old SKILL.md exists.
plak_skill_source_dir() { return 1; }
cp "$tmpdir/custom skills/plak-cli/SKILL.md" "$tmpdir/before-download"
if FAIL_DOWNLOAD=true plak_skill install pi --directory "$tmpdir/custom skills" > "$tmpdir/output" 2>&1; then exit 1; fi
cmp "$tmpdir/before-download" "$tmpdir/custom skills/plak-cli/SKILL.md"
grep -q 'existing SKILL.md was preserved' "$tmpdir/output"
if grep -q 'Installed Plak skill' "$tmpdir/output"; then exit 1; fi
[ -z "$(find "$tmpdir/custom skills" -name '.SKILL.*' -print)" ]
echo 'Skill paths, isolated homes, explicit Windows/custom targets and failure tests passed (simulated interop, not WSL)'
