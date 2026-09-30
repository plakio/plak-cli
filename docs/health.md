# Stack health

`plak health` is read-only: services, FrankenPHP version, disk, bounded log
signals and recovery/old-job candidates. `unknown` / JSON `null` means the
measurement could not be obtained; a log match does not establish a crash cause.
Candidate resources are never removed automatically.

Run `plak reload` after upgrading to deploy the loopback-only web PHP probe.
`plak health opcache [--json]` reads the **web process**, including configuration
limits, free memory, `cache_full`, hits and misses. An unavailable probe never
falls back to CLI OPcache.

```sh
plak health opcache set opcache.memory_consumption=256 opcache.max_accelerated_files=20000
# Saves php.ini only; does not reload/restart or prompt.
plak health opcache set opcache.memory_consumption=256 --restart
# Explicitly regenerates configuration and restarts FrankenPHP.
```

Supported settings: enable / validate_timestamps (0 or 1), memory_consumption
(8–4096 MB), interned_strings_buffer (1–1024 MB), max_accelerated_files
(200–1000000), revalidate_freq (0–3600 seconds). Review real free memory before
raising limits. No scheduled restarts are added. `--yes` alone does not restart.

## HTTP/2 evaluation: representative-load evidence still pending

The existing Caddy configuration explicitly uses `protocols h1`. It remains the
default. Initially `command -v frankenphp` returned exit status 1 in this
development environment. A temporary official v1.12.7 binary was later used to
validate multisite HTTPS and the web OPcache probe (see `docs/multisite.md`),
without installing it globally. Representative HTTP/2 load evidence still has
**not** been collected; the default is not changed by the multisite tests.
`plak health http2` only reports curl capability and negotiated protocol, not
performance. A client without HTTP2 support reports negotiation as unknown.

To reproduce the evaluation on an installed stack:

1. Record `frankenphp version`, `curl --version`, platform, site and configuration.
2. Measure HTTP/1.1 on the dashboard, a static site and a representative WordPress
   site, recording errors and latency (warm and cold requests, concurrent load).
3. For evaluation only, set `HTTP2_ENABLED='1'` in `~/Plak/config` and run
   `plak reload`. This generates `protocols h1 h2`, retaining HTTP/1.1.
4. Repeat identical requests with `curl --http2`, verify `http_version=2`, and
   compare errors, latency and service logs. Example single-request probe:
   `curl --noproxy '*' -k --http2 -o /dev/null -w '%{http_version} %{time_total}\n' https://plak.localhost/`.
5. Restore `HTTP2_ENABLED='0'` and reload if compatibility or load checks fail.

Default enablement requires those results; fixture tests alone are insufficient.
