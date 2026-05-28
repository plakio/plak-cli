# plak

Plak CLI is a Bash + [gum](https://github.com/charmbracelet/gum) tool for everyday local developer tasks:

- SSH server aliases in `~/.ssh/config`
- Local domain entries in `/etc/hosts`
- SSH keys in `~/.ssh`
- Local WordPress and plain static sites served through Caddy/FrankenPHP

It follows a modular structure: source files are compiled into a single distributable `plak.sh` script.

## Quickstart

```bash
# Install Plak CLI
curl -fsSL https://plak.sh/install.sh | bash

# Install local dependencies
plak install

# Create a WordPress site
plak add my-site

# Access the dashboard
open https://plak.localhost
```

## Requirements

- Bash
- `gum`
- `ssh` and `ssh-keygen`
- `frankenphp`, `mariadb`, `mailpit`, and `wp-cli` for local site management
- `sudo` for writing to `/etc/hosts` when needed

## Installation

Install Plak with Homebrew:

```bash
brew tap plakio/plak-cli
brew install plak-cli
```

Or in one command:

```bash
brew install plakio/plak-cli/plak-cli
```

You can also install Plak directly with the installer script:

```bash
bash <(curl -sL https://plak.sh/install.sh)
```

Install the Plak agent skill for Codex, Claude Code, OpenCode, or Pi:

```bash
plak skill install
```

For scripted setup:

```bash
plak skill install codex
plak skill install claude-code
plak skill install opencode
plak skill install pi
plak skill install all
```

For local development, Plak can also install/check the local site stack:

```bash
./plak.sh install
```

## Development

Compile the distributable script:

```bash
./compile.sh
```

Run locally:

```bash
./plak.sh status
./plak.sh server list
```

Run smoke tests:

```bash
./tests/smoke.sh
```

Install the local compiled script as `plak`:

```bash
./install.sh --dev
```

See [docs/homebrew.md](docs/homebrew.md) for release and tap maintenance.

## Project Structure

```text
main              # globals, help, OS detection, command router
shared/           # shared UI and validation helpers
commands/         # command modules
compile.sh        # builds plak.sh
plak.sh           # compiled distributable script
install.sh        # local installer
```

## Commands

```bash
plak status
plak version
plak install
plak skill install
plak enable
plak disable
plak reload
```

The local site dashboard is served at `https://plak.localhost` after install.

### Sites

```bash
plak add <name> [--plain]
plak delete <name> [--force]
plak rename <old-name> <new-name>
plak list [--totals]
plak login <site> [<user>]
plak path <name>
plak url <name>
plak log [site] [-f]
```

### Migration

```bash
plak pull [--proxy-uploads]
plak push
```

### Database

```bash
plak db backup
plak db list
```

### Site Configuration

```bash
plak ports [--http PORT] [--https PORT] [--skip-urls] [--dry-run]
plak memory [set <value>] [--yes]
plak directive <add|update|delete|list> [site]
plak mappings <site> [add|remove|list] [domain]
plak proxy <add|list|delete>
```

### Network Access

```bash
plak share [site]
plak lan <enable|disable|status|trust> [site]
plak tailscale <enable|disable|status>
plak valet <enable|disable|status>
plak wsl-hosts
plak trust
plak upgrade
```

**Laravel Valet** — If Valet owns ports 80/443 and Plak runs on alternative ports (e.g. 8090/8453), `plak valet enable` creates an nginx reverse proxy so `*.localhost` routes through Valet to Plak. Use `plak valet status` to check and `plak valet disable` to remove.

### SSH Servers

```bash
plak server list
plak server add
plak server connect
plak server delete
```

### Domains

```bash
plak domain list
plak domain add
plak domain delete
```

`domain add/delete` creates a timestamped backup next to the hosts file before writing. On `/etc/hosts`, this usually requires `sudo`.

### SSH Keys

```bash
plak sshkey list
plak sshkey view [key-name-or-path]
plak sshkey create
plak sshkey delete
```

## Notes

- Interactive commands require a real terminal because `gum` opens TUI prompts.
- Non-interactive list/status commands fall back to plain output for scripts and tests.
- `plak.sh` is generated from `main`, `shared/`, and `commands/`.
