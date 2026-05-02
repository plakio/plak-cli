# Homebrew Distribution

Plak is distributed through a Homebrew tap.

## User Install

After the first tap release is published, users can install Plak with:

```bash
brew tap plak/plak-cli
brew install plak-cli
```

Or in one command:

```bash
brew install plak/plak-cli/plak-cli
```

## Tap Repository

Homebrew expects the tap repository to be named with a `homebrew-` prefix. For Plak, use:

```text
plak/homebrew-plak-cli
```

The tap should contain:

```text
Formula/plak-cli.rb
README.md
```

## Release Flow

1. Ensure `PLAK_VERSION` in `main` is a stable version, for example `0.3.0`.
2. Compile and test:

   ```bash
   ./compile.sh
   ./tests/smoke.sh
   ```

3. Merge the release changes into `main`.
4. Tag and push the release from `main`:

   ```bash
   git tag v0.3.0
   git push origin v0.3.0
   ```

5. Generate the Homebrew formula:

   ```bash
   ./scripts/homebrew_formula.sh 0.3.0 > /tmp/plak-cli.rb
   ```

6. Copy `/tmp/plak-cli.rb` into the tap repository:

   ```text
   plak/homebrew-plak-cli/Formula/plak-cli.rb
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
   git commit -m "plak-cli 0.3.0"
   git push origin main
   ```

## Formula Template

The source template lives at:

```text
packaging/homebrew/plak-cli.rb.template
```

It is intentionally checked in as a template because Homebrew requires a real release tarball SHA256. The generated `Formula/plak-cli.rb` belongs in `plak/homebrew-plak-cli`, not this source repository.
