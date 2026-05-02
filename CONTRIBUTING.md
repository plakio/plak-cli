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
   bash -n main shared/* commands/* compile.sh install-plak.sh plak.sh
   ```

4. If available, run:

   ```bash
   shellcheck main shared/* commands/* compile.sh install-plak.sh
   shfmt -w main shared/* commands/* compile.sh install-plak.sh
   ./compile.sh
   ```

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
