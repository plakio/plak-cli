# FrankenPHP CLI compatibility

FrankenPHP **1.13.0 / PHP 8.5** regresses script arguments: the binary occupies
`$argv[0]`, the script moves to `$argv[1]`, and WP-CLI rejects its own PHAR as a
command. Plain PHP scripts are affected too, not just PHARs or WSL. Reproduced
with official static and extracted DEB binaries on Linux ARM64. 1.12.7 with the
same PHP 8.5.11 and conventional php-zts execute the arguments correctly.

Upstream [#2690](https://github.com/php/frankenphp/issues/2690) was fixed by
[#2691](https://github.com/php/frankenphp/pull/2691) on 2026-10-10; as checked
2026-10-12 the latest published release is still 1.13.0. A merged upstream fix
is not a tested installed runtime. Do not downgrade to avoid the bug blindly:
1.13.0 also contains security fixes. No runtime/package upgrade is performed by
Plak's compatibility selection.

## Selection

Working FrankenPHP builds remain direct: `frankenphp php-cli <wp-phar> ...`.
For 1.13.0, Plak first probes actual script `$argv`, `$argc` and server copies,
so a downstream backport/native CLI implementation can remain direct. If the
probe detects the shift, Plak selects only an executable sibling `php-zts`
whose actual script probe matches the runtime fingerprint: exact PHP version,
ZTS, integer size, loaded/scanned INI, extension set (excluding the embedding
module `frankenphp-cli`) and key configuration values. Both inherit Plak's
`PHPRC`; differing configuration/extensions reject the fallback.

This is the CLI frontend from the **same FrankenPHP distribution**, not an
arbitrary `php` on PATH. For packaged installations, inspect the matching
`php-zts-cli` package supplied by the FrankenPHP repository. Plak never installs
it silently. Static builds without a matched companion fail actionably before
new site/database creation; use a validated runtime containing the upstream
fix. No generic independent PHP is selected automatically.

The shared resolver is also used by DB-list and component-history child WP
processes. `plak wp` still uses `exec`, preserving quoting, standard streams,
signals and return statuses.

## Rejected alternatives

- `-f`/`--`: tested, still shifted on 1.13.0.
- PHP 8.6 upgrade: the string about versions lower than 8.6 concerns unsupported
  emulation modes with no script/eval code (e.g. bare `-i`/`-v`); it does not
  establish WordPress's need for PHP8.6. PHP8.6 was not tested here.
- Argv-only shim: WP-CLI PHAR self-subprocesses use `PHP_BINARY`, also incorrect
  in this emulation. Fixing `core download` alone would not fix those operations.
- Unreleased upstream build/system upgrade: not silently installed or assumed
  compatible. Prefer a tested released fix when available.

## Test matrix / limits

Deterministic tests cover direct/backported builds, matched/missing/mismatched
companions, empty/quoted/metacharacter arguments, streams and exit status.
Live tests opt in to isolated PHP/WordPress/MariaDB operations; no existing
sites/databases/host trust stores are used. Actual WSL2/Ubuntu26.04 and Windows
browser/network/trust acceptance remain separate manual validation.
