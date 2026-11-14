# Service status versus WordPress readiness

`plak status` checks services. Running FrankenPHP/MariaDB/Mailpit does not prove
that PHP scripts or WP-CLI work. Use the existing diagnostics command:

```sh
plak health wordpress
plak health wordpress --json
```

This read-only, 20-second-bounded probe selects the shared compatible runtime,
executes a real PHP script with space/empty arguments, checks global/server
argv/argc, required mysqli/curl/dom/mbstring/zip/Phar extensions, then runs WP-CLI
`cli info` outside any site with its global config disabled. It does not download
WordPress, create databases, change trust, or load website plugins. GNU `timeout`
(or `gtimeout` on macOS) is required to guarantee the time bound.

JSON reports readiness, failing phase, exit code, selected runtime and missing
extensions. External probe stderr is not dumped because user configuration may
contain secrets. This checks CLI prerequisites, not MariaDB credentials,
WordPress release/network availability, DNS/TLS or web PHP readiness; those are
separate checks. PHP8.6 is not presumed necessary.

During provisioning, original WP-CLI errors remain visible and the failing
process exit code is preserved through owned-resource rollback. The extra
message identifies the operation without printing command arguments/passwords
or assuming every failure is a missing release/network problem. If WP-CLI
reports success but leaves missing files, Plak still fails and rolls back.
