# plak

Plak CLI is a small Bash + [gum](https://github.com/charmbracelet/gum) tool for managing everyday local developer SSH tasks:

- SSH server aliases in `~/.ssh/config`
- Local domain entries in `/etc/hosts`
- SSH keys in `~/.ssh`

It follows a Cove-style structure: modular source files are compiled into a single distributable `plak.sh` script.

## Requirements

- Bash
- `gum`
- `ssh` and `ssh-keygen`
- `sudo` for writing to `/etc/hosts` when needed

## Installation

After the Homebrew tap is published, install Plak with:

```bash
brew tap plakio/plak-cli
brew install plak-cli
```

For local development, Plak can also install/check `gum` with Homebrew:

```bash
./plak.sh install
```

## Development

Compile the distributable script:

```bash
./compile.sh
```

Run locally:

```bash
./plak.sh status
./plak.sh server list
```

Run smoke tests:

```bash
./tests/smoke.sh
```

Install the local compiled script as `plak`:

```bash
./install-plak.sh --dev
```

See [docs/homebrew.md](docs/homebrew.md) for release and tap maintenance.

## Project Structure

```text
main              # globals, help, OS detection, command router
shared/           # shared UI and validation helpers
commands/         # command modules
compile.sh        # builds plak.sh
plak.sh           # compiled distributable script
install-plak.sh   # local installer
```

## Commands

```bash
plak status
plak version
plak install
```

### SSH Servers

```bash
plak server list
plak server add
plak server connect
plak server delete
```

### Domains

```bash
plak domain list
plak domain add
plak domain delete
```

`domain add/delete` creates a timestamped backup next to the hosts file before writing. On `/etc/hosts`, this usually requires `sudo`.

### SSH Keys

```bash
plak sshkey list
plak sshkey view [key-name-or-path]
plak sshkey create
plak sshkey delete
```

## Notes

- Interactive commands require a real terminal because `gum` opens TUI prompts.
- Non-interactive list/status commands fall back to plain output for scripts and tests.
- `plak.sh` is generated from `main`, `shared/`, and `commands/`.
