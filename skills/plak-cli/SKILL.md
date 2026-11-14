---
name: plak-cli
description: "Use when working with Plak CLI: managing local WordPress/static sites, the https://plak.localhost dashboard, Plak install/status/service workflows, database backups, pull/push migrations, /etc/hosts entries, SSH remotes with site bindings, SSH keys, or Plak release/Homebrew maintenance."
---

# Plak CLI

Use Plak for local developer workflows around:

- Local WordPress and static sites served by FrankenPHP/Caddy.
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
# Via curl (macOS/Linux/WSL), interactive: asks before installing the stack
curl -fsSL https://plak.sh/install | bash

# Non-interactive (agents/CI): CLI + local stack, installs Homebrew on macOS
curl -fsSL https://plak.sh/install | PLAK_YES=1 bash

# CLI only, without the local stack
curl -fsSL https://plak.sh/install | PLAK_CLI_ONLY=1 bash

# Via Homebrew (macOS)
brew install plakio/tap/plak-cli
```

`PLAK_YES=1` installs Homebrew on macOS when needed and persists its
`shellenv` for new shells. It may still need a sudo password. Run it in a
terminal or configure passwordless sudo for the agent; do not store the
password in the agent configuration. On Windows, run the command inside WSL
with systemd enabled.

Install this skill for supported agents:

```bash
plak skill install [--no-windows] [codex|claude-code|opencode|hermes|pi|global|all]
```

On WSL, this also installs into the Windows user profile for `codex`,
`claude-code`, `opencode`, and `global`, so native Windows agents can discover
it. Use `--no-windows` to install only in WSL. Hermes and Pi are installed only
in WSL because their Windows discovery paths are not verified.

Hermes installs to `~/.hermes/skills/plak-cli/SKILL.md`.

## Agent-friendly interface

The CLI is designed for non-interactive use by AI agents. No TTY is required when all values are passed via flags or positional args.

**Global flags** (can appear before the command or after the action):

- `--quiet` / `-q` — suppress success messages on STDOUT. Errors still go to STDERR.
- `--json` — force JSON output for commands that support it.
- `--help` / `-h` — show help. Must come after the command name.

Exception: `plak wp <site> <args...>` passes everything after the site name
unchanged to WP-CLI, including its flags. It preserves stdin, stdout, stderr and
WP-CLI's exit code. Use `plak wp --help` for Plak's wrapper help.

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
plak health php            # embedded CLI/web PHP + PHP2Shell security floor
plak --json version        # {name, version}
plak install --yes         # non-interactive install (auto-accept defaults)
plak enable
plak disable
plak reload
plak --quiet version       # suppress output for scripts
```

## Sites

```bash
plak add <name> [--static] [--agent] [--no-reload]
plak delete <name> [--force|--yes] [--no-reload]
plak rename <old-name> <new-name>
plak list [--totals] [--json]
plak login <site> [<user>] [--raw]    # --raw prints only the URL
plak wp <site> <wp-cli arguments...> # uses the same PHP runtime as the web
plak path <site>
plak url <site>
plak edit <site> [--print-url] [--no-open]
plak log [site] [-f]
```

`--static` creates a static site with the default HTML starter at
`public/index.html`. It has no database and no WordPress files.

Use `--static` for a new static HTML site. `--plain` and `--html` are not valid
flags.

Static sites show a local **Edit** launcher on the page; `plak edit <site>`
opens it directly. The editor edits text inline (bold, italic, underline),
images (URL, alt, upload to `public/uploads/` or drop a file onto an existing
image), links (href and target) and raw HTML, with undo/redo, SHA conflict
checks and backups. It lives in Plak's app directory, not in `public/`, and is
never part of the published site.

Use `plak wp <site> plugin list --format=json` or
`plak wp <site> option get siteurl` from any directory. New WordPress sites are
marked `WP_ENVIRONMENT_TYPE=local`; failed provisioning removes only resources
created by that attempt. A reload-only failure keeps the completed site for retry.

## Creating a site for the user

When the user asks you to create a site, never guess its name or its type.
Ask these two questions first, in this order, unless the user already answered
them:

1. What should the site be called?
2. Should it be a static HTML site or a WordPress site?

Then create it with the matching flag:

| Type | Command |
| --- | --- |
| Static HTML | `plak add <name> --static` |
| WordPress | `plak add <name> --agent` |

- `--static` creates a static site with `public/index.html`; it has no database
  and no WordPress files.
- `--agent` explicitly prepares a WordPress site for an agent: it installs and
  activates WP-MCP and HTML Editor, enables WP-MCP abilities, mints an
  Application Password, and registers the site in `wp-mcp-cli`. If preparation
  fails after creation, repair it with `plak agent <name>` (idempotent).
- `--agent` cannot be combined with `--static`. `--plain` and `--html` are not
  valid flags.

Do not create a WordPress site just because the user did not name a type; ask.

After creating the site, report:

- the site URL: `plak url <name>`
- for WordPress, the login URL: `plak login <name> --raw`
- the dashboard: `https://plak.localhost`

## Agent-ready sites (WP-MCP)

**When you create a WordPress site for yourself, always pass `--agent`** unless
the user explicitly asked for a WordPress site without agent preparation:

```bash
plak add mysite --agent
```

`--agent` creates the site and then installs and activates the **WP-MCP** and
**HTML Editor** plugins, sets a standard permalink structure and enables WP-MCP's
abilities (locked to the site's host) so its REST API works, mints a scoped
WordPress Application Password, registers the site with `wp-mcp-cli` under a
profile named after the site, and verifies that WP-MCP abilities are discoverable.
It cannot be combined with `--static`.

Once ready, drive the site through wp-mcp instead of guessing at REST calls:

```bash
wp-mcp --site mysite --json discover
wp-mcp --site mysite describe wp-mcp/list-directory
wp-mcp --site mysite run wp-mcp/list-directory --input '{"path":"/"}'
```

`plak install` installs `wp-mcp-cli` (and `jq`) alongside Plak. `plak skill install`
also installs the official wp-mcp skill for the selected agents.

If preparation fails after the site is created, the WordPress site is kept; repair
it (idempotently) with:

```bash
plak agent mysite          # re-installs plugins, rotates the password, re-verifies
plak agent mysite --json   # single JSON envelope on stdout
```

## Databases and migration

```bash
plak db backup
plak db list [--json]
plak pull [<site>] [--yes] [--dry-run] [--proxy-uploads]
plak push [<site>] [--yes] [--dry-run]
```

`plak push <site>` and `plak pull <site>` skip their interactive path prompt when the site has a remote binding (see **Remotes** below). Use `<site>` to skip the site picker and `--yes` to skip the overwrite confirmation.

Static sites transfer only `public/` and never a database. Static push keeps
remote-only files by default and creates a remote backup; static pull requires
an existing static site, mirrors the remote public tree, and keeps a local
backup. `--dry-run` previews either direction. `--proxy-uploads` is
WordPress-only.

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

# Panel account (device flow, Botmail-style; secret never via argv)
plak connect [--panel URL] [--dev] [--no-open] [--wait SECS] [--poll SECS] [--json]
plak connect --manual [--panel URL] [--dev] --token-stdin   # echo "$KEY" | plak connect --manual --token-stdin
plak connect status [--json]
plak disconnect [--yes]   # local forget only; revoke in panel Perfil > API Keys
```

**Panel connection**: `plak connect` requests a pairing and polls until you
approve it in the panel (`approve_url`, 1 click). Credential lives in
`${PLAK_HOME:-~/.plak}/connection.json` (dir `700`, file `600`); `--json`
outputs never include the secret. Dev behind Cloudflare Access needs
`PLAK_CF_ACCESS_TOKEN` (service token, different from the Plak API key).

**Panel resources (read-only, connected account only)**:
`plak panel sites [--all] [--json]`, `plak panel site <id|domain>`,
`plak panel servers [--all] [--json]`, `plak panel server <id|name>`.
Never mixed with local sites (`plak list`); the saved token is never sent
to another origin.
**Panel linking**: `plak panel link <panel-site> <local-site>` authorizes
one local public key (`ssh:authorize`), verifies SSH + WP path, binds an
SSH remote and records `.panel-link` (no secrets). Wrong paths never bind;
SSH authorizations outlive API keys (remove in panel Servers > SSH keys).
**Panel migration**: `plak push/pull` on linked sites revalidate the panel
destination first (account/panel/remote/site changes and invalid tokens
stop with an explanation); manual remotes unchanged.
**Panel writes (Fase A)**: `providers`, `create-server`, `delete-server`,
`restart-server`, `create-site`, `delete-site` (opt-in scopes
`servers:write`/`sites:write`; async creation is polled, never false success).
**Panel WordPress (Fase B)**: `wp-overview|wp-themes|wp-plugins`,
`wp-complete-install|wp-mark-installed|wp-install-wpcli|wp-xmlrpc`,
theme/plugin `activate|deactivate|update|install|delete`,
`wp-search-replace`, guarded `wp-cli`, `wp-set-php|wp-set-robots`.
**Panel servers (Fase C)**: `service-list|service-restart|service-reload`,
`wpcli-install|wpcli-uninstall`, `php-info|php-install|php-cli-set`,
`opcache-enable|disable|refresh`, `firewall-list|add|del`,
`users-list|add|del` (`servers:write` for mutations; synchronous).
**Panel site infra (Fase D)**: `db-*|cron-*|cert-*|redirect-*|alias-*|dns-*|
authuser-*|cache-*|app-*` (`sites:write` for mutations).

**Remote → site bindings**: `plak remote attach <remote> <site>` writes the remote name to `~/Plak/Sites/<site>.localhost/.remote`. The `remote_path` (WordPress root or static web root) is stored in `~/.ssh/config` inside the `Host` block as `# plak-remote-path: <path>`. With a binding, `plak push <site>` and `plak pull <site>` resolve the remote automatically without prompting.

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

5. Release tags trigger the automated `homebrew-tap` update; do not edit the formula manually before the tag exists.

## Troubleshooting

- If `plak list` or site commands fail with missing dependencies, run `plak install`.
- If the dashboard does not respond, run `plak status`, then `plak enable` or `plak reload`.
- If HTTPS warnings appear, run `plak trust`.
- If ports 80/443 conflict with another local dev tool, use `plak ports`.
- If you need to install Plak CLI first, see **Installation** above.
