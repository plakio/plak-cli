# Linux database listing and browser trust

`plak db list [--json]` uses mysqli, not PDO. Each site's real wp-config.php
supplies its database name, credentials and host/port/socket; connection and
query failures are errors on stderr with a nonzero exit status, not empty lists.
SQL schema names are bound parameters. `bash tests/db-linux.sh` exercises a real
isolated MariaDB query with PDO disabled when the required tools are installed.

Run `plak trust` **without sudo**, with Plak running. Only the system trust step
escalates privileges. NSS writes use the invoking user's HOME, covering:

- Shared Chromium NSS databases (`~/.pki`, `~/.local/share/pki`).
- Native Firefox profiles (`~/.mozilla/firefox`).
- Snap profiles under `~/snap`.
- Flatpak profiles under `~/.var/app`.

Existing cert9.db (SQL) and cert8.db (legacy DBM) profiles are detected. Plak/Caddy
managed nicknames are replaced with the current local root, retaining unrelated
certificates. Missing certutil or a locked/unwritable profile is reported and
prevents a total-success result. Restart browsers after changing trust.
`tests/trust-nss-live.sh` also creates real isolated NSS databases in the seven
profile layouts, verifies CA rotation, idempotence, preservation of unrelated
roots and an unwritable-profile failure. It runs when certutil is available
(or set `PLAK_TEST_CERTUTIL` to a temporary extracted binary). Installed browser
behavior still requires checking after restart.
