# Agent setup

Public agent setup guides for Plak products. The files live here, next to the
CLI they install, so the instructions change with the CLI behavior. The public
URLs are stable redirects served from each product site.

| Public URL | Source file |
| --- | --- |
| `https://plak.sh/agent-setup/prompt.md` | [`cli/prompt.md`](cli/prompt.md) |
| `https://plak.io/agent-setup/prompt.md` | [`panel/prompt.md`](panel/prompt.md) |

## Redirects

`plak.sh`:

```text
/agent-setup/prompt.md  https://raw.githubusercontent.com/plakio/plak-cli/main/agent-setup/cli/prompt.md  302
/agent-setup/           /agent-setup/prompt.md                                                            302
```

`plak.io`:

```text
/agent-setup/prompt.md  https://raw.githubusercontent.com/plakio/plak-cli/main/agent-setup/panel/prompt.md  302
/agent-setup/           /agent-setup/prompt.md                                                                302
```

When more documents are added, a wildcard can replace the per-file rules:

```text
plak.sh/agent-setup/*  ->  raw .../agent-setup/cli/:splat
plak.io/agent-setup/*  ->  raw .../agent-setup/panel/:splat
```

## Adding a product

Create `agent-setup/<product>/prompt.md` and add a redirect from the product's
`/agent-setup/prompt.md` to that file on `main`. Keep the public path the same
across products; the domain selects the onboarding.
