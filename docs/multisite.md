# Local WordPress multisite

```sh
plak add network --multisite subdirectories --no-agent
plak add network-domains --multisite subdomains --no-agent
plak network network --json
plak network create network team --title 'Team'
plak login network admin --subsite 2 --raw
plak clone network network-copy --yes
plak rename network-copy renamed-network
```

Both modes retain WordPress network constants and IDs. `plak network` obtains
live subsites/URLs from WordPress; it does not accept arbitrary external login
URLs. Login validates network membership and the selected user before generating
a short-lived token. The dashboard detail view shows network mode and subsites.
`plak list --json` includes network data for Plak-created networks.

Subdomain networks receive a `*.network.localhost` Caddy host with `tls internal`;
subdirectory networks receive the WordPress asset/admin prefix rewrite. New
subsites need no separate directory. Clients must resolve `*.localhost` to
loopback and trust Plak's current local CA. Default local HTTPS is recommended;
nondefault application ports require additional validation. Linux web routing and
wildcard certificate verification were tested with a temporary official
FrankenPHP v1.12.7 binary (PHP 8.5.11, Caddy 2.11.4), isolated loopback listeners
and a temporary CA; this does not validate macOS or installed browsers.

## Data safety and supported boundaries

- Clone changes only the independent destination DB/files. Network/bare domain
  fields, serialized URLs and `DOMAIN_CURRENT_SITE` are rewritten; unrelated
  externally-suffixed hostnames are excluded by regex boundaries.
- Only one local root network, with all subsites under the managed localhost
  domain and Plak's configured local DB credentials/server, is supported by clone
  and rename. External mapped domains / multiple networks fail before copying.
- Network rename first provisions an independent clone. The old directory is
  retained under `~/Plak/cache/rename-recovery.*` and the old DB is deliberately
  retained. `rename-recovery` in the new site's directory points to it. Inspect
  that old wp-config.php to identify the DB before manually cleaning up. On failure,
  keep the recovery and resolve the reported state; there is no destructive
  automatic cleanup of source data.
- IP-based LAN and quick-tunnel access cannot preserve network hostname routing,
  so both are rejected before changing state. The MU-plugin never collapses a
  multisite network to the incoming LAN/share hostname.
- Multisite archive import, snapshot restore, remote push/pull and automatic agent
  preparation are not supported in this delivery. Snapshot creation/export still
  saves the entire network; it is not a per-subsite backup. Unsupported mutations
  are rejected before writing. Dashboard plugin/theme mutations and cron execution
  require explicit network/subsite scope and are refused; use the WP-CLI console
  or `plak wp network ... --url=<actual-subsite-url>` with intentional scope.

## Verification

`PLAK_LIVE_TESTS=1 bash tests/multisite-live.sh` exercises real WordPress 6.8.1
and an isolated MariaDB with a PHP CLI wrapper: both modes, subsite creation,
login rejection, cloning, serialized options and renaming. It downloads WordPress
and is opt-in. To additionally validate the generated Caddy config, subdirectory
admin/asset routing and trusted wildcard TLS, set `PLAK_TEST_FRANKENPHP` to an
official executable binary. Tests use isolated high ports and do not install the
temporary CA in system/browser trust stores.
