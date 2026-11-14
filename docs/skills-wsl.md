# Agent skills from WSL

`plak skill install` writes skills into the home directory of the environment
where Plak runs. A native Windows agent does not read the WSL home, so in WSL
Plak also installs into the Windows user profile for the targets whose Windows
discovery paths are verified.

## Destinations

Linux/WSL paths use the current user's `$HOME`. Windows paths use
`%USERPROFILE%` (resolved with `cmd.exe` or `powershell.exe` and converted with
`wslpath`).

| Target | Linux/WSL | Windows |
| --- | --- | --- |
| `codex` | `~/.agents/skills/plak-cli` | `%USERPROFILE%\.agents\skills\plak-cli` |
| `claude-code` | `~/.claude/skills/plak-cli` | `%USERPROFILE%\.claude\skills\plak-cli` |
| `opencode` | `${XDG_CONFIG_HOME:-~/.config}/opencode/skills/plak-cli` | `%USERPROFILE%\.config\opencode\skills\plak-cli` |
| `global` | `~/.agents/skills/plak-cli` | `%USERPROFILE%\.agents\skills\plak-cli` |
| `hermes` | `~/.hermes/skills/plak-cli` | not installed automatically |
| `pi` | `~/.pi/agent/skills/plak-cli` | not installed automatically |

The `wp-mcp` companion skill is installed beside the Plak skill for the same
targets. A Windows/custom destination is downloaded directly; it never
delegates to a WSL `wp-mcp` process.

## Opting out and overrides

```bash
# WSL-only installation
plak skill install --no-windows opencode

# Or for every invocation in the current shell
export PLAK_SKILL_NO_WINDOWS=1
```

`PLAK_WINDOWS_HOME` can point at a mounted Windows profile explicitly. It is
mainly useful for tests or unusual WSL layouts:

```bash
PLAK_WINDOWS_HOME=/mnt/c/Users/me plak skill install opencode
```

If Windows is not reachable, `plak skill install` still installs in the local
home and prints a warning. It does not fail the local installation.

## Discovery and execution limits

The Windows copy of `SKILL.md` includes a note explaining that Plak itself runs
inside WSL. A native Windows agent should invoke it through WSL, for example:

```powershell
wsl.exe -d <distribution> -- bash -lc 'plak status'
```

This copies instructions; it does not install a native Windows Plak binary,
register a cross-environment MCP server, or transfer credentials. Hermes and Pi
are installed only in WSL because their Windows discovery paths are not
verified. Configure the agent's own skill path if it uses a custom location.

Installation is idempotent: rerunning replaces the files and keeps exactly one
copy of the appended Windows section.
