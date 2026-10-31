#!/usr/bin/env bash

# shellcheck disable=SC2016  # grep patterns intentionally match literal $ and `

# Release tooling contract: publishing is tag-driven.
#
# These checks guard the documented flow: a version bump on main, a pushed
# v<version> tag, the Homebrew tap update, and a notes-only GitHub Release.
# The release script itself must not create release pages or delete tags; a
# separate workflow creates the notes page from the tag. The universal
# installer and plak upgrade must install only from stable tags (never main
# or releases/latest).

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

WORKFLOW=".github/workflows/notify-homebrew-tap.yml"
NOTES_WORKFLOW=".github/workflows/release-notes.yml"
STABLE_API="api.github.com/repos/plakio/plak-cli/tags"

fail() {
    echo "release tooling test failed: $1" >&2
    exit 1
}

# The skill installer must fetch the skill from the binary's release tag, not
# from main; otherwise an old Homebrew binary can receive a newer skill.
grep -Fq 'plak-cli/v${PLAK_VERSION}/skills/plak-cli' commands/skill \
    || fail "skill installer does not match the binary release tag"

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
grep -Fq 'Homebrew tap update' <<<"$help_output" \
    || fail "release.sh help does not mention the Homebrew tap update"
grep -Fq 'GitHub Release notes workflow' <<<"$help_output" \
    || fail "release.sh help does not mention the release notes workflow"
grep -Fq 'Does not create the GitHub Release page locally' <<<"$help_output" \
    || fail "release.sh help does not keep release-page creation out of the script"

# The tap is notified by a tag push, never by a GitHub Release event.
grep -Fq 'tags:' "$WORKFLOW" || fail "$WORKFLOW does not trigger on tags"
grep -Fq 'push:' "$WORKFLOW" || fail "$WORKFLOW does not trigger on pushes"
if grep -Eq '^[[:space:]]+(release|releases):' "$WORKFLOW"; then
    fail "$WORKFLOW triggers on release events"
fi

# A separate tag-triggered workflow creates the notes-only GitHub Release.
[ -f "$NOTES_WORKFLOW" ] || fail "$NOTES_WORKFLOW is missing"
grep -Fq 'tags:' "$NOTES_WORKFLOW" || fail "$NOTES_WORKFLOW does not trigger on tags"
grep -Fq 'contents: write' "$NOTES_WORKFLOW" || fail "$NOTES_WORKFLOW lacks contents: write"
grep -Fq 'gh release create' "$NOTES_WORKFLOW" || fail "$NOTES_WORKFLOW does not create a release"
grep -Fq -- '--generate-notes' "$NOTES_WORKFLOW" || fail "$NOTES_WORKFLOW does not generate notes"
grep -Fq -- '--notes-start-tag' "$NOTES_WORKFLOW" || fail "$NOTES_WORKFLOW does not anchor notes to the previous tag"
grep -Fq 'gh release view' "$NOTES_WORKFLOW" || fail "$NOTES_WORKFLOW is not idempotent"

# The universal installer and plak upgrade use the stable tag channel, never
# main or releases/latest. Both must resolve tags and stage atomically.
for file in install.sh shared/release; do
    grep -Fq "$STABLE_API" "$file" || fail "$file does not call the tags API"
done
for file in install.sh commands/site/upgrade; do
    grep -Fq 'plak_release_resolve_latest_tag' "$file" || fail "$file does not resolve a stable tag"
    grep -Fq 'plak_release_validate_script' "$file" || fail "$file does not validate the downloaded script"
    grep -Fq 'mktemp' "$file" || fail "$file does not use mktemp"
    if grep -Eq 'raw\.githubusercontent\.com/plakio/plak-cli/(main|master)/plak\.sh' "$file"; then
        fail "$file still downloads main/plak.sh"
    fi
    if grep -Eq 'github\.com/plakio/plak-cli/releases/latest|raw\.githubusercontent\.com/plakio/plak-cli/main/plak\.sh' "$file"; then
        fail "$file still downloads from main or releases/latest"
    fi
    if grep -Fq '/tmp/plak.sh.latest' "$file"; then
        fail "$file still uses the fixed /tmp/plak.sh.latest path"
    fi
done
grep -Fq 'plak_release_script_url' commands/site/upgrade \
    || fail "plak upgrade does not download from the selected tag"

# The upgrade helper runs under `if !`, which suppresses `set -e` inside it:
# every staging step (including chmod) must be checked explicitly, or a failed
# chmod would swap in a non-executable file while reporting success.
if grep -Eq '^[[:space:]]*chmod [^|&]*"\$temp_script"' commands/site/upgrade; then
    fail "plak upgrade has an unchecked chmod on the staged script"
fi
grep -Fq 'if ! chmod 755 "$temp_script"' commands/site/upgrade \
    || fail "plak upgrade does not check the staging chmod explicitly"

# The tag artifact is compiled before the tag exists, so Homebrew (tag archive)
# and the universal channel (tag plak.sh) receive the same release source.
compile_line=$(grep -n '^\./compile\.sh$' scripts/release.sh | head -n1 | cut -d: -f1)
tag_line=$(grep -n '^git tag "\$TAG"$' scripts/release.sh | head -n1 | cut -d: -f1)
[ -n "$compile_line" ] || fail "scripts/release.sh does not run ./compile.sh"
[ -n "$tag_line" ] || fail "scripts/release.sh does not create the release tag"
[ "$compile_line" -lt "$tag_line" ] || fail "scripts/release.sh tags before compiling plak.sh"

# The documentation keeps the same contract.
grep -Fq 'Publishing is **tag-driven**' CONTRIBUTING.md \
    || fail "CONTRIBUTING.md does not define publishing as tag-driven"
grep -Fq 'A GitHub Release page is generated for notes' CONTRIBUTING.md \
    || fail "CONTRIBUTING.md does not describe the notes-only GitHub Release"
grep -Fq 'not a distribution trigger' CONTRIBUTING.md \
    || fail "CONTRIBUTING.md treats the GitHub Release as a distribution trigger"
grep -Fq 'never fall back to `main`' CONTRIBUTING.md \
    || fail "CONTRIBUTING.md does not rule out a main fallback"
grep -Fq 'A GitHub Release page is generated automatically for notes' docs/homebrew.md \
    || fail "docs/homebrew.md does not describe the notes-only GitHub Release"
grep -Fq 'not a distribution channel' docs/homebrew.md \
    || fail "docs/homebrew.md treats the GitHub Release as a distribution channel"
grep -Fq 'Stable channel selection rules' docs/homebrew.md \
    || fail "docs/homebrew.md does not document stable tag selection"
grep -Fq 'no fallback to `main`' docs/homebrew.md \
    || fail "docs/homebrew.md does not rule out a main fallback"
grep -Fq 'PLAK_INSTALL_URL' docs/homebrew.md \
    || fail "docs/homebrew.md does not document the explicit installer override"

echo "Release tooling checks passed."
