# Plak Go

Plak Go is the portable shell runtime used by Plak to execute WordPress
operations in local or remote environments.

The public endpoint should serve the compiled script:

```bash
https://plak.sh/go
```

Expected usage:

```bash
curl -sL https://plak.sh/go | bash -s -- backup <path> --quiet
curl -sL https://plak.sh/go | bash -s -- migrate --url=<backup.zip> --update-urls
```

## Build

Run from this directory:

```bash
./compile.sh
```

The output is:

```text
go/go.sh
```
