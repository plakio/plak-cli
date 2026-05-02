#!/usr/bin/env bash

set -euo pipefail

version="${1:-}"
if [ -z "$version" ]; then
    echo "Usage: $0 <version>" >&2
    echo "Example: $0 0.3.0" >&2
    exit 1
fi

version="${version#v}"
repo_url="https://github.com/plakio/plak-cli/archive/refs/tags/v${version}.tar.gz"
template="packaging/homebrew/plak.rb.template"

if [ ! -f "$template" ]; then
    echo "Template not found: $template" >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required." >&2
    exit 1
fi

if ! command -v shasum >/dev/null 2>&1; then
    echo "shasum is required." >&2
    exit 1
fi

sha256=$(curl -fsSL "$repo_url" | shasum -a 256 | awk '{ print $1 }')

sed \
    -e "s/__VERSION__/${version}/g" \
    -e "s/__SHA256__/${sha256}/g" \
    "$template"
