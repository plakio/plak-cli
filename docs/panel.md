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
the real site root (`StrictHostKeyChecking=accept-new`, wrong paths never
bind): `wp-config.php` marks a WordPress root and `index.html`/`index.htm`
a static web root. Both link the same way; push/pull choose their flow
from the local site. The command then creates/reuses an SSH remote and
records `.panel-link` (panel/account/remote ids and the detected `type`,
no tokens). `plak panel unlink` removes the
record only; installed SSH keys are removed in the panel (Servers > SSH
keys) and live independently of API keys.

A panel domain/remote holds one local site at a time: attaching a second
local site to the same remote warns, because their pushes overwrite each
other and the last one wins. In non-interactive runs, `link` reports every
missing flag (`--system-user`, `--path` when needed, and `--key` or
`--generate`) in one hint.

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
plak panel offers [--provider NAME] [--family KEY] [--region ID|NAME] [--json]
plak panel buy-server --offer ID --region ID --name N [--wait SECS] [--poll SECS] [--json] [--new]
plak panel purchase-request <id> [--wait SECS] [--poll SECS] [--json]
plak panel purchases [--json]
plak panel create-server --name N --provider ID --region ID --plan ID [--json]   # legacy
plak panel delete-server <id|name> [--yes] [--json]
plak panel restart-server <id|name> [--yes] [--json]
plak panel create-site --domain D --server <id|name> [--json]
plak panel delete-site <id|domain> [--yes] [--json]
```

Creation is async (`202 busy`): the CLI polls until `active`/`failed` (or
timeout, never a false success). Deletes confirm (or `--yes`); remote
removal is panel best-effort. `--json` never includes secrets.

`providers` is kept for older panels that still serve `/api/v1/providers`.
Current panels retire that endpoint, so the CLI derives the same
provider/region/plan references from `offers` instead of reporting a
misleading account error.

`create-server` is the legacy direct-creation path. Panels with per-server
billing answer `servers.purchase_required` (or retire the route); the CLI
guides to `offers`/`buy-server` and never falls back to global or comped
creation.

## Purchases — offers, approval and polling (CLI-50/51)

The panel sells new servers through an offer catalog. The catalog is readable
with `user:read`, so an account without a paid package can browse it. Buying
needs the opt-in `billing:request` scope (Perfil > API Keys); `buy-server`
does not require `user:read`, because the panel validates the offer/region
pair on the POST. A key with both scopes covers the full flow.

The device pairing grants `user:read` + `ssh:authorize` by default.
`plak connect --billing` asks the panel to grant `billing:request` when the
holder approves the device (PLA-277). Until the deployed panel grants it, the
CLI warns and the fallback is a manual API key with that scope:

```bash
plak connect --billing
plak connect status                    # shows scopes and purchase availability
printf '%s\n' "$PLAK_API_KEY" | plak connect --manual --token-stdin
```

`billing:request` can only request a purchase and read its status, never
approve or pay.

```bash
plak panel offers
plak panel offers --json
plak panel offers --provider AWS
plak panel offers --family arm
plak panel offers --region 13
plak panel buy-server --offer 12 --region 13 --name web-1
plak panel buy-server --offer 12 --region 13 --name web-1 --json
plak panel purchase-request 42 --wait 600 --poll 10
plak panel purchases --json
```

- `offers` returns one catalog entry per offer+region. Human output groups by
  `offer_id`, shows the Plak plan (`code`), family, provider plan, specs,
  reference price and every available region. `family`/`family_label` are
  optional: some providers (DigitalOcean, Vultr, UpCloud) omit them, and the
  CLI simply leaves the family out. `--provider`, `--family` and `--region`
  filter the catalog (region accepts an id or label).
- `buy-server` sends only `offer_id`, `provider_region_id`, `name` and an
  idempotency key. It never sends a price or Polar product/price ID.
- The CLI prints only the panel's internal `approval_url` (for example
  `https://cloud.plak.io/billing/purchase-requests/42`). The account holder
  opens it in an authenticated browser and approves/pays there. The CLI never
  receives or prints the Polar checkout URL, customer portal URL or token.
- `--yes` is not financial approval. In non-interactive mode the command only
  requests the purchase and reports the approval URL. A free account can
  request and explore; no VM is created until the holder approves and the
  backend confirms payment.
- The idempotency key is stored in
  `${PLAK_HOME:-$HOME/.plak}/panel-purchases.json` (dir `700`, file `600`)
  before the POST. Re-running the same offer/region/name resumes the stored
  request; a lost response is retried with the same key, so a purchase is not
  duplicated. After a timeout re-run the same `buy-server` command (same key)
  or, if you have the request id, use `purchase-request <id>`; never a blind
  retry with a new key.
- Long polls tolerate transient failures (timeouts, refused connections,
  5xx): the CLI retries up to 3 consecutive times with backoff based on
  `--poll` and keeps the last known status. A timeout is reported differently
  from a refused connection. If polling stops for real, the request id and an
  explicit `purchase-request <id> --wait ...` resume command are always
  printed; stopping polling is never permission to create another purchase.
- Statuses: `pending_approval`, `approved`, `checkout_open`, `paid`,
  `provisioning`, `fulfilled` (success); `failed`, `cancelled`;
  `manual_review` and `provisioning_unknown` are ambiguous. Any status the CLI
  does not recognize is also treated as ambiguous (exit 3), never as success.
  Stop and check the panel/support; do not create another purchase.
- `expires_at` applies to `pending_approval`, `approved` and `checkout_open`.
  The CLI reports `expired` and asks for an explicit `--new`; it never silently
  creates a second request. `--new` is only accepted after `failed`/`cancelled`
  or an expired approval, never for `paid`, `provisioning`, ambiguous or
  unresolved requests.
- `purchases` lists the local request records (safe fields only). The token is
  never stored there or printed in `--json`.
- Deleting a paid server schedules cancellation for the end of the paid
  period; the CLI reports the panel message and does not claim immediate
  destruction. The subscription is cancelled in the Polar portal.

`--json` exposes `request_id`, `status`, `approval_url`, `expires_at`,
`created_at`, `resumed`, `approval_required`, and the flags `expired`,
`timed_out`, `ambiguous` or `interrupted` when applicable; a timed-out or
interrupted poll also includes `resume_command`. `approval_required` is true
only while the holder still has to act (`pending_approval`, `approved`,
`checkout_open`); `expired` only applies to those states, never to a terminal
request. It never exposes a token, Polar URL, customer portal URL or
idempotency key.

Known API gaps (reported, not worked around with fragile heuristics):

- A lost response has no lookup by idempotency key, so the CLI re-sends the
  same POST with the same key. The Panel returns the existing request; this is
  not a second purchase, but it is an HTTP retry.
- A `fulfilled` request does not include the created `server_id`; run
  `plak panel servers` to find the new server.

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
