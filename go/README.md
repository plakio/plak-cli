# Plak CLI Go

Plak CLI Go is the portable shell runtime used by Plak to execute WordPress
operations on remote servers without installing Plak CLI there.

The public endpoint should serve the compiled script:

```bash
https://plak.sh/go
```

Expected usage:

```bash
alias _go='curl -sL https://plak.sh/go | bash -s'

_go help
_go backup <path> --quiet
_go convert-to-webp wp-content/uploads --install-cwebp
_go db backup
_go db check-autoload
_go find slow-plugins
_go login admin --raw
_go migrate --url=<backup.zip> --update-urls
```

## Alias Installation

For the current shell session:

```bash
alias _go='curl -sL https://plak.sh/go | bash -s'
```

For a persistent zsh alias:

```bash
printf "\nalias _go='curl -sL https://plak.sh/go | bash -s'\n" >> ~/.zshrc
source ~/.zshrc
```

For a persistent bash alias:

```bash
printf "\nalias _go='curl -sL https://plak.sh/go | bash -s'\n" >> ~/.bashrc
source ~/.bashrc
```

The alias runs Plak CLI Go remotely through `curl | bash`; it does not install
Plak CLI on the server.

## Commands

```text
backup <path>
checkpoint <create|list|show|revert|latest>
clean <plugins|themes|disk>
convert-to-webp [path]
cron <list|add|delete|run>
db <backup|check-autoload|optimize>
dump <pattern>
email
find <recent-files|slow-plugins|hidden-plugins|malware|php-tags>
https
login <user>
migrate --url=<backup.zip>
monitor <errors|access.log|error.log|traffic>
reset <permissions|wp>
suspend <activate|deactivate>
update <all|list>
vault <create|snapshots|info|prune>
version
wpcli check
zip <path>
```

Plak CLI Go avoids provider-specific behavior and does not install global
services. Optional tools such as `cwebp` are installed locally only when an
explicit install flag is passed.

## Recoverable migrations

`migrate` never leaves the destination database empty or half-imported. Before
the first destructive step it snapshots the existing database and records a
state file in the site's private directory, then resets and imports. If the
import fails, or the imported database cannot be verified, the snapshot is
restored automatically. If the process is interrupted, the next run refuses to
start and points at the recovery material; restore it with:

```bash
_go migrate --recover
```

A temporary-database swap is not used because shared hosts frequently withhold
`CREATE DATABASE`, so the pre-reset snapshot is the portable contract. Recovery
material is only discarded once the replacement is confirmed.

## Build

Run from this directory:

```bash
./compile.sh
```

The output is:

```text
go/go.sh
```
