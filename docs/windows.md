# Windows onboarding (WSL2 + Ubuntu 24.04)

Plak runs inside **WSL2 with Ubuntu 24.04 LTS** on Windows. Docker is **not**
required. Docker Desktop is a separate tool and creates its own
`docker-desktop` distribution; Plak does not use it.

The planned one-line bootstrapper is tracked in
[plakio/plak-cli#80](https://github.com/plakio/plak-cli/issues/80):

```powershell
irm https://plak.sh/install.ps1 | iex
```

Until that ships, use the manual flow below. It is also the fallback if the
bootstrapper cannot run.

## 1. Enable WSL2

Open **PowerShell as Administrator** only if `VirtualMachinePlatform` is
disabled:

```powershell
Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
```

Reboot Windows. Do not continue while a reboot is pending. After rebooting:

```powershell
wsl --status
wsl --list --verbose
Get-Service vmcompute
```

## 2. Install Ubuntu 24.04

Use the web download to avoid Microsoft Store failures:

```powershell
wsl --update
wsl --install -d Ubuntu-24.04 --web-download --no-launch
wsl --set-default-version 2
wsl --list --verbose
```

`VERSION` must be `2`. If `Ubuntu-24.04` fails, retry with `Ubuntu` or
`Ubuntu-22.04` and report the real error. Do not switch to Debian or another
distribution without an explicit decision.

## 3. Prepare Ubuntu

Open Ubuntu from the Start menu or with `wsl -d Ubuntu-24.04`. The first launch
asks for a Linux username and password. Use a normal user; do **not** run Plak
as root.

Inside Ubuntu:

```bash
ps -p 1 -o comm=
id -u
cat /etc/wsl.conf
```

- `ps -p 1 -o comm=` must print `systemd`.
- `id -u` must not be `0`.
- If systemd is missing, add:

  ```ini
  [boot]
  systemd=true
  ```

  Then run `wsl --shutdown` from PowerShell, reopen Ubuntu, and recheck.

Install the missing base tools:

```bash
sudo apt-get update
sudo apt-get install -y python3 openssh-client curl ca-certificates
```

## 4. Install Plak

Run inside Ubuntu, as the normal user:

```bash
curl -fsSL https://plak.sh/install | PLAK_YES=1 bash
plak version
plak status --json
```

Do not pass PowerShell here-strings to Bash. Run the commands in the WSL shell;
CRLF line endings produce `bash\r: command not found`.

## 5. Create a site and trust the certificate

```bash
plak add demo --static
plak list
plak url demo
plak trust
```

`plak trust` must run **without sudo**; it escalates only the system trust step.
In WSL it also imports the Caddy root into the current Windows user store.
If `*.localhost` does not resolve in Windows, run:

```bash
plak wsl-hosts
```

Verify the site in Edge or Chrome. The Codex embedded browser may not use the
Windows trust store and can still show `ERR_CERT_AUTHORITY_INVALID`; that does
not mean the Windows browser is untrusted.

## 6. Cold start

After a Windows reboot or `wsl --shutdown`, start Ubuntu and wait for the
services before opening the site:

```bash
wsl -d Ubuntu-24.04
systemctl is-active plak mariadb mailpit
```

If a service is inactive, run `plak enable` and check again.

## Common errors

| Error | Cause | Fix |
|---|---|---|
| `The requested operation requires elevation` | PowerShell is not Administrator | Reopen PowerShell as Administrator |
| WSL shows no distribution | WSL is installed but Ubuntu is not | `wsl --install -d Ubuntu-24.04 --web-download` |
| Ubuntu install fails | Store/network | `wsl --update`, retry with `--web-download` |
| `bash\r: command not found` | CRLF script sent from PowerShell | Run commands inside Bash/WSL |
| `python3 is required for plak connect` | Minimal Ubuntu image | `sudo apt-get install -y python3` |
| `ssh: command not found` | No OpenSSH client | `sudo apt-get install -y openssh-client` |
| APT cannot read `static-php85.asc` | `umask 077` during FrankenPHP install | Re-run `plak install --yes`; Plak now normalizes the keyring permissions |
| Browser shows certificate warning | Windows does not trust the WSL CA yet | `plak trust`; restart the browser |
| Site fails after reboot | Ubuntu/services were stopped | Start Ubuntu, `systemctl is-active plak mariadb mailpit` |

## Panel note

A panel account with zero servers has no deployment target. Promo/redeem codes
do not provision servers; a server purchase requires an offer and the account
holder's approval/payment. Sandbox sites are a separate service and can be
created without a server.
