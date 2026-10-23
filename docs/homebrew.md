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

The universal installer (`install.sh`, served by `https://plak.sh/install`) and `plak upgrade` are independent of the Homebrew flow, but they publish from the same Git tags. Both use the **stable channel**:

1. Resolve the newest stable tag from the GitHub tags API (`https://api.github.com/repos/plakio/plak-cli/tags`).
2. Download `https://raw.githubusercontent.com/plakio/plak-cli/<tag>/plak.sh` for that exact tag.
3. Validate that the file is the compiled Bash script, that its embedded `PLAK_VERSION` matches the tag, and that it reports `plak v<version>`.
4. Stage it on the destination filesystem and rename it into place only after validation.

A download, API, or validation failure leaves the current executable untouched. There is deliberately **no fallback to `main` and no `releases/latest` lookup**.

### Stable channel selection rules

- Only `vMAJOR.MINOR.PATCH` tags are eligible. The highest numeric version wins, regardless of the order returned by the API.
- Prereleases (`-rc1`, `-beta`), build metadata (`+build`), tags without the `v` prefix, non-semver names, and tags with leading zeroes are ignored.
- The tag and the embedded `PLAK_VERSION` must match. A mismatch is an error.
- Network failures, API errors, rate limits, missing tags, invalid or incomplete downloads, and permission-setting (chmod/staging) failures stop with an actionable message. They never install `main` or an arbitrary commit, and they do not silently fall back to an older tag when the selected tag's artifact is missing or invalid.
- `GITHUB_TOKEN` or `GH_TOKEN` is used when present to raise the unauthenticated GitHub API rate limit. The token is only sent to `api.github.com`.
- Downloads and staging use `mktemp` with unique names. Downloads are mode 0600 and the installed script is mode 0755. Temporary files are removed on success, error, and interruption; concurrent runs do not share paths.
- `PLAK_INSTALL_URL` remains an explicit override for tests and advanced/offline use. It is not the stable channel and does not trigger an implicit fallback.

The resolver and installer use Bash 3.2-compatible constructs and tools available on Linux and macOS. The default install location is unchanged: `/usr/local/bin` on Linux and `/opt/homebrew/bin` on macOS arm64, unless `PLAK_INSTALL_DIR` is set.

Homebrew and the universal channel deliver the same code for the same tag: Homebrew downloads the tag archive and runs `compile.sh`; the universal channel downloads the committed `plak.sh` from that tag. `scripts/release.sh` compiles and commits `plak.sh` before creating the tag, so both artifacts come from the same compiled source.

Creating a GitHub Release page is not part of publishing a version and is not authorized by "publish a release"; it would be a separate, explicit editorial step after the tag and tap update.

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
