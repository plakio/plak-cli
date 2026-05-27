# Homebrew Distribution

Plak is distributed through a Homebrew tap.

## User Install

After the first tap release is published, users can install Plak with:

```bash
brew tap plakio/plak-cli
brew install plak-cli
```

Or in one command:

```bash
brew install plakio/plak-cli/plak-cli
```

## Tap Repository

Homebrew expects the tap repository to be named with a `homebrew-` prefix. For Plak, use:

```text
plakio/homebrew-plak-cli
```

The tap should contain:

```text
Formula/plak-cli.rb
README.md
```

## Release Flow

Use `scripts/release.sh` from the `plak-cli` repository root. The script is the source of truth for releases and handles both GitHub and Homebrew.

### Before releasing

1. Make and validate your code changes.
2. Commit the functional change first:

   ```bash
   git add <files>
   git commit -m "Describe the change"
   ```

3. Ensure both repositories are on `main` and clean:

   ```bash
   git status --short --branch
   git -C ../homebrew-plak-cli status --short --branch
   ```

The release script intentionally refuses to run with dirty working trees.

### Recommended command

To auto-increment the patch version from `PLAK_VERSION` in `main`:

```bash
./scripts/release.sh --yes
```

For example, if `main` contains `PLAK_VERSION="0.4.30"`, this releases `0.4.31`.

To release an explicit version:

```bash
./scripts/release.sh 0.4.31 --yes
```

To also test the generated Homebrew formula locally:

```bash
./scripts/release.sh 0.4.31 --brew-test --yes
```

If the tap repository is not at `../homebrew-plak-cli`, pass it explicitly:

```bash
./scripts/release.sh 0.4.31 --tap-dir /path/to/homebrew-plak-cli --yes
```

### What the script does

`release.sh` performs the full release:

1. Determines the release version, auto-incrementing patch if no version is provided.
2. Updates `PLAK_VERSION` in `main`.
3. Runs `./compile.sh` to regenerate `plak.sh`.
4. Validates shell syntax and runs `./tests/smoke.sh`.
5. Commits the version bump as `Release <version>`.
6. Pushes `main` to `plakio/plak-cli`.
7. Creates and pushes tag `v<version>`.
8. Generates the Homebrew formula from the published tag.
9. Copies the formula into `homebrew-plak-cli/Formula/plak-cli.rb`.
10. Commits and pushes the Homebrew tap update.

Do not manually edit the Homebrew formula before the CLI release tag exists. The release tag is the source of truth for the tarball URL and SHA256.

### Manual flow, only if needed

Prefer `scripts/release.sh`. If you must recover or release manually: 

1. Ensure `PLAK_VERSION` in `main` is a stable version, for example `0.4.31`.
2. Compile and test:

   ```bash
   ./compile.sh
   ./tests/smoke.sh
   ```

3. Merge the release changes into `main`.
4. Tag and push the release from `main`:

   ```bash
   git push origin main
   git tag v0.4.31
   git push origin v0.4.31
   ```

5. Generate the Homebrew formula:

   ```bash
   ./scripts/homebrew_formula.sh 0.4.31 > /tmp/plak-cli.rb
   ```

6. Copy `/tmp/plak-cli.rb` into the tap repository:

   ```text
   plakio/homebrew-plak-cli/Formula/plak-cli.rb
   ```

7. In the tap repository, test locally:

   ```bash
   brew install --build-from-source ./Formula/plak-cli.rb
   brew test ./Formula/plak-cli.rb
   brew uninstall plak-cli
   ```

8. Commit and push the tap update:

   ```bash
   git add Formula/plak-cli.rb
   git commit -m "plak-cli 0.4.31"
   git push origin main
   ```

## Formula Template

The source template lives at:

```text
packaging/homebrew/plak-cli.rb.template
```

It is intentionally checked in as a template because Homebrew requires a real release tarball SHA256. The generated `Formula/plak-cli.rb` belongs in `plakio/homebrew-plak-cli`, not this source repository.
