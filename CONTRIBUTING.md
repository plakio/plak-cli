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

This auto-increments the patch version from `PLAK_VERSION`, compiles `plak.sh`, runs smoke tests, commits the release bump, pushes `main`, and creates and pushes the GitHub tag. The tag triggers the automated Homebrew tap update.

Publishing is **tag-driven**: the Git tag is the source of truth and the only release channel.

1. `scripts/release.sh` pushes the version bump to `main` and pushes tag `v<version>`.
2. The tag starts `.github/workflows/notify-homebrew-tap.yml`.
3. That workflow dispatches the update to `plakio/homebrew-tap`.

`scripts/release.sh` compiles `plak.sh` before creating the tag, so the tag archive used by Homebrew and the `plak.sh` downloaded by the stable channel contain the same compiled release source.

`scripts/release.sh` does **not** create a GitHub Release page, and "publish a version" does not authorize creating one. GitHub Releases are not needed by Homebrew, the universal installer (`install.sh`, served by `https://plak.sh/install`) or `plak upgrade`. Homebrew builds from the tag archive; the installer and `plak upgrade` resolve the newest stable `vMAJOR.MINOR.PATCH` tag from the GitHub tags API and download `plak.sh` from that exact tag. They never fall back to `main` or `releases/latest`. See the stable channel section in `docs/homebrew.md`. If a GitHub Release page is ever wanted for editorial notes, it is a separate, explicitly authorized step after the tag and the tap update, and it must not be treated as the publication trigger.

For an explicit version:

```bash
./scripts/release.sh 0.4.31 --yes
```

Only `plak-cli` needs to be cloned locally. It must be on `main` with a clean working tree. Do not edit the Homebrew formula manually before the CLI release tag exists. See `docs/homebrew.md` for automation and recovery details.

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
