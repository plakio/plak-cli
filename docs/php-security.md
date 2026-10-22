# PHP runtime security (PHP2Shell, October 2026)

Plak serves local sites with PHP embedded in FrankenPHP. The Bash CLI, the
Homebrew `plak-cli` formula, `frankenphp version` and the host `php` are four
different things; none of them proves which PHP is serving a site. This page
records the advisory, the component matrix, how Plak selects and updates the
runtime, and how to verify the PHP that is actually executing.

## Advisory

On **2026-10-21** the PHP project published an out-of-cycle security release:

- [PHP security advisory: critical remote code execution, update now](https://www.php.net/archive/2026.php#2026-10-21-5)
- [CVE-2026-109618 — RCE via OOM corruption (GHSA-w8hw-w9fx-j79w)](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
- [CVE-2026-109619 — RCE via stale global state (GHSA-6wmf-4rv5-p3rp)](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp)
- [CISA alert, 2026-10-21](https://www.cisa.gov/news-events/alerts/2026/10/21/critical-vulnerabilities-php-require-immediate-patching)
- [CERT-EU advisory 2026-018](https://cert.europa.eu/publications/security-advisories/2026-018)

Both issues are rated **CVSS v4.0 9.2** and can give an unauthenticated
attacker remote code execution as the PHP worker. Fixed upstream releases:

| Branch | First fixed release | Affected |
| --- | --- | --- |
| PHP 8.5 | **8.5.12** | all earlier 8.5.x |
| PHP 8.4 | **8.4.27** | all earlier 8.4.x |
| PHP 8.3 | **8.3.36** | all earlier 8.3.x |
| PHP 8.2 | **8.2.35** | all earlier 8.2.x |
| PHP 8.1 and older | no upstream release | EOL; vendor backport only |

PHP 8.2 reaches end of life on 2026-12-31. The advisory says every PHP
installation serving web requests is at risk, **including FrankenPHP**. It
also warns that updating is the only complete mitigation.

- **CVE-2026-109618** interrupts PHP with `longjmp()` during out-of-memory
  handling while request data is only partly initialized. Apache `mod_php`
  unconditionally runs request shutdown and was exploited before application
  code runs. The advisory describes FrankenPHP as analogous to `mod_php` and
  therefore **likely susceptible to application-independent attacks**, although
  a complete FrankenPHP exploit was not demonstrated there. Controlled multipart
  parsing and an administratively enforced `memory_limit=-1` reduce exposure but
  are not complete mitigations.
- **CVE-2026-109619** leaves request-owned state reachable after its memory is
  freed; a later request on the same worker can consume it. Confirmed paths
  involve `session.upload_progress` and, on PHP 8.5, fatal error backtraces. The
  advisory did not establish an early configuration consumer in FrankenPHP's
  default configuration, but explicitly says this does not make FrankenPHP
  immune. `session.upload_progress.enabled=0` and `fatal_error_backtraces=0`
  block the confirmed paths only; they are not complete mitigations.

### Local sites are still reachable

Plak binds its admin surfaces to loopback and uses `.localhost` names, but
"local only" is not an isolation boundary. Local processes and a browser
visiting another page can send requests to loopback services. Do not treat a
Plak site as safe merely because it is not exposed to the internet. `plak lan`,
`plak share` and `plak tailscale` can expose sites beyond loopback.

## Does this apply to FrankenPHP and to Plak?

**Yes.** The advisory explicitly names FrankenPHP among the SAPIs that serve
web requests, alongside PHP-FPM, `mod_php`, `php-cgi` and LiteSpeed. The higher
demonstrated risk in `mod_php` does not exclude FrankenPHP. Plak's generated
Caddyfile uses `php_server` for every site and does **not** declare a `worker`
directive, so sites run through FrankenPHP's classic embedded web SAPI rather
than a persistent application worker script. The PHP process and its threads
still handle multiple requests, which is the "same worker" condition relevant
to CVE-2026-109619.

`plak wp`, the dashboard, Adminer and the history/database helpers invoke the
same binary through `frankenphp php-cli` (the CLI SAPI). That is the same
unpatched PHP code on disk, but it is not an HTTP request worker. The two
advisories are about the request lifecycle of a web SAPI, so they are not a
remote attack path through WP-CLI.

| Vulnerability | FrankenPHP web SAPI used by Plak sites | `frankenphp php-cli` / WP-CLI | FPM / CGI / `mod_php` | Concrete requirement and confidence |
| --- | --- | --- | --- | --- |
| **CVE-2026-109618** (OOM corruption) | **Affected in principle.** The advisory calls FrankenPHP analogous to `mod_php`, which runs request shutdown even when request startup failed, and says it is likely susceptible to application-independent attacks. Plak's defaults give the web process a finite `memory_limit=1G`, so the controllable OOM condition exists. | **Not applicable as a remote attack path.** The CLI SAPI has no HTTP request startup/parsing or request-shutdown lifecycle for an attacker to reach. The binary is still unpatched and must be updated for the web process. | Affected. `mod_php` is the demonstrated pre-application RCE; FPM is susceptible and application-level FPM exploitation was confirmed; `php-cgi` is named by the advisory. | An unauthenticated request must be able to make PHP hit the memory limit at the wrong point in request initialization (for example a multipart request without a usable length, many part headers, empty file controls or nested field names), before application code runs. No complete FrankenPHP exploit was published in the advisory; this is "affected, no demonstrated FrankenPHP exploit", not "not applicable". |
| **CVE-2026-109619** (stale global state) | **Affected in principle, exposure depends on the application and configuration.** The advisory says an equivalent early *INI-diagnostic* consumer was not established in FrankenPHP's default configuration, but that does not make it immune. The independent `session.upload_progress` consumer is enabled by default in the PHP build Plak ships, and PHP 8.5 also defaults `fatal_error_backtraces=1`. A producer (for example an attacker-reachable fatal error or OOM) and a consumer in a later request on the same thread are still required. | **Not applicable as a remote attack path.** It needs multiple HTTP requests handled by the same web worker; the CLI SAPI does not provide that attack surface. | Affected. `mod_php` has a confirmed fatal-backtrace RCE; FPM was validated with an application-level producer plus the session upload-progress consumer; `php-cgi`/LSAPI are named or modelled as candidates. | The attacker must reach a producer that leaves request-owned state published, then reach a consumer in a later request on the same worker before normal initialization resets it. No complete FrankenPHP exploit was demonstrated, but the composed session/fatal paths are the same primitives the advisory identifies. |
| **PHP CLI used by WP-CLI** | Not a web SAPI. | Same unpatched PHP binary, but neither CVE is a remote HTTP vector through `php-cli`. | Not applicable to CLI. | Updating the binary is still mandatory because the web SAPI is the exposure; a patched CLI proves the on-disk runtime is patched only when the web process has also been restarted. |

The distinction is therefore:

- **Affected but no demonstrated FrankenPHP exploit:** both CVEs for the web
  SAPI. CVE-2026-109618 has the stronger architectural analogy; CVE-2026-109619
  needs an application/config producer and consumer, and the advisory did not
  establish the INI consumer in default FrankenPHP.
- **Not applicable by architecture:** the two remote HTTP attack paths through
  `php-cli`/WP-CLI. The CLI is not a request worker.
- **Uncertain until the machine is inspected:** whether a particular Plak
  install has already restarted into a patched web process, and whether its
  sites/application code provide the producer/consumer chain for
  CVE-2026-109619. `plak health php` answers the runtime part; it does not
  perform an exploit test.

### Configuration contrast with Plak defaults

The PHP build Plak installs has these defaults before Plak's INI overrides
(measured with the official v1.13.1 static binary on Linux ARM64):

| Setting | PHP/FrankenPHP default | Plak web configuration |
| --- | --- | --- |
| `PHP_SAPI` | `cli` for `php-cli`; embedded web SAPI for sites | web SAPI for sites, `cli` for WP-CLI |
| ZTS | `1` | same binary |
| `memory_limit` | `128M` | **`1G`** (finite, so the controllable OOM path is present) |
| `post_max_size` | `8M` | **`1G`** |
| `upload_max_filesize` | `2M` | **`1G`** |
| `session.upload_progress.enabled` | `1` | not overridden; still `1` |
| `fatal_error_backtraces` (PHP 8.5) | `1` | not overridden; still `1` |

This is not an exploit test. It shows that Plak's defaults do not remove the
preconditions the advisory discusses; in particular its request-size limits are
much higher than the advisory's suggested 8M/32M. Do not change these blindly:
large uploads may be required by a site. Lower them only with the site owner's
approval and verify the application still works.

The advisory's date is not an exploitation condition: the release was published
on 2026-10-21 at 14:00 UTC after a pre-announcement on 2026-10-20. CISA said it
had not observed exploitation at publication; CERT-EU reported that PoCs were
circulating. Treat the runtime as exposed when it is reachable; do not infer
either safety or active compromise from the date alone.

## What runs PHP in Plak

| Component | Role | PHP runtime | What a security update requires |
| --- | --- | --- | --- |
| **Plak CLI** (`plak.sh`, `plak-cli` formula) | Bash + gum orchestration | none | Updating Plak does not patch PHP. This release adds the checks below. |
| **FrankenPHP static binary** (macOS and Linux) | Serves sites and provides `frankenphp php-cli` for WP-CLI | PHP 8.5.x embedded in the binary | Replace the binary with one built against PHP 8.5.12, then **restart** the service. |
| **FrankenPHP apt/dnf package** (official installer for Linux) | Same runtime at `/usr/bin/frankenphp` | PHP 8.5 ZTS from the package | Upgrade the package through apt/dnf; the package version may not change when PHP does. |
| **Homebrew `plak-cli`** | Installs only the Bash CLI and `gum` | none | `brew upgrade plak-cli` does not patch FrankenPHP or PHP. |
| **Host PHP** (`php`, `/usr/bin/php`, Homebrew `php`) | Not used by Plak to serve sites or run WP-CLI | whatever the host installed | Patching it does not patch the embedded runtime. `plak memory` lists it for auditing only. |
| **WP-CLI PHAR** | WordPress administration | none; runs under `frankenphp php-cli` | Update the FrankenPHP runtime, not the PHAR, for this CVE. |
| **Adminer, Whoops, dashboard PHP** | Local tools | run under the embedded runtime | Same runtime as the sites. |

FrankenPHP **v1.13.2** is the first release documented to ship static binaries
with PHP 8.5.12 and Docker images with PHP 8.2.35, 8.3.36, 8.4.27 and 8.5.12:
<https://github.com/php/frankenphp/releases/tag/v1.13.2>.

Release version numbers are **not** proof on their own. The v1.13.1 assets were
rebuilt on 2026-10-21 after the PHP release; a v1.13.1 binary downloaded on
2026-10-22 reports PHP 8.5.12, while the same version downloaded before the
rebuild reports 8.5.11. Always probe `PHP_VERSION` from the binary.

## Verify the effective PHP

```sh
# Read-only. Probes the embedded CLI PHP and the running web process.
plak health php
plak health php --json

# Direct probe of the runtime used for sites and WP-CLI.
frankenphp php-cli -r 'echo PHP_VERSION, " ", PHP_SAPI, PHP_EOL;'

# Per-site check through WP-CLI (uses the same embedded runtime).
plak wp my-site eval 'echo PHP_VERSION, " ", PHP_SAPI, PHP_EOL;'
```

`plak health php` returns:

| Exit | Meaning |
| --- | --- |
| 0 | The embedded PHP reports a fixed upstream version. |
| 1 | The embedded PHP is below the upstream floor. |
| 2 | A package-managed build is below the floor; a vendor backport is possible but cannot be verified locally. |
| 3 | The runtime could not be probed. |

`plak health --json` includes a `php_runtime` object with `binary`, `channel`,
`frankenphp_version`, `php_version`, `status`, `web_php_version`, `web_status`,
the advisory URL and the fixed versions.

### Do not confuse these versions

- `plak version` — the Bash CLI only.
- `frankenphp version` — the server; newer builds also print their PHP version,
  but parsing that string is not a substitute for probing.
- `frankenphp php-cli -r 'echo PHP_VERSION;'` — the PHP embedded in the binary
  used by sites, WP-CLI, Adminer and the dashboard.
- `php -v` — the host PHP, which Plak does not use for sites or WP-CLI.
- `plak health php` — compares the embedded CLI PHP with the running **web**
  process; an old web process after a binary update is not patched.

## Update and migration

### Static FrankenPHP (macOS, Linux)

```sh
plak upgrade
plak health php
```

`plak upgrade` now:

1. Probes the embedded `PHP_VERSION`, independently of the FrankenPHP version.
2. Updates through the owning channel (static asset, apt/dnf package or
   Homebrew formula) when PHP is not verified as fixed.
3. Downloads the platform asset with `--fail`, checks that it runs, and requires
   the embedded PHP to be at or above the fixed release **before** replacing
   the working binary.
4. Replaces the binary atomically, keeps the old one on any failure, and
   restarts the Plak service. A Caddy reload keeps the old PHP process; it is
   not a full restart.
5. Re-reads the web PHP probe and reports a mismatch or failure.

For static binaries the platform selection is:

- Linux x86_64/aarch64: the `-gnu` asset when glibc is 2.28 or newer, otherwise
  the musl asset.
- macOS Apple Silicon: `frankenphp-mac-arm64`.
- macOS Intel: v1.13.2 no longer publishes `frankenphp-mac-x86_64`. The v1.13.1
  assets were rebuilt with PHP 8.5.12 and are used as a validated fallback. This
  fixes PHP2Shell but does **not** include the FrankenPHP fixes from v1.13.2;
  build v1.13.2 from source with PHP 8.5.12 for full coverage.

If no runnable, patched artifact exists, `plak upgrade` stops without replacing
the binary and names the blocker. It does not claim that updating the CLI is
enough.

### Linux package

```sh
plak upgrade
# or, explicitly:
sudo apt-get update && sudo apt-get install --only-upgrade frankenphp
sudo dnf upgrade frankenphp
plak health php
```

The package can keep a version such as `1.13.2+php85-1` while the embedded PHP
changes. Plak therefore probes PHP and triggers a package update even when the
FrankenPHP version already equals the latest release. If the package still
reports a version below the floor, Plak reports `unverified` for a distribution
package: check the vendor's security notice, package changelog/build date and
USN/DSA/RHSA entry. A distribution backport can be fixed without a version bump,
so the version string alone is neither proof of vulnerability nor proof of a
fix.

### Homebrew

The `plakio/tap/plak-cli` formula installs only the Bash CLI and depends on
`gum`; it does not install PHP or FrankenPHP. `brew upgrade plak-cli` only
updates the CLI. If FrankenPHP itself is managed by a Homebrew formula on the
machine, update that formula as well and verify with `plak health php`.

## Interim mitigations

Only the fixed PHP release is a complete fix. The following reduce specific
paths and are **not** substitutes:

- For CVE-2026-109618: enforce `memory_limit=-1` administratively (not with an
  application override), use a low `post_max_size` (8M without uploads, 32M
  with uploads), keep `upload_max_filesize` below it, and bound decoded request
  size, multipart parts, headers and nesting at the server/proxy. Do not use
  `RLIMIT_AS`/`RLIMIT_DATA`.
- For CVE-2026-109619: set `session.upload_progress.enabled=0` and, on PHP 8.5,
  `fatal_error_backtraces=0` in the web process configuration, then restart
  every worker. Remove invalid/deprecated per-request INI settings that emit
  diagnostics before initialization.
- If neither is possible, stop serving the sites until the runtime is patched.
  Plak's loopback binding is not an isolation boundary.

Apply PHP INI changes to the configuration the web process actually loads (the
`php_ini` directives in `~/Plak/Caddyfile` and the INI file they reference), not
only to a shell profile, and verify with `plak health php` after a full restart.

## Evidence and limits

Verified locally on Linux ARM64 (Ubuntu 24.04, glibc 2.39) on 2026-10-22:

- Official `frankenphp-linux-aarch64` v1.13.2 reports PHP 8.5.12 and loads
  mysqli, curl, gd, xml, mbstring, zip, intl and bcmath.
- Official `frankenphp-linux-aarch64` v1.13.1
  (<https://github.com/php/frankenphp/releases/tag/v1.13.1>), downloaded after
  the rebuild, reports PHP 8.5.12; its GitHub asset timestamps are
  2026-10-21T15:41–16:52Z. This is why the version string alone is not used.
- `tests/php-security.sh` covers both sides of every fixed branch, prerelease
  and EOL strings, probing the embedded rather than host PHP, refusing a
  downloaded artifact with vulnerable PHP (old binary retained), failed
  downloads, the Intel macOS fallback, package updates at an equal FrankenPHP
  version, and the `plak upgrade` decision when only PHP is stale.

Not verified here: a real macOS run, a real Intel macOS binary, a live apt/dnf
vendor update, and exploitation behaviour. The advisory's FrankenPHP/`mod_php`
analogy is not a demonstrated FrankenPHP exploit. No exploit or request was
sent to a real site during this work.
