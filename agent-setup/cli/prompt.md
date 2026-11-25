# Plak agent setup

You are installing Plak CLI and creating a local WordPress site. Follow these
steps in order. Ask the user before destructive actions.

## 1. Check the host

- Supported systems: macOS, Linux, and WSL2 on Windows. On Windows, Plak runs
  inside WSL2 with **Ubuntu 24.04 LTS**. Docker is not required.
- Native Windows preferred: run the Windows bootstrapper:
  `irm https://plak.sh/install.ps1 | iex`. It may prompt for UAC, reboot
  Windows, and open Ubuntu to create the first Linux user; hand those
  interactive steps to the user. If it returns 404, use the manual steps below.
  Never run the Linux installer directly on native Windows. If the harness
  cannot survive a reboot, ask the user to rerun this onboarding afterwards.
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

On native Windows, the bootstrapper in section 1 already installed Plak inside
Ubuntu. Do not run the command below in PowerShell; skip to section 3 and run
the verification commands inside Ubuntu, for example:
`wsl -d Ubuntu-24.04 -- bash -lc 'plak version'`.

If the bootstrapper stopped before installing Plak, open Ubuntu and run the
command there.

On macOS, Linux and WSL, run exactly:

```bash
curl -fsSL https://plak.sh/install | PLAK_YES=1 bash
```

This installs the `plak` CLI, Homebrew on macOS when missing, and the local
stack: gum, FrankenPHP, MariaDB, Mailpit and WP-CLI.

If `sudo` asks for a password, ask the user to type it. Never store or echo
the password. If the installer fails, show the full error and stop. Do not
retry with `sudo bash` or bypass the installer's validation.

If the user only wants the CLI, use `PLAK_CLI_ONLY=1`; a local site cannot be
created until the stack is installed.

## 3. Verify the installation

```bash
plak version
plak status
```

`plak version` must report `0.4.78` or newer. `plak status` must show `found`
for gum, frankenphp, mariadb, mailpit and wp. For machine-readable output use
`plak status --json`.

If a dependency is missing, run:

```bash
plak install --yes
```

Then check `plak status` again. Stop if the stack is still not ready.

## 4. Create the WordPress site

If the user did not give a site name, ask for one. Valid names are 1-63
lowercase letters, numbers or hyphens, and cannot start or end with a hyphen.
Do not reuse or overwrite an existing site: check `plak list` first.

```bash
plak add <site-name>
```

This creates `~/Plak/Sites/<site-name>.localhost` and prints the admin user,
password and one-time login URL. Treat the password and login URL as secrets.

On WSL, after creating the site, run `plak trust` (without sudo) and, if
`*.localhost` does not resolve, `plak wsl-hosts`. Verify in Edge/Chrome; the
Codex embedded browser may not use the Windows trust store. After a Windows
reboot or `wsl --shutdown`, start Ubuntu and wait for
`systemctl is-active plak mariadb mailpit` before opening the site.

## 5. Verify the site

```bash
plak list
plak url <site-name>
plak status
```

Open the printed URL or give it to the user. The dashboard is
`https://plak.localhost`. If the site is not listed or the URL does not
resolve, stop and report the commands and errors.

## 6. Report

Tell the user:

- the Plak version and site name,
- the site URL and dashboard URL,
- the admin user and one-time login URL, marked as sensitive,
- how to stop and start the stack with `plak disable` and `plak enable`.

If the one-time login URL expires, `plak login <site-name>` generates a new
one.

## Safety rules

- Never run `plak delete`, `rm -rf`, database drops, migrations, or pull/push
  against remote servers unless the user explicitly asks.
- Never put passwords, tokens or login URLs in a repository or log.
- Ask before changing system services, `/etc/hosts`, or shell profiles.
- Keep existing sites and data untouched.
