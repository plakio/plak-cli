#!/usr/bin/env bash

# Release tooling contract: publishing is tag-driven.
#
# These checks guard the documented flow: a version bump on main, a pushed
# v<version> tag, and the Homebrew tap update. The release tooling must not
# create GitHub Release pages, must not delete tags, and must not make the
# universal installer or plak upgrade depend on tags or releases.

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

WORKFLOW=".github/workflows/notify-homebrew-tap.yml"
MAIN_SCRIPT_URL="raw.githubusercontent.com/plakio/plak-cli/main/plak.sh"

fail() {
    echo "release tooling test failed: $1" >&2
    exit 1
}

# The release script must not create release pages or remove tags.
for forbidden in \
    'gh release' \
    '--cleanup-tag' \
    'git tag -d' \
    'git push --delete' \
    ':refs/tags'; do
    if grep -Fq -- "$forbidden" scripts/release.sh; then
        fail "scripts/release.sh contains '$forbidden'"
    fi
done

# The help text states the contract explicitly.
help_output=$(./scripts/release.sh --help)
grep -Fq 'Does not create a GitHub Release page: the tag is the publication channel' <<<"$help_output" \
    || fail "release.sh help does not state that no GitHub Release page is created"
grep -Fq 'Homebrew tap update' <<<"$help_output" \
    || fail "release.sh help does not mention the Homebrew tap update"

# The tap is notified by a tag push, never by a GitHub Release event.
grep -Fq 'tags:' "$WORKFLOW" || fail "$WORKFLOW does not trigger on tags"
grep -Fq 'push:' "$WORKFLOW" || fail "$WORKFLOW does not trigger on pushes"
if grep -Eq '^[[:space:]]+(release|releases):' "$WORKFLOW"; then
    fail "$WORKFLOW triggers on release events"
fi

# The universal installer and plak upgrade track main, not tags or releases.
grep -Fq "$MAIN_SCRIPT_URL" install.sh \
    || fail "install.sh does not download main/plak.sh"
grep -Fq "$MAIN_SCRIPT_URL" commands/site/upgrade \
    || fail "plak upgrade does not download main/plak.sh"

# The documentation keeps the same contract.
grep -Fq 'Publishing is **tag-driven**' CONTRIBUTING.md \
    || fail "CONTRIBUTING.md does not define publishing as tag-driven"
grep -Fq 'does **not** create a GitHub Release page' CONTRIBUTING.md \
    || fail "CONTRIBUTING.md does not rule out GitHub Release pages"
grep -Fq '"publish a version" does not authorize creating one' CONTRIBUTING.md \
    || fail "CONTRIBUTING.md does not separate publishing from GitHub Releases"
grep -Fq 'There is no GitHub Release page in the flow.' docs/homebrew.md \
    || fail "docs/homebrew.md does not rule out GitHub Release pages"
grep -Fq 'Creating a GitHub Release page is not part of publishing a version' docs/homebrew.md \
    || fail "docs/homebrew.md does not separate publishing from GitHub Releases"

echo "Release tooling checks passed."
