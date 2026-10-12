# Agent skills: Linux, WSL and native Windows

`plak skill install <target>` copies instructions to the **current user's**
environment, not a central agent registry. Installing in WSL does not install
anything in a Windows agent's home. A Windows editor can also host an agent
inside WSL; check where the agent process/server actually runs, not just where
its window appears.

Inspect the destination without writing:

```sh
plak skill path claude-code
plak skill path opencode
plak skill path codex
```

Default skill roots (each contains `plak-cli/SKILL.md`):

| Target | Current user's root |
| --- | --- |
| codex / global | `~/.agents/skills` |
| claude-code | `~/.claude/skills` |
| opencode | `${XDG_CONFIG_HOME:-~/.config}/opencode/skills` |
| hermes | `~/.hermes/skills` (existing Plak target) |
| pi | `~/.pi/agent/skills` (existing Plak target) |

Codex now documents `.agents/skills` for user discovery, rather than Plak's old
`.codex/skills` destination. Existing old copies are not deleted. OpenCode V2
documents `~/.config/opencode/skills` and `.agents`/`.claude` compatibility
roots, **not an assumed AppData skill directory**. Custom agent configurations
can change discovery; copying a file does not guarantee automatic invocation.

## Explicit Windows copies from WSL

For native Windows Codex, Claude Code or OpenCode using their documented
home-relative discovery paths:

```sh
plak skill path claude-code --windows
plak skill install claude-code --windows
plak skill install codex --windows
plak skill install opencode --windows
plak skill install global --windows
```

This is opt-in and Windows-only; run the normal install separately if you want
both environments. Plak reads `%USERPROFILE%` with `cmd.exe /d /c`, converts it
with `wslpath`, checks the mounted profile, and reports the exact destination.
It does not inherit WSL's XDG settings or delegate companion installation to a
WSL `wp-mcp` process. The wp-mcp companion is downloaded to the selected root.
Missing interop/mounts cause an actionable failure, not a claim of Windows
installation. No sudo, profile guessing, registry edits or symlinks into WSL
are used.

Automatic `--windows` mappings for Hermes/Pi, and consequently `all`, are
deliberately rejected: this change has not verified their native Windows
discovery. For custom paths, disabled interop, non-default Windows agent homes
or another verified agent skills root, select exactly one target explicitly:

```sh
plak skill path opencode --directory '/mnt/c/Users/My Name/custom-skills'
plak skill install opencode --directory '/mnt/c/Users/My Name/custom-skills'
```

`--directory` is the exact skills **root**, not the skill folder or filename.
It works outside WSL too. Confirm your agent is configured to scan that root;
Plak does not modify agent configuration. This option does not infer whether a
custom directory belongs to Windows.

Restart/reload the agent and inspect its skill list. On Windows, Plak still
runs inside WSL: choose the correct distro with `wsl.exe --list --quiet`, then
verify `wsl.exe -d <distro> -- bash -lc 'command -v plak; plak version'`.
The Windows Plak skill copy includes this execution boundary. Installing skill
instructions does not register MCP across Windows/WSL, copy credentials, or
install a native Windows Plak runtime.

## Evidence and limitations

Reference discovery docs checked 2026-10-12:
- [Codex](https://developers.openai.com/codex/build-skills#where-codex-loads-local-skills)
- [Claude Code](https://code.claude.com/docs/en/skills#where-skills-live)
- [OpenCode V2](https://opencode.ai/v2/docs/skills#discovery)

Automated tests simulate separate homes, Windows interop output/CRLF, spaces,
missing tools, bad profiles, repeat installs and failed downloads on Linux.
They do **not** validate actual WSL2 interop, Windows ACLs or native agent
discovery. Those require manual acceptance for the agent/version in use.
