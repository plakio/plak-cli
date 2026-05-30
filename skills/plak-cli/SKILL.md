---
name: plak-cli
description: "Use when working with Plak CLI: managing local WordPress/plain sites, the https://plak.localhost dashboard, Plak install/status/service workflows, database backups, pull/push migrations, local domains, SSH server aliases, SSH keys, or Plak release/Homebrew maintenance."
---

# Plak CLI

Use Plak for local developer workflows around:

- Local WordPress and plain static sites served by FrankenPHP/Caddy.
- The Plak dashboard at `https://plak.localhost`.
- Adminer at `https://db.plak.localhost` and Mailpit at `https://mail.plak.localhost`.
- SSH server aliases, local hosts entries, and SSH keys.
- Plak CLI development, tests, releases, and Homebrew tap maintenance.

## Key Rules

- Keep existing `server`, `domain`, and `sshkey` behavior intact when changing site features.
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
brew tap plakio/plak-cli && brew install plak-cli
```

## Common Commands

```bash
plak status
plak install
plak enable
plak disable
plak reload
plak version
```

Sites:

```bash
plak add <name> [--plain]
plak delete <name> [--force]
plak rename <old-name> <new-name>
plak list [--totals]
plak login <site> [<user>]
plak path <site>
plak url <site>
plak log [site] [-f]
```

Databases and migration:

```bash
plak db backup
plak db list
plak pull [--proxy-uploads]
plak push
```

Network and config:

```bash
plak ports [--http PORT] [--https PORT] [--skip-urls] [--dry-run]
plak memory [set <value>] [--yes]
plak directive <add|update|delete|list> [site]
plak mappings <site> [add|remove|list] [domain]
plak proxy <add|list|delete>
plak share [site]
plak lan <enable|disable|status|trust> [site]
plak tailscale <enable|disable|status>
```

Original Plak utilities:

```bash
plak server <list|add|connect|delete>
plak domain <list|add|delete>
plak sshkey <list|view|create|delete>
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

5. Do not modify `homebrew-plak-cli/` unless the user is doing a release and the CLI artifact already exists.

## Troubleshooting

- If `plak list` or site commands fail with missing dependencies, run `plak install`.
- If the dashboard does not respond, run `plak status`, then `plak enable` or `plak reload`.
- If HTTPS warnings appear, run `plak trust`.
- If ports 80/443 conflict with another local dev tool, use `plak ports`.
- If you need to install Plak CLI first, see **Installation** above.
