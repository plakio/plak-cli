#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

./compile.sh >/dev/null

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fail() {
    echo "skills-wsl regression test failed: $1" >&2
    exit 1
}

export HOME="$tmpdir/linux home"
export PLAK_WINDOWS_HOME="$tmpdir/windows home"
mkdir -p "$HOME" "$PLAK_WINDOWS_HOME" "$tmpdir/bin"

# Hermetic: no real wp-mcp, and curl is faked so companion downloads stay local.
export PATH="$tmpdir/bin:/usr/bin:/bin"
export PLAK_NO_PATH_PRELUDE=1
curl() {
    local out=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -o)
                out="$2"
                shift 2
                ;;
            *) shift ;;
        esac
    done
    [ -n "$out" ] || return 1
    printf 'wp-mcp skill\n' > "$out"
}

source ./plak.sh >/dev/null
IS_WSL=true

plak_skill_install opencode > "$tmpdir/opencode.out"
[ -f "$HOME/.config/opencode/skills/plak-cli/SKILL.md" ] ||
    fail 'Linux opencode skill was not installed'
[ -f "$PLAK_WINDOWS_HOME/.config/opencode/skills/plak-cli/SKILL.md" ] ||
    fail 'Windows opencode skill was not installed'
grep -q '^## Native Windows host with Plak in WSL$' \
    "$PLAK_WINDOWS_HOME/.config/opencode/skills/plak-cli/SKILL.md" ||
    fail 'Windows skill lacks the WSL execution note'
[ -f "$PLAK_WINDOWS_HOME/.config/opencode/skills/wp-mcp/SKILL.md" ] ||
    fail 'Windows wp-mcp companion skill was not installed'
grep -q '^## Native Windows host with Plak in WSL$' \
    "$PLAK_WINDOWS_HOME/.config/opencode/skills/wp-mcp/SKILL.md" ||
    fail 'Windows wp-mcp companion lacks the WSL execution note'

# Idempotent: re-running must not duplicate the appended Windows section.
plak_skill_install opencode >/dev/null
[ "$(grep -c '^## Native Windows host with Plak in WSL$' \
    "$PLAK_WINDOWS_HOME/.config/opencode/skills/plak-cli/SKILL.md")" = 1 ] ||
    fail 'Windows skill note was duplicated on reinstall'

# --no-windows keeps the install local even in WSL.
plak_skill_install --no-windows claude-code >/dev/null
[ -f "$HOME/.claude/skills/plak-cli/SKILL.md" ] ||
    fail 'Linux claude-code skill was not installed'
[ ! -e "$PLAK_WINDOWS_HOME/.claude/skills/plak-cli/SKILL.md" ] ||
    fail '--no-windows wrote the claude-code skill to Windows'

# Current Codex discovery root is ~/.agents/skills, in both environments.
plak_skill_install codex >/dev/null
[ -f "$HOME/.agents/skills/plak-cli/SKILL.md" ] ||
    fail 'Linux codex skill was not installed under .agents/skills'
[ -f "$PLAK_WINDOWS_HOME/.agents/skills/plak-cli/SKILL.md" ] ||
    fail 'Windows codex skill was not installed under .agents/skills'
[ -f "$PLAK_WINDOWS_HOME/.agents/skills/wp-mcp/SKILL.md" ] ||
    fail 'Windows codex wp-mcp companion was not installed under .agents/skills'

# Hermes has no verified Windows discovery path: install locally and warn.
plak_skill_install hermes > "$tmpdir/hermes.out"
[ -f "$HOME/.hermes/skills/plak-cli/SKILL.md" ] ||
    fail 'Linux hermes skill was not installed'
[ ! -e "$PLAK_WINDOWS_HOME/.hermes/skills/plak-cli/SKILL.md" ] ||
    fail 'hermes was written to an unverified Windows path'
grep -q 'not verified for hermes' "$tmpdir/hermes.out" ||
    fail 'hermes Windows skip was not reported'

# Detect USERPROFILE with cmd.exe/wslpath, including CRLF and spaces.
mkdir -p "$tmpdir/detect-bin"
cat > "$tmpdir/detect-bin/cmd.exe" <<'CMD'
#!/usr/bin/env bash
printf 'CMD.EXE was started with a UNC path.\r\nC:\\Users\\Test User   \r\n'
CMD
cat > "$tmpdir/detect-bin/wslpath" <<WSLPATH
#!/usr/bin/env bash
case "\$1" in
    -u) printf '%s\\n' '$PLAK_WINDOWS_HOME' ;;
    *) printf '%s\\n' 'C:\\Users\\Test User' ;;
esac
WSLPATH
chmod +x "$tmpdir/detect-bin/cmd.exe" "$tmpdir/detect-bin/wslpath"
unset PLAK_WINDOWS_HOME
PATH="$tmpdir/detect-bin:/usr/bin:/bin"
detected=$(plak_skill_windows_home)
[ "$detected" = "$tmpdir/windows home" ] ||
    fail "Windows profile detection returned '$detected'"

# No interop: install Linux only, and say so clearly.
IS_WSL=true
PATH="/usr/bin:/bin"
plak_skill_install opencode > "$tmpdir/no-windows.out" 2>&1
[ -f "$HOME/.config/opencode/skills/plak-cli/SKILL.md" ] ||
    fail 'Linux install stopped when Windows was unreachable'
grep -q 'Windows user profile is not reachable' "$tmpdir/no-windows.out" ||
    fail 'unreachable Windows profile was not reported'

echo 'WSL skill tests passed.'
