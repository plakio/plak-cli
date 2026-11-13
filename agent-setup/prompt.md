# Plak agent setup

You are installing Plak CLI and creating a local WordPress site. Follow these
steps in order. Ask the user before destructive actions.

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
