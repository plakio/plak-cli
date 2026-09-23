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
curl -fsSL https://plak.sh/install | bash

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
brew install plakio/tap/plak-cli
```

Or tap the repository first:

```bash
brew tap plakio/tap
brew install plak-cli
```

You can also install Plak directly with the installer script:

```bash
curl -fsSL https://plak.sh/install | bash
```

Install the Plak agent skill for Codex, Claude Code, OpenCode, Hermes, Pi, or the global agent skills directory:

```bash
plak skill install
```

For scripted setup:

```bash
plak skill install codex
plak skill install claude-code
plak skill install opencode
plak skill install hermes
plak skill install pi
plak skill install global
plak skill install all
```

`all` installs agent-specific targets only (`codex`, `claude-code`, `opencode`, `hermes`, and `pi`). Use `global` explicitly to install into `~/.agents/skills`.

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
plak add <name> [--plain] [--agent]
plak import <name> <backup.zip> [--yes]
plak delete <name> [--force]
plak rename <old-name> <new-name>
plak list [--totals]
plak login <site> [<user>]
plak wp <site> <wp-cli arguments...>
plak agent <site> [--json]
plak path <name>
plak url <name>
plak log [site] [-f]
```

Run WP-CLI from any directory using the site's FrankenPHP runtime:

```bash
plak wp my-site plugin list --format=json
plak wp my-site option get siteurl
plak wp my-site core --help
```

Arguments after the site name, including `--quiet`, `--json`, and `--help`,
are forwarded unchanged. Standard input/output, errors and the exit status
are passed through; `plak wp --help` shows Plak's wrapper help. No TTY is needed.

Plak resolves the `wp` executable through symlinks and common shell wrappers
referencing a literal PHAR path (including quoted paths with spaces and `$HOME`).
Wrappers with computed paths that cannot be resolved are rejected with guidance
to put the official WP-CLI PHAR on PATH. This keeps CLI and web on the same PHP.

New WordPress sites use `WP_ENVIRONMENT_TYPE=local` and keep debug logging enabled.
Creation checks every installation stage and cleans up only the directory and
database created by that invocation if provisioning fails. An existing database
is never reused. If only the server reload fails, the completed site is kept and
Plak reports how to retry the reload.

### Agent-ready sites

Agents should create the sites they will work on with `--agent`:

```bash
plak add my-site --agent
```

This creates the WordPress site, then installs and activates the **WP-MCP** and
**HTML Editor** plugins from `downloads.plak.io`, sets a standard permalink
structure and enables WP-MCP's abilities (locked to the site's host) so its REST
API answers, mints a scoped WordPress Application Password, registers the site
with `wp-mcp-cli` under a profile named after the site, and verifies that WP-MCP
abilities are discoverable. The plugins are downloaded with the
`PlakCLI/<version>` User-Agent, so the downloads host can allow Plak through its
firewall without opening the archives to the world. `--agent` requires WordPress
and cannot be combined with `--plain`.

`plak install` installs `wp-mcp-cli` and its `jq` dependency alongside Plak, and
`plak skill install` also installs the official wp-mcp skill for the selected
agents. After a successful `--agent` run the site is driven through wp-mcp:

```bash
wp-mcp --site my-site --json discover
wp-mcp --site my-site run wp-mcp/list-directory --input '{"path":"/"}'
```

If preparation fails after the site is created, the site is kept and the failure
is reported as partial. Repair it idempotently (installs/activates the plugins,
rotates the scoped password, refreshes the profile and re-verifies) with:

```bash
plak agent my-site
plak agent my-site --json
```

### Migration

```bash
plak pull [--proxy-uploads]
plak push
```

Pull and push ship a self-contained Plak engine to the remote over SSH and run
it there, so the remote needs neither internet access nor a publicly reachable
backup URL. The backup itself travels over SSH. Before touching the remote
database, Plak checks which archive and database tools are available
(`plak.sh/go diagnose` reports the same set) and cancels with an actionable
message when a required tool is missing. The helper and backup are removed on
success and on controlled failures; if removal is impossible, Plak reports the
remote path so it can be cleaned manually.

### Database

```bash
plak db backup
plak db list
```

### Snapshots

```bash
plak snapshot <site> create [--note <text>]
plak snapshot <site> list [--json]
plak snapshot <site> restore <id> [--yes]
plak snapshot <site> delete <id> [--yes]
plak snapshot <site> export <id> [--output <path>]
```

`plak import` creates a new site from a WordPress backup ZIP, tar.gz or tar
(including Plak exports, Local exports, and hosting backups with a single-site
WordPress tree and one recognisable SQL dump). It refuses path traversal,
ambiguous or missing SQL dumps, existing destinations, and multisite backups,
and rewrites home/siteurl plus the table prefix through the shared migration
engine. A failed import keeps the partially created site for inspection and
tells you how to remove it.

Snapshots are local recovery points of a site's files and database, stored under
`private/snapshots/<id>` with a unique, sortable identifier. Static sites only
capture files. Restoring keeps a safety snapshot of the current state first and
applies the same recoverable database contract as migrations, so a partial
restore is never reported as success. Export produces a portable ZIP.

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
plak wsl-hosts
plak trust
plak upgrade
```

### SSH Remotes

```bash
plak remote list
plak remote add <name> --host <host> --user <user> [--port <port>] [--path <path>]
plak remote connect [name]
plak remote delete <name> --yes
plak remote attach <remote> <site>
plak remote detach <site>
```

`remote add` records an SSH host in `~/.ssh/config` and stores the remote WordPress path as `# plak-remote-path: <path>` in the same block. Once `remote attach` binds a remote to a site, `plak push` and `plak pull` skip their interactive prompts.

### Hosts

```bash
plak hosts list
plak hosts add <ip> <domain>
plak hosts delete <domain> --yes
```

`hosts add/delete` creates a timestamped backup next to the hosts file before writing. On `/etc/hosts`, this usually requires `sudo`.

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
