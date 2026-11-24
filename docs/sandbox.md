# `plak sandbox` — disposable sites

`plak sandbox` talks to the public Sandbox API at
`https://sandbox.plak.io`. There is no account, no token and no
`plak sandbox connect`. Set `PLAK_SANDBOX_URL` for staging or tests.

## Model

- Any user can create a sandbox, like the public form.
- The site UUID is an access link: `/s/<uuid>` shows the site details and
  credentials. Share that link only with people who need admin access.
- To share only the site preview, share the site URL
  (`https://<subdomain>.sandbox.plak.io`), not the `/s/<uuid>` page.
- The CLI stores only `uuid`, subdomain, domain, URLs and expiration in
  `${PLAK_HOME:-$HOME/.plak}/sandbox-sites.json` (mode `600`). It never stores
  WordPress or database passwords.
- There is no `delete`: sandboxes expire automatically and the admin cleans
  them up.

## Commands

```bash
plak sandbox create demo
plak sandbox create demo --email me@example.com --plugin devkit
plak sandbox list
plak sandbox show demo
plak sandbox show demo --secrets
plak sandbox open demo
plak sandbox open demo --info
plak sandbox import https://sandbox.plak.io/s/<uuid>
```

- `create` validates the subdomain and plugins, sends an
  `Idempotency-Key`, retries one interrupted/5xx request safely and prints the
  site URL, `/s/<uuid>` info page, WordPress credentials and expiration.
- If both attempts fail, the pending idempotency key is kept locally. Re-running
  the same `create` command reuses it, so a timeout does not create a second
  site.
- `list` reads the local file only. It is not a global server list and does not
  show sites created on another machine.
- `show` refreshes the site from `GET /api/v1/public/sites/{uuid}`. Credentials
  are hidden unless `--secrets` is passed.
- `import` extracts the UUID from an existing `/s/<uuid>` URL and adds it to
  the local list.
- `--json` prints the API response (or a filtered response for `show`/`import`)
  and never mixes human messages into stdout.
- `PLAK_SANDBOX_URL` defaults to `https://sandbox.plak.io`.

## Rate limits and errors

Creation is rate-limited by IP (the exact quota is configured by Sandbox).
`429` prints `Retry-After`; `503` means creation is temporarily disabled;
`422` usually means invalid input or a taken subdomain. The CLI never prints a
token and never sends WordPress or database passwords anywhere.

The CLI assumes Sandbox serves the public endpoints described in
`plakio/sandbox#1` and `plakio/sandbox#2`. Until those are deployed,
`plak sandbox` will report the API error instead of falling back to scraping
the public website.
