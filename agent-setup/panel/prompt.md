# Plak.io agent setup

You are installing Plak CLI and the local Plak stack, connecting this machine
to the user's Plak.io account, and verifying the connection and scopes. Follow
these steps in order. Ask the user before destructive actions, before changing
remote resources, and before requesting purchase capability.

## 1. Check the host

- Supported systems: macOS, Linux, and WSL2 on Windows. On Windows, Plak runs
  inside WSL2 with **Ubuntu 24.04 LTS**. Docker is not required.
- Native Windows preferred: run the Windows bootstrapper:
  `irm https://plak.sh/install.ps1 | iex`. If that URL is not available yet
  (404), use the manual steps below. Never run the Linux installer directly on
  native Windows.
- Native Windows manual fallback: prepare WSL2 first:
  1. From PowerShell, check `wsl --status`, `wsl --list --verbose` and
     `Get-Service vmcompute`.
  2. If `VirtualMachinePlatform` is disabled or no distribution exists, ask
     the user to open PowerShell as Administrator and run:
     `Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform`
     and, when disabled,
     `Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart`.
     Reboot Windows. Do not continue until the reboot is complete; if the
     harness cannot survive a reboot, ask the user to rerun this onboarding
     afterwards.
  3. Install Ubuntu from the web (avoids Microsoft Store failures):
     `wsl --update`
     `wsl --install -d Ubuntu-24.04 --web-download --no-launch`
     `wsl --set-default-version 2`
     `wsl --list --verbose`
     If it fails, retry with `Ubuntu` or `Ubuntu-22.04`. Do not switch to
     Debian or another distribution without explicit user consent.
  4. Open Ubuntu and verify `ps -p 1 -o comm=` is `systemd` and `id -u` is not
     0. If systemd is missing, add `[boot]` and `systemd=true` to
     `/etc/wsl.conf`, run `wsl --shutdown` from Windows, reopen Ubuntu and
     retry. If only root exists, help the user create a normal Linux user and
     run Plak as that user. Never run the installer as root.
  5. Install prerequisites inside Ubuntu:
     `sudo apt-get update && sudo apt-get install -y python3 openssh-client curl ca-certificates`.
  6. Run the installer inside Ubuntu. Run Bash commands in the WSL shell, not
     as PowerShell here-strings; CRLF causes `bash\r: command not found`.
  7. After the bootstrapper finishes, run every `plak` command inside Ubuntu,
     never in native PowerShell. For example:
     `wsl -d Ubuntu-24.04 -- bash -lc 'plak version'`.
- macOS: `xcode-select -p` must succeed. If it fails, ask the user to run
  `xcode-select --install`, wait for it to finish, then continue.
- WSL: systemd must be enabled. If `pidof systemd` fails, use the `/etc/wsl.conf`
  fix above and restart WSL.
- Docker is not required for Plak. Do not install Docker Desktop for this
  onboarding unless the user explicitly asks for an unrelated workshop tool.
- Do not run the installer or `plak install` as root. Use `sudo` only when it
  prompts; the installer handles its own privileged steps.

## 2. Install Plak CLI and the local stack

Run exactly:

```bash
curl -fsSL https://plak.sh/install | PLAK_YES=1 bash
```

This installs the `plak` CLI, Homebrew on macOS when missing, and the local
stack: gum, FrankenPHP, MariaDB, Mailpit and WP-CLI.

This full install is intentional: `plak add` creates sites locally and needs
FrankenPHP, MariaDB, Mailpit and WP-CLI. Do not use `PLAK_CLI_ONLY=1` for this
onboarding unless the user explicitly says they do not want local sites.

If `sudo` asks for a password, ask the user to type it. Never store or echo
the password. If the installer fails, show the full error and stop. Do not
retry with `sudo bash` or bypass the installer's validation.

## 3. Verify the installation

```bash
plak version
plak status
```

`plak version` must report `0.4.90` or newer. That version is required for
`plak connect --billing` and the server purchase flow. If it is older, run
`plak upgrade` or repeat the installer before continuing.

`plak status` must show `found` for gum, frankenphp, mariadb, mailpit and wp.
For machine-readable output use `plak status --json`.

If a dependency is missing, run `plak install --yes`, then check
`plak status` again. Stop if the stack is still not ready.

## 4. Connect to the Plak panel

First inspect the existing connection:

```bash
plak connect status --json
```

It reports the granted `scopes` and `billing_granted`. Decide with the user
whether this machine should be able to request server purchases:

- Normal setup: `user:read` + `ssh:authorize`; browsing is allowed, buying is not.
- Purchase setup: additionally `billing:request`; the holder still approves
  and pays for every purchase in the browser.

If it reports `"connected":true`, reuse the connection only when it has the
scopes the user needs. Do not silently replace an existing credential. If the
user wants to buy servers and `billing_granted` is not true, explain the two
options:

1. Reconnect with the device flow using `--billing`. This replaces the saved
   credential, so warn that any `servers:write`/`sites:write` scopes from a
   manual key would be lost.
2. Connect a manual API key that includes every scope the user needs. This is
   the safer option when the current connection already has write scopes.

Otherwise use the device flow:

```bash
plak connect --panel https://cloud.plak.io --no-open
# If the user wants to request server purchases:
plak connect --panel https://cloud.plak.io --no-open --billing
```

This prints an approval URL and a pairing code, then waits for the user to
approve the device in the panel. Show the URL and code to the user and keep
the command running until it finishes. Approving requires the user's action
in the panel; do not claim success before the command exits successfully.

On the approval page, if the user wants purchases, make sure the optional
`billing:request` checkbox is checked. It is checked by default when the
device requested it, but the user can uncheck it. If it is denied, the
connection still works for read/SSH but cannot buy servers.

If your harness cannot keep a long-running command alive, or the user cannot
use a browser, use the manual fallback. The user must create the API key and
run this command themselves; never ask them to paste the key into the chat:

```bash
printf '%s\n' "$PLAK_API_KEY" | plak connect --manual --panel https://cloud.plak.io --token-stdin
```

The key is created in the panel under Perfil > API Keys. It needs at least
`user:read`; add `billing:request` for purchases, `servers:write` and/or
`sites:write` for panel writes, and `ssh:authorize` for panel link. Never pass
the key as a command argument, never echo it, and never write it to a file,
log or repository. If the user cannot provide a key, stop and explain both
options.

If the user has a custom panel origin (staging or self-hosted), use that URL
explicitly with `--panel`. Do not send a saved credential to a different
origin.

## 5. Verify the connection and scopes

```bash
plak connect status --json
```

Require `"connected":true`. Report the panel URL, account name/email, `scopes`
and `billing_granted`. If the user requested purchase capability, require
`billing_granted:true`; otherwise do not claim the machine can buy servers and
explain the reconnect/manual-key options.

If the token is invalid, expired or revoked, reconnect with `plak connect`;
do not try to repair or edit the stored credential manually.

## 6. Install the agent skill

Ask which harness the user is using, then install the matching Plak agent
skill so future sessions know the CLI and purchase safety contract:

```bash
plak skill install <codex|claude-code|opencode|hermes|pi|global>
```

Use `global` for a generic skill or when the harness is unknown. This only
writes the skill file; it does not change the panel. If the user does not want
it, skip it and mention that it can be installed later with `plak skill install`.

## 7. Inspect the account

Read-only inventory:

```bash
plak panel sites --all --json
plak panel servers --all --json
```

Summarize the number of sites and servers, their names/domains, and the
servers' regions or status if present. Do not print tokens or secrets.

If the inventory has zero servers, do not claim a deployment is possible.
Promo/redeem codes do not provision infrastructure; buying a server requires an
offer and the account holder's explicit approval and payment.

Do not run `plak panel create-*`, `delete-*`, `restart-*`, `buy-server`,
`link`, `pull` or `push` unless the user explicitly asks. Those commands can
create purchase requests or change production resources. `offers`,
`purchase-request` and `purchases` are read-only or local and may be used to
inspect the purchase catalog/status.

## 8. Ask what comes next

After reporting the connection and inventory, ask the user what they want to
do. Common next steps:

- Create a local site now: ask for the name and type first. WordPress:
  `plak add <name> --agent`; static HTML: `plak add <name> --static`. Verify
  with `plak list` and `plak url <name>`; for WordPress, report the admin user
  and one-time login URL as secrets. `--agent` prepares WP-MCP and the HTML
  Editor.
  On WSL, after creating the site, run `plak trust` (without sudo) and, if
  `*.localhost` does not resolve, `plak wsl-hosts`. Verify in Edge/Chrome; the
  Codex embedded browser may not use the Windows trust store. After a Windows
  reboot or `wsl --shutdown`, start Ubuntu and wait for
  `systemctl is-active plak mariadb mailpit` before opening the site.
- A local site is not a panel server: `plak add` uses this machine's stack,
  while `plak panel buy-server` requests a remote server in the panel and
  requires the holder's approval/payment.
- Link a panel site to a local site:
  `plak panel link <panel-site> <local-site>` only with explicit consent and
  the required SSH user/path/key details.
- Buy a server, only when the user explicitly asks:
  ```bash
  plak panel offers
  plak panel buy-server --offer ID --region ID --name NAME
  ```
  The CLI creates a purchase request and prints the internal approval URL.
  Give it to the account holder; they approve and pay in the browser. Never
  approve or pay for them, never open or complete a Polar checkout with agent
  credentials, never ask for card data, and never treat `--yes` as financial
  approval. Check with `plak panel purchase-request <id>` or
  `plak panel purchases`. If the status is `manual_review` or
  `provisioning_unknown`, stop and check the panel/support; never create
  another purchase. Use `--new` only after a terminal `failed`/`cancelled`
  request or an expired `pending_approval`/`approved`/`checkout_open`
  request; never for `paid`, `provisioning`, ambiguous, or unresolved states.
- Pull or push a site only with explicit consent and a clear description of
  the source and destination.

## 9. Report

Tell the user:

- the Plak version and local stack status,
- the connected panel URL, account, scopes and whether purchases are available,
- whether the agent skill was installed,
- the panel sites and servers found,
- the local site created, if any, with its URL and dashboard,
- the next step they chose, or that nothing was changed.

## Safety rules

- Never log or expose API keys, tokens, passwords, SSH keys or WordPress
  one-time login URLs. The pairing approval URL is not a reusable credential:
  show it only to the user in this session and never send it to third parties,
  log it or commit it.
- Never approve or pay for a purchase on the user's behalf. Never open or
  complete a Polar checkout with agent credentials, never ask for card data,
  and never treat `--yes` as financial approval.
- Never create a purchase request (`buy-server`) without an explicit request
  from the user. `billing:request` only requests purchases and reads status;
  it cannot approve or pay.
- Never retry a purchase with a new idempotency key. Re-run the same command or
  use `purchase-request <id>`; never create a second purchase.
- Ask before changing panel, server, DNS, SSH, `/etc/hosts` or shell profile
  state.
- Never run destructive panel or server commands without an explicit request
  from the user.
- Keep existing sites, databases and remote resources untouched unless the
  user asks for a specific change.
