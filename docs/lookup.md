# `plak lookup` — WHOIS, DNS, email and zones

`plak lookup` uses the public API at `https://lookup.plak.io`. It needs no
account or token. Set `PLAK_LOOKUP_URL` to point at staging or a self-hosted
instance (the value is normalized without a trailing slash).

```bash
plak lookup example.com
plak lookup example.com --deep
plak lookup example.com --json

plak lookup whois example.com
plak lookup dns example.com --type MX
plak lookup email example.com
plak lookup zone example.com --deep --output example.com.zone
plak lookup health --json
```

- `--deep` requests AXFR plus Certificate Transparency discovery. It has a
  tighter rate limit and can be slower.
- `--json` prints the API response unchanged; it never mixes human text into
  stdout.
- `--timeout SECS` controls the HTTP timeout (default 30).
- `whois`, `dns`, `email` and `zone` fetch the same lookup and filter the
  result; `dns --type` accepts any DNS type returned by the API.
- `health` exits non-zero when the service is not `ok`.

## Audit, convert and diff

```bash
plak lookup audit example.com example.org --wait 600 --poll 5
plak lookup audit --file domains.txt --wait 600 --format csv --output audit.csv
plak lookup audit --id <job-id> --wait 600
plak lookup audit --cancel <job-id>

plak lookup convert zone.txt --provider cloudflare --output cloudflare.zone
plak lookup diff --before old.zone --after new.zone --csv
```

- `audit` accepts up to 100 domains from arguments, `--file`, or stdin (`-`).
  Without `--wait` it starts the job and prints its id. With `--wait` it polls
  and exits `3` if the job is still running at the deadline.
- `--format json|csv` downloads the finished report to `--output` or stdout.
- `convert` accepts a BIND zone file (or `-`/stdin) and writes the converted
  content. Supported providers: `bind`, `cloudflare`, `route53`, `route53-json`.
- `diff` compares two BIND zones and prints the risk and changes; `--csv`
  prints the CSV export.

All inputs are limited by the API to 1 MB and the public rate limits apply:
30/min normal lookup, 5/min deep, 10/min convert/diff, 5/min audit creation and
120/min audit status. A `429` prints the `Retry-After` value.

Domains are sent to `lookup.plak.io` and recorded in its logs; the CLI never
sends credentials. Tests use a local stub and never call the real service.
