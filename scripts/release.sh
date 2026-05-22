#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  ./scripts/release.sh <version> [options]

Example:
  ./scripts/release.sh 0.4.0

Options:
  --tap-dir PATH    Path to homebrew-plak-cli (default: ../homebrew-plak-cli)
  --brew-test       Run brew install/test/uninstall against the generated formula
  --yes, -y         Skip confirmation prompt
  --help, -h        Show this help

What this does:
  1. Updates PLAK_VERSION in main
  2. Compiles plak.sh and runs smoke tests
  3. Commits "Release <version>"
  4. Pushes main, tags v<version>, and pushes the tag
  5. Generates the Homebrew formula from the published tag
  6. Commits and pushes the tap update
USAGE
}

die() {
    echo "Error: $*" >&2
    exit 1
}

confirm() {
    local message="$1"
    if [ "$ASSUME_YES" = true ]; then
        return 0
    fi
    if [ ! -t 0 ]; then
        die "$message (run with --yes to continue non-interactively)"
    fi
    printf "%s [y/N] " "$message"
    local reply
    read -r reply
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) die "Release cancelled." ;;
    esac
}

require_clean_repo() {
    local repo_dir="$1" label="$2"
    if [ -n "$(git -C "$repo_dir" status --short)" ]; then
        git -C "$repo_dir" status --short >&2
        die "$label working tree is not clean."
    fi
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "'$1' is required."
}

VERSION="${1:-}"
if [[ "${VERSION:-}" == "--help" || "${VERSION:-}" == "-h" ]]; then
    usage
    exit 0
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

# Auto-increment version if not provided
if [ -z "$VERSION" ]; then
    if [ -f main ]; then
        CURRENT_VERSION=$(grep 'PLAK_VERSION=' main | sed 's/PLAK_VERSION="\([^"]*\)"/\1/')
        if [ -n "$CURRENT_VERSION" ]; then
            IFS='.' read -r major minor patch <<< "$CURRENT_VERSION"
            patch=$((patch + 1))
            VERSION="${major}.${minor}.${patch}"
            echo "==> Auto-incrementing version: $CURRENT_VERSION -> $VERSION"
        else
            die "Could not determine current PLAK_VERSION from 'main'"
        fi
    else
        die "'main' file not found. Provide version explicitly: ./scripts/release.sh <version>"
    fi
else
    shift  # Consume the version argument
fi

VERSION="${VERSION#v}"
TAP_DIR=""
RUN_BREW_TEST=false
ASSUME_YES=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tap-dir)
            [ "$#" -ge 2 ] || die "--tap-dir requires a path."
            TAP_DIR="$2"
            shift 2
            ;;
        --brew-test)
            RUN_BREW_TEST=true
            shift
            ;;
        --yes|-y)
            ASSUME_YES=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    die "Version must look like 0.4.0 or v0.4.0."
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

TAP_DIR="${TAP_DIR:-$REPO_ROOT/../homebrew-plak-cli}"
TAG="v$VERSION"

require_cmd git
require_cmd curl
require_cmd shasum

[ -d "$TAP_DIR/.git" ] || die "Tap repository not found at: $TAP_DIR"
[ -f "$TAP_DIR/Formula/plak-cli.rb" ] || die "Tap formula not found at: $TAP_DIR/Formula/plak-cli.rb"

BRANCH=$(git branch --show-current)
[ "$BRANCH" = "main" ] || die "Run releases from main (current branch: $BRANCH)."

TAP_BRANCH=$(git -C "$TAP_DIR" branch --show-current)
[ "$TAP_BRANCH" = "main" ] || die "Tap repo must be on main (current branch: $TAP_BRANCH)."

require_clean_repo "$REPO_ROOT" "plak-cli"
require_clean_repo "$TAP_DIR" "homebrew-plak-cli"

git fetch origin --tags
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    die "Local tag already exists: $TAG"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    die "Remote tag already exists: $TAG"
fi

echo "==> Preparing Plak $VERSION"
RELEASE_VERSION="$VERSION" perl -0pi -e 's/PLAK_VERSION="[^"]+"/PLAK_VERSION="$ENV{RELEASE_VERSION}"/' main

./compile.sh
bash -n main shared/* shared/site/* commands/* commands/site/* compile.sh install.sh plak.sh
./tests/smoke.sh

if [ -n "$(git status --short)" ]; then
    git add main plak.sh
    git commit -m "Release $VERSION"
else
    echo "==> No version changes to commit."
fi

RELEASE_COMMIT=$(git rev-parse --short HEAD)
confirm "Release $VERSION from commit $RELEASE_COMMIT and update Homebrew tap?"

echo "==> Pushing main"
git push origin main

echo "==> Creating and pushing tag $TAG"
git tag "$TAG"
git push origin "$TAG"

echo "==> Generating Homebrew formula from published tag"
TMP_FORMULA=$(mktemp)
trap 'rm -f "$TMP_FORMULA"' EXIT

generated=false
for attempt in 1 2 3 4 5; do
    if ./scripts/homebrew_formula.sh "$VERSION" > "$TMP_FORMULA"; then
        generated=true
        break
    fi
    echo "Formula generation failed; retrying in $((attempt * 2))s..."
    sleep $((attempt * 2))
done
$generated || die "Failed to generate Homebrew formula for $TAG."

cp "$TMP_FORMULA" "$TAP_DIR/Formula/plak-cli.rb"

if [ "$RUN_BREW_TEST" = true ]; then
    require_cmd brew
    echo "==> Testing Homebrew formula"
    (
        cd "$TAP_DIR"
        brew install --build-from-source ./Formula/plak-cli.rb
        brew test ./Formula/plak-cli.rb
        brew uninstall plak-cli
    )
fi

if [ -n "$(git -C "$TAP_DIR" status --short)" ]; then
    echo "==> Committing tap update"
    git -C "$TAP_DIR" add Formula/plak-cli.rb
    git -C "$TAP_DIR" commit -m "plak-cli $VERSION"
    git -C "$TAP_DIR" push origin main
else
    echo "==> Tap formula already up to date."
fi

echo "==> Release $VERSION complete."
