# `plak panel` — own sites and servers (CLI-25)

Read-only access to the connected account's panel resources. Local sites
(`plak list`) and panel resources are never mixed: this command only talks
to the saved connection (`plak connect`: panel URL + token + identity).

```bash
plak panel sites [--page N] [--per-page N] [--all] [--json]
plak panel site <id|domain> [--json]
plak panel servers [--page N] [--per-page N] [--all] [--json]
plak panel server <id|name> [--json]
```

- Pagination follows the panel (`page`, `per_page` 1–100, `--all` walks
  every page for inventories and automation).
- Selection accepts a numeric id (direct lookup) or the exact
  domain/name (searches pages, max 10).
- The saved token is never sent to another origin: `--panel/--dev` for a
  different origin is refused — reconnect with
  `plak connect --panel <url>` instead.
- Empty accounts report "No sites/servers yet" (exit 0). Revoked/expired
  tokens point at `plak connect`; blocked accounts are reported as such.
- `--json` outputs never include the secret.

Requires panel endpoints `GET /api/v1/sites`, `/sites/{id}`, `/servers`,
`/servers/{id}` (personal API, `user:read`). Foreign IDs resolve to
`404` server-side, so other accounts' resources are neither listed nor
enumerable.

## Linking (`plak panel link`, CLI-26)

`plak panel link <panel-site> <local-site>` authorizes one local public
key on the panel server (`ssh:authorize` scope), verifies SSH access and
the real WordPress path (`StrictHostKeyChecking=accept-new`, wrong paths
never bind), then creates/reuses an SSH remote and records `.panel-link`
(panel/account/remote ids, no tokens). `plak panel unlink` removes the
record only; installed SSH keys are removed in the panel (Servers > SSH
keys) and live independently of API keys.

## Migrating (`plak push` / `plak pull`, CLI-27)

Linked sites revalidate the panel destination before anything destructive
runs: account/panel mismatch, swapped remotes, withdrawn or renamed sites
and invalid tokens stop with an explanation instead of migrating blindly.
The transfer engine itself is unchanged (CLI-7/CLI-6); manual remotes
without `.panel-link` behave exactly as before.

## Writing — providers, servers, sites (CLI-40)

Opt-in scopes `servers:write` / `sites:write` (grant in panel Perfil >
API Keys; pairing keys carry read + SSH only — a `403` always tells you
how to grant them):

```bash
plak panel providers [--json]
plak panel create-server --name N --provider ID --region ID --plan ID [--json]
plak panel delete-server <id|name> [--yes] [--json]
plak panel restart-server <id|name> [--yes] [--json]
plak panel create-site --domain D --server <id|name> [--json]
plak panel delete-site <id|domain> [--yes] [--json]
```

Creation is async (`202 busy`): the CLI polls until `active`/`failed` (or
timeout, never a false success). Deletes confirm (or `--yes`); remote
removal is panel best-effort. `--json` never includes secrets.

## WordPress (`plak panel wp-*`, CLI-41)

Reads (`user:read`): `wp-overview`, `wp-themes`, `wp-plugins` (with
`--refresh`). Mutations (`sites:write`): `wp-complete-install`,
`wp-mark-installed`, `wp-install-wpcli`, `wp-xmlrpc --block|--allow`,
theme/plugin `activate|deactivate|update|install|delete`, `wp-search-replace`
(`--dry-run` or confirm), guarded `wp-cli -- <command>`, async
`wp-set-php --version` (polled) and `wp-set-robots`. Partial results
(`updated/failed`) are always shown; destructive remote wp-cli is denied
server-side.

## Site infra (`plak panel db-*|cron-*|cert-*|redirect-*|alias-*|dns-*|authuser-*|cache-*|app-*`, CLI-43)

Databases, cronjobs, certificates, redirects, aliases, DNS (Cloudflare),
HTTP auth, cache (FastCGI/OPcache) and one-click apps on your own sites.
Reads need `user:read`; mutations need `sites:write` (+ package update
policy). Local resources are addressed by panel id; remote-only ones
(DNS records, HTTP auth users) by their remote id. Deletes confirm or
`--yes`; creation is synchronous where the panel is (databases) or async
where it is not (apps, polled via `app-info`).

## Server operations (`plak panel *`, CLI-42)

Services (`service-list`, `service-restart`, `service-reload`), WP-CLI
(`wpcli-install` polled, `wpcli-uninstall`), PHP (`php-info`, `php-install`,
`php-cli-set`), OPcache (`opcache-enable|disable|refresh`), firewall
(`firewall-list|add|del`) and system users (`users-list`, `users-add` shows
the password once, `users-del`). Reads need `user:read`; mutations need
`servers:write` (+ package update where the panel requires it). Everything
is synchronous server-side: a 200 only comes back when Ploi answered.
