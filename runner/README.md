# Plak Runner

Plak Runner is the portable shell runtime used by Plak to execute WordPress
operations in local or remote environments.

The public endpoint should serve the compiled script:

```bash
https://plak.sh/runner
```

Expected usage:

```bash
curl -sL https://plak.sh/runner | bash -s -- backup <path> --quiet
curl -sL https://plak.sh/runner | bash -s -- migrate --url=<backup.zip> --update-urls
```

For now this directory is a scaffold. `backup` and `migrate` are command
placeholders and should not be wired into `plak pull` or `plak push` until the
implementation is ported.

## Build

Run from this directory:

```bash
./compile.sh
```

The output is:

```text
runner/runner.sh
```
