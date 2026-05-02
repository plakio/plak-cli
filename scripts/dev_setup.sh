#!/usr/bin/env bash

set -euo pipefail

if ! command -v gum >/dev/null 2>&1; then
    echo "gum is required. Installing/guiding through Plak installer..."
    ./plak.sh install
fi

./compile.sh

echo "Development setup complete. Run ./plak.sh status to verify."
