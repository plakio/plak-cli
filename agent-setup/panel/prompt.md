# Plak.io agent setup

You are installing Plak CLI, connecting this machine to the user's Plak.io
account, and verifying the connection. Follow these steps in order. Ask the
user before destructive actions or before changing remote resources.

## 1. Check the host

- Supported systems: macOS, Linux, and WSL2 on Windows.
- If this is native Windows rather than WSL, stop and tell the user to run the
  setup inside WSL2.
- macOS: `xcode-select -p` must succeed. If it fails, ask the user to run
  `xcode-select --install`, wait for it to finish, then continue.
- WSL: systemd must be enabled. If `pidof systemd` fails, stop and tell the
  user to add `[boot]` and `systemd=true` to `/etc/wsl.conf`, run
  `wsl --shutdown` from Windows, reopen WSL, and retry.
- Do not run the installer or `plak install` as root. Use `sudo` only when it
  prompts; the installer handles its own privileged steps.

## 2. Install Plak CLI and the local stack

Run exactly:

```bash
curl -fsSL https://plak.sh/install | PLAK_YES=1 bash
```

This installs the `plak` CLI, Homebrew on macOS when missing, and the local
stack: gum, FrankenPHP, MariaDB, Mailpit and WP-CLI.

If `sudo` asks for a password, ask the user to type it. Never store or echo
the password. If the installer fails, show the full error and stop. Do not
retry with `sudo bash` or bypass the installer's validation.

## 3. Verify the installation

```bash
plak version
plak status
```

`plak status` must show `found` for gum, frankenphp, mariadb, mailpit and wp.
For machine-readable output use `plak status --json`.

If a dependency is missing, run `plak install --yes`, then check
`plak status` again. Stop if the stack is still not ready.

## 4. Connect to the Plak panel

First check whether this machine is already connected:

```bash
plak connect status --json
```

If it reports `"connected":true`, reuse the existing connection and skip the
rest of this section.

Otherwise use the device flow:

```bash
plak connect --panel https://panel.plak.work --no-open
```

This prints an approval URL and a pairing code, then waits for the user to
approve the device in the panel. Show the URL and code to the user and keep
the command running until it finishes. Approving requires the user's action
in the panel; do not claim success before the command exits successfully.

If your harness cannot keep a long-running command alive, or the user cannot
use a browser, use the manual fallback:

```bash
echo "$PLAK_API_KEY" | plak connect --manual --panel https://panel.plak.work --token-stdin
```

The user creates the API key in the panel under Perfil > API Keys. Never pass
the key as a command argument, never echo it, and never write it to a file,
log or repository. If the user cannot provide a key, stop and explain both
options.

If the user has a custom panel origin (staging or self-hosted), use that URL
explicitly with `--panel`. Do not send a saved credential to a different
origin.

## 5. Verify the connection

```bash
plak connect status --json
```

Require `"connected":true`. Report the panel URL and the account name/email
from the JSON. If the token is invalid, expired or revoked, reconnect with
`plak connect`; do not try to repair or edit the stored credential manually.

## 6. Inspect the account

Read-only inventory:

```bash
plak panel sites --all --json
plak panel servers --all --json
```

Summarize the number of sites and servers, their names/domains, and the
servers' regions or status if present. Do not print tokens or secrets.

Do not run `plak panel create-*`, `delete-*`, `restart-*`, `link`, `pull` or
`push` unless the user explicitly asks. Those commands can change production
resources.

## 7. Ask what comes next

After reporting the connection and inventory, ask the user what they want to
do. Common next steps:

- Create a local WordPress site: `plak add <site-name>`, then
  `plak url <site-name>`.
- Link a panel site to a local site:
  `plak panel link <panel-site> <local-site>` only with explicit consent and
  the required SSH user/path/key details.
- Pull or push a site only with explicit consent and a clear description of
  the source and destination.

## 8. Report

Tell the user:

- the Plak version and local stack status,
- the connected panel URL and account,
- the panel sites and servers found,
- the next step they chose, or that nothing was changed.

## Safety rules

- Never log or expose API keys, tokens, passwords, SSH keys or one-time login
  URLs.
- Ask before changing panel, server, DNS, SSH, `/etc/hosts` or shell profile
  state.
- Never run destructive panel or server commands without an explicit request
  from the user.
- Keep existing sites, databases and remote resources untouched unless the
  user asks for a specific change.
