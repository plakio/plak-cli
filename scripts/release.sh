#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  ./scripts/release.sh <version> [options]

Example:
  ./scripts/release.sh 0.4.0

Options:
  --yes, -y         Skip confirmation prompt
  --help, -h        Show this help

What this does:
  1. Updates PLAK_VERSION in main
  2. Compiles plak.sh and go.sh, then runs smoke tests
  3. Commits "Release <version>"
  4. Pushes main, tags v<version>, and pushes the tag
  5. The tag triggers the automated Homebrew tap update
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

ASSUME_YES=false
VERSION=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes|-y)
            ASSUME_YES=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        -*)
            die "Unknown option: $1"
            ;;
        *)
            # Non-option arguments (version or extra args)
            if [ -z "$VERSION" ]; then
                VERSION="$1"
                shift
            else
                die "Unexpected argument: $1"
            fi
            ;;
    esac
done

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
fi

VERSION="${VERSION#v}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "Invalid version: $VERSION (expected X.Y.Z)."
fi

TAG="v$VERSION"

require_cmd git

BRANCH=$(git branch --show-current)
[ "$BRANCH" = "main" ] || die "Run releases from main (current branch: $BRANCH)."

require_clean_repo "$REPO_ROOT" "plak-cli"

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
(cd go && ./compile.sh)
bash -n main shared/* shared/site/* commands/* commands/site/* compile.sh install.sh plak.sh go/main go/shared/* go/commands/* go/compile.sh go/go.sh
./tests/smoke.sh

if [ -n "$(git status --short)" ]; then
    git add main plak.sh go/go.sh
    git commit -m "Release $VERSION"
else
    echo "==> No version changes to commit."
fi

RELEASE_COMMIT=$(git rev-parse --short HEAD)
confirm "Release $VERSION from commit $RELEASE_COMMIT?"

echo "==> Pushing main"
git push origin main

echo "==> Creating and pushing tag $TAG"
git tag "$TAG"
git push origin "$TAG"

echo "==> Release $VERSION complete; GitHub Actions will update the Homebrew tap."
