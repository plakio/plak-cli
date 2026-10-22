# Homebrew Distribution

Plak is distributed through the `plakio/homebrew-tap` repository. Users install it with:

```bash
brew install plakio/tap/plak-cli
```

## Publication model

Publishing Plak CLI is **tag-driven**: the Git tag is the source of truth and the only release channel. There is no GitHub Release page in the flow.

1. `scripts/release.sh` bumps `PLAK_VERSION`, compiles, tests, commits, and pushes `main`.
2. It creates and pushes tag `v<version>`.
3. The tag starts `.github/workflows/notify-homebrew-tap.yml`, which dispatches `new-release` to the tap.
4. The tap downloads the tag archive, calculates its SHA-256, generates and tests the formula on macOS, and pushes the formula update.

The universal installer and `plak upgrade` are independent of this flow: both download `https://raw.githubusercontent.com/plakio/plak-cli/main/plak.sh`. Creating a GitHub Release page is not part of publishing a version and is not authorized by "publish a release"; it would be a separate, explicit editorial step after the tag and tap update.

Historical note: the `v0.4.67` GitHub Release page was removed when the project returned to tags-only. Tag `v0.4.67` and its source archive are unchanged.

## Automated Release Flow

Use `scripts/release.sh` from the `plak-cli` repository root. Only this repository needs to be cloned locally.

To auto-increment the patch version from `PLAK_VERSION`:

```bash
./scripts/release.sh --yes
```

To release an explicit version:

```bash
./scripts/release.sh 0.4.54 --yes
```

The script:

1. Updates `PLAK_VERSION`.
2. Compiles the Bash and Go distributions.
3. Validates shell syntax and runs smoke tests.
4. Commits the version bump and pushes `main`.
5. Creates and pushes tag `v<version>`.

The tag starts `.github/workflows/notify-homebrew-tap.yml`, which sends a `new-release` repository dispatch event to `plakio/homebrew-tap`. The tap then downloads the tag archive, calculates its SHA256, generates and tests the formula on macOS, and pushes the formula update.

The `plak-cli` repository requires an Actions secret named `TAP_DISPATCH_TOKEN`. It must be a fine-grained token limited to `plakio/homebrew-tap` with `Contents: Read and write` permission.

The tag is also the end of the publication step: no GitHub Release page is created or required. Publishing a version does not authorize creating one.

## Recovery

If the tag exists but the tap workflow did not start, resend the notification without creating another tag, release, or version:

```bash
gh workflow run notify-homebrew-tap.yml \
  --repo plakio/plak-cli \
  --field version=v0.4.54
```

Monitor the run with:

```bash
gh run list --repo plakio/homebrew-tap --workflow update-formula.yml
```

The release tag is the source of truth. Do not manually edit the formula before the tag exists. Do not create a GitHub Release page to trigger or accompany the update.
