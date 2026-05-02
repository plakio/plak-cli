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

## Homebrew Releases

Plak's Homebrew formula is generated from `packaging/homebrew/plak.rb.template`.

After tagging a release, generate the formula for the tap with:

```bash
./scripts/homebrew_formula.sh 0.3.0 > /tmp/plak.rb
```

Then copy it to `plakio/homebrew-tap/Formula/plak.rb` and test it with Homebrew. See `docs/homebrew.md` for the full release flow.

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
