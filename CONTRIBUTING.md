# Contributing to Plak

Plak is now a Bash + gum CLI. Source files are modular, and `compile.sh` generates the single distributable `plak.sh` script.

## Setup

Install dependencies:

```bash
./plak.sh install
```

Useful optional development tools:

```bash
brew install shellcheck shfmt
```

## Workflow

1. Edit `main`, `shared/*`, or `commands/*`.
2. Compile:

   ```bash
   ./compile.sh
   ```

3. Validate syntax:

   ```bash
   bash -n main shared/* commands/* compile.sh install.sh plak.sh
   ```

4. If available, run:

   ```bash
   shellcheck main shared/* commands/* compile.sh install.sh
   shfmt -w main shared/* commands/* compile.sh install.sh
   ./compile.sh
   ```

## Releases

Use `scripts/release.sh` from the repository root. Commit functional changes first, then run:

```bash
./scripts/release.sh --yes
```

This auto-increments the patch version from `PLAK_VERSION`, compiles `plak.sh`, runs smoke tests, commits the release bump, pushes `main`, creates and pushes the GitHub tag, generates the Homebrew formula from that tag, and pushes the tap update.

For an explicit version:

```bash
./scripts/release.sh 0.4.31 --yes
```

For local Homebrew formula testing during release:

```bash
./scripts/release.sh 0.4.31 --brew-test --yes
```

Both `plak-cli` and `../homebrew-tap` must be on `main` with clean working trees. Do not edit the Homebrew formula manually before the CLI release tag exists. See `docs/homebrew.md` for details and manual recovery steps.

## Safety

- Do not edit `/etc/hosts` without a backup.
- Prefer `mktemp` for temporary files.
- Keep destructive commands behind `gum confirm`.
- Test hosts and SSH config changes with temporary files when possible.

## Commit Messages

Use conventional commits when practical:

- `feat`: new feature
- `fix`: bug fix
- `docs`: documentation
- `refactor`: internal cleanup
- `test`: test coverage
- `chore`: tooling or maintenance
