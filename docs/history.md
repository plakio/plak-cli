# Component history and selective rollback

```sh
plak history demo save --note 'Before plugin updates'
plak history demo list
plak history demo show <id> plugins/woocommerce
plak history demo diff <from-id> current plugins/woocommerce
plak history demo restore <id> plugins/woocommerce --yes
plak history demo restore <id> mu-plugins/example.php --yes
```

All results are JSON (`--json` is also accepted). Paths are relative to the
standard `public/wp-content` directory and select a plugin/theme/MU component or
a file inside it. Restoring a component replaces its entire tree, including
removing files absent from the selected record. Restoring a historical absence
removes the selected current component. **Only intentionally selected paths are
changed.** A containing directory must already exist for a single-file restore.

## What gets saved

Immutable records live in `<site>/private/history/records`, outside the site's
public files and Git index. Each contains files and a JSON manifest: UTC date,
note, SHA-256 hashes, modes, versions and activation status from WP-CLI. Plugins,
themes and MU-plugins are included; symlinks are recorded without following their
targets. `.git` contents are excluded and their presence is recorded. A save
only publishes a record when files or component metadata changed; a different
note alone does not create another record. Changes observed during a save cause
an error instead of publishing a potentially mixed record.

Custom/external `WP_CONTENT_DIR` and linked content/storage roots are unsupported
and refused. This initial implementation copies all component files on each
changed save; **there is no automatic retention or pruning**. Plan disk space
accordingly. It does not snapshot uploads, core, config, caches or database data.

## Safety and reversibility

Every rollback saves the current state first and returns a `safety_id`. Restore
that record with the same selection to undo the rollback. An unchanged state can
reuse the latest history record as the safety record. Activation states are
recorded for comparison but **not restored**: changing them changes the database.
Use a full backup for updates involving database migrations.

Selections intersecting symlinks, nested Git repositories, or a checkout owning
`wp-content` are refused before writing. Use Git explicitly for development
checkouts; this command never checks out commits, resets a repository or changes
its index. It also refuses corrupted historical file hashes before replacement.

An advisory per-site lock excludes simultaneous history saves/restores. Other
programs (WP-CLI updates, editors, WordPress itself) do not honor that lock: pause
updates and edits during saves/restores. Atomic publication and a persistent
replacement journal protect against interruption, but this is not a guarantee
against power loss or failing storage. After an interrupted rollback:

```sh
plak history demo recover --yes
```

Recovery reinstates the selection's pre-rollback files. The pending journal
blocks other history actions until recovery succeeds; jobs remain inspectable.
Interrupted saves cannot appear as completed records. Hidden `.pending-*`
directories may remain after a killed process; inspect them before cleanup.

## Background jobs and explicit scheduling

```sh
plak history demo save --note 'Background save' --background
plak history demo restore <id> plugins/example --yes --background
plak history demo jobs
plak history demo schedule daily --enable
plak history demo schedule hourly --enable
plak history demo schedule --disable
```

Jobs record their log, exit code and status under `private/history/jobs`. Queued
work does not bypass the site lock: an overlapping job fails and exposes the
error, rather than silently overwriting another operation. Job status does not
take the save/restore lock. A process killed without an exit record can be shown
as interrupted when the runtime supports POSIX process checks.

Scheduling is **never enabled automatically**. These commands edit only the
invoking user's crontab entry bearing `# plak-history:<site>` and preserve other
entries. Do not run them with sudo. Daily saves run at 03:17 local time; hourly
saves at minute 17. The entry sets HOME and uses an absolute CLI path. Cron
delivers output/errors using the user's normal cron mail setup; background job
files are only for explicit `--background` invocations. Disabling is idempotent.

## History vs checkpoint vs vault

- `plak history`: component files and manifest, independent of site Git, selective
  rollback; no database backup.
- `_go checkpoint`: Git-based WordPress file checkpoint in the current site
  repository, including core/config paths; not independent component history.
- `_go vault`: restic backup using configured repository credentials, potentially
  with a database export; different storage/retention and recovery semantics.
- `plak snapshot`: full local site files plus database recovery point.

`bash tests/history.sh` covers no-op saves, version/file diffs, reversible
component/file restore, protected paths, corruption, locking, journal recovery,
background failures and user-crontab preservation. The opt-in multisite live test
also checks real WordPress metadata and a MU-file rollback in both modes.
