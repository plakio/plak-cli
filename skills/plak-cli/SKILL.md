---
name: plak-cli
description: "Use when working with Plak CLI: managing local WordPress/plain sites, the https://plak.localhost dashboard, Plak install/status/service workflows, database backups, pull/push migrations, /etc/hosts entries, SSH remotes with site bindings, SSH keys, or Plak release/Homebrew maintenance."
---

# Plak CLI

Use Plak for local developer workflows around:

- Local WordPress and plain static sites served by FrankenPHP/Caddy.
- The Plak dashboard at `https://plak.localhost`.
- Adminer at `https://db.plak.localhost` and Mailpit at `https://mail.plak.localhost`.
- SSH remotes (with optional site bindings for push/pull), `/etc/hosts` entries, and SSH keys.
- Plak CLI development, tests, releases, and Homebrew tap maintenance.

## Key Rules

- Keep existing `remote`, `hosts`, and `sshkey` behavior intact when changing site features.
- Do not edit the Homebrew formula manually before a release artifact exists.
- CLI releases are the source of truth; the Homebrew tap only references released artifacts.
- Plak uses FrankenPHP as the Caddy server. Do not install or require a separate `caddy` binary unless the user explicitly asks.
- Plak site state lives under `~/Plak`; sites live under `~/Plak/Sites`.
- The compiled distributable is `plak.sh`; source files are `main`, `shared/`, and `commands/`.

## Installation

If Plak CLI is not installed, use:

```bash
# Via curl (macOS/Linux)
curl -fsSL https://plak.sh/install | bash

# Via Homebrew (macOS)
brew install plakio/tap/plak-cli
```

Install this skill for supported agents:

```bash
plak skill install [codex|claude-code|opencode|hermes|pi|global|all]
```

Hermes installs to `~/.hermes/skills/plak-cli/SKILL.md`.

## Agent-friendly interface

The CLI is designed for non-interactive use by AI agents. No TTY is required when all values are passed via flags or positional args.

**Global flags** (can appear before the command or after the action):

- `--quiet` / `-q` — suppress success messages on STDOUT. Errors still go to STDERR.
- `--json` — force JSON output for commands that support it.
- `--help` / `-h` — show help. Must come after the command name.

**Error handling**:

- Exit codes: `0` = success, `1` = usage/config error, `2` = not found, `3` = binding/integrity error.
- Errors go to STDERR; data goes to STDOUT. Use `data=$(plak ... 2>/dev/null)` to capture only data.
- When a TTY is unavailable AND a confirmation prompt is needed, the command exits with a clear error telling you which flag to pass (`--yes`, `--force`, etc.) — it does **not** auto-confirm.

**External dependencies** that must be in `PATH` (verify with `plak --json status`):

- `gum`, `frankenphp`, `mariadb`/`mysql`, `ssh`, `ssh-keygen` — for core workflows.
- `cloudflared` — only for `plak share`; pass `--no-install` to fail fast if missing.
- `tailscale` — only for `plak tailscale`; auto-detected when present.
- `sudo` (or root) — required for `/etc/hosts` writes and service start/stop on Linux.

## Common Commands

```bash
plak --json status         # inspect dependencies and services
plak --json version        # {name, version}
plak install --yes         # non-interactive install (auto-accept defaults)
plak enable
plak disable
plak reload
plak --quiet version       # suppress output for scripts
```

## Sites

```bash
plak add <name> [--plain] [--no-reload]
plak delete <name> [--force|--yes] [--no-reload]
plak rename <old-name> <new-name>
plak list [--totals] [--json]
plak login <site> [<user>] [--raw]    # --raw prints only the URL
plak path <site>
plak url <site>
plak log [site] [-f]
```

## Databases and migration

```bash
plak db backup
plak db list [--json]
plak pull [<site>] [--yes] [--proxy-uploads]
plak push [<site>] [--yes]
```

`plak push <site>` and `plak pull <site>` skip their interactive path prompt when the site has a remote binding (see **Remotes** below). Use `<site>` to skip the site picker and `--yes` to skip the overwrite confirmation.

## Network and config

```bash
plak ports [--http PORT] [--https PORT] [--skip-urls] [--dry-run] [--yes]
plak memory [set <value>] [--yes]
plak directive <add|update|delete|list> [site]
plak directive list [--json]
plak mappings <site> [add|remove|list] [domain] [--json]
plak proxy <add|list|delete>
plak share [<site>] [--print-url] [--no-install]   # --print-url kills the tunnel after printing
plak lan <enable|disable|status|trust> [site]
plak tailscale <enable|disable|status>
```

`plak tailscale enable` auto-detects the machine hostname via `tailscale status --json` before prompting. If detection fails and there is no TTY, the command errors with a clear message to pass the hostname explicitly.

## Remotes, hosts, and SSH keys

```bash
# Remotes (SSH hosts with optional WordPress path)
plak remote add <name> --host <host> --user <user> [--port <port>] [--path <path>] [--identity <file>|--no-identity]
plak remote edit <name> [--newname N] [--host H] [--user U] [--port P] [--path PATH] [--identity F|--no-identity]
plak remote delete <name> [--yes]
plak remote list [--managed] [--unmanaged] [--json]
plak remote connect [<name>]                  # ssh -t, cd into remote_path if set
plak remote attach <remote> <site> [--yes]    # bind remote to a Plak site
plak remote detach <site> [--yes]

# Hosts (/etc/hosts entries)
plak hosts add <ip> <domain>                  # positional, no TTY needed
plak hosts list
plak hosts delete <domain> [--yes]

# SSH keys
plak sshkey create <name> [--type ed25519|rsa|ecdsa] [--bits N] [--passphrase P] [--yes]
plak sshkey delete <name> [--yes]
plak sshkey list
plak sshkey view [<name>]
```

**Remote → site bindings**: `plak remote attach <remote> <site>` writes the remote name to `~/Plak/Sites/<site>.localhost/.remote`. The `remote_path` (WordPress root) is stored in `~/.ssh/config` inside the `Host` block as `# plak-remote-path: <path>`. With a binding, `plak push <site>` and `plak pull <site>` resolve the remote automatically without prompting.

## Typical agent workflow

```bash
# Setup
plak remote add prod --host 1.2.3.4 --user ubuntu --port 22 --path public/
plak remote attach prod mysite
plak --quiet push mysite

# Inspect
plak --json status | jq '.dependencies'
plak --json list | jq '.[].name'
plak --json remote list --managed | jq '.[] | select(.path == "public/")'

# Cleanup
plak --quiet remote detach mysite --yes
plak --quiet remote delete prod --yes
```

## Development Workflow

When editing Plak CLI:

1. Read `AGENTS.md` first.
2. Prefer existing Bash module patterns.
3. Compile after source edits:

```bash
./compile.sh
```

4. Validate:

```bash
bash -n main shared/* shared/site/* commands/* commands/site/* compile.sh install.sh plak.sh
./tests/smoke.sh
```

5. Do not modify `homebrew-tap/` unless the user is doing a release and the CLI artifact already exists.

## Troubleshooting

- If `plak list` or site commands fail with missing dependencies, run `plak install`.
- If the dashboard does not respond, run `plak status`, then `plak enable` or `plak reload`.
- If HTTPS warnings appear, run `plak trust`.
- If ports 80/443 conflict with another local dev tool, use `plak ports`.
- If you need to install Plak CLI first, see **Installation** above.
