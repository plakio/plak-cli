# Stack health

`plak health` is read-only: services, FrankenPHP version, disk, bounded log
signals and recovery/old-job candidates. `unknown` / JSON `null` means the
measurement could not be obtained; a log match does not establish a crash cause.
Candidate resources are never removed automatically.

The web probe distinguishes shared-cache metrics from `opcache_ini` settings.
Invalid negative memory counters, a zero enabled-cache limit or non-finite
percentages are returned as JSON `null` / text `unknown`, with
`opcache_warnings`; they are never replaced with guessed usage values. The
separate INI values are configuration, not proof of measured cache capacity.

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

## HTTP/2 evaluation: opt-in retained after real load tests

The existing Caddy configuration explicitly uses `protocols h1`. It remains the
default. On 2026-10-01 a temporary official FrankenPHP v1.12.7 (PHP 8.5.11,
Caddy 2.11.4) was tested on Linux ARM64 with curl 8.5.0/nghttp2 1.59.0,
real MariaDB/WordPress and trusted isolated TLS. Nothing was installed globally.
The test used 2 PHP threads (maximum 4), OPcache INI memory 256 MB, five
endpoints, one initial request and 100 warm requests each at concurrency 8 and
16, for **1,005 requests per protocol**. All requests returned HTTP 200 and the
expected negotiated version, with no fatal server log signals.

Selected warm concurrency-16 results (single run; not a universal benchmark):

| Endpoint | h1 p95 ms | h2 p95 ms | h1 req/s | h2 req/s |
| --- | ---: | ---: | ---: | ---: |
| Dashboard | 39.220 | 16.929 | 1201.22 | 1007.13 |
| Static site | 38.732 | 9.431 | 1443.26 | 2032.54 |
| WordPress homepage | 303.836 | 421.738 | 56.65 | 49.84 |
| WordPress login | 144.495 | 149.715 | 142.43 | 134.72 |
| WordPress CSS asset | 37.976 | 11.030 | 1434.70 | 2406.70 |

Sampled process RSS peaks were 148.7 MiB (h1) and 147.9 MiB (h2). HTTP/2
helped static assets but regressed the WordPress high-concurrency p95 by about
39% and dashboard throughput by about 16%. These results do **not** justify
changing the default; repeat on supported installed stacks before enabling it
generally. HTTP/1.1 remains available with the opt-in.

The same real-process test verified save without restart, invalid settings
without mutation, explicit restart applying web INI settings, OPcache disabled
and unavailable service. This runtime reproducibly returned negative used
memory and a zero configured shared-cache limit even in a minimal standalone
PHP probe; those metrics now remain unknown with warnings rather than being
presented as valid measurements. Live shared-cache capacity validation remains
blocked by that runtime behavior; INI application is independently verified.
`plak health http2` only reports curl capability and negotiated protocol, not
performance. A client without HTTP2 support reports negotiation as unknown.

To reproduce the isolated automated evaluation (downloads WordPress; requires
MariaDB, PHP, WP-CLI, Python and an official FrankenPHP binary):

```sh
PLAK_LIVE_TESTS=1 PLAK_TEST_HEALTH=1 \
PLAK_TEST_FRANKENPHP=/path/to/frankenphp \
PLAK_HEALTH_RESULTS_DIR=/path/to/results bash tests/multisite-live.sh
```

The results directory contains per-request JSON, summaries, protocol probes,
versions, logs and the evaluated Caddyfile. On an installed stack:

1. Record `frankenphp version`, `curl --version`, platform, site and configuration.
2. Measure HTTP/1.1 on the dashboard, a static site and a representative WordPress
   site, recording errors and latency (warm and cold requests, concurrent load).
3. For evaluation only, set `HTTP2_ENABLED='1'` in `~/Plak/config` and run
   `plak reload`. This generates `protocols h1 h2`, retaining HTTP/1.1.
4. Repeat identical requests with `curl --http2`, verify `http_version=2`, and
   compare errors, latency and service logs. Example single-request probe:
   `curl --noproxy '*' -k --http2 -o /dev/null -w '%{http_version} %{time_total}\n' https://plak.localhost/`.
5. Restore `HTTP2_ENABLED='0'` and reload if compatibility or load checks fail.

Default enablement requires repeated acceptable installed-stack results, not
just protocol negotiation or fixture configuration checks.
