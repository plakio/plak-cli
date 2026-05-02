#!/usr/bin/env bash

set -euo pipefail

DEV_MODE=false
for arg in "$@"; do
    case "$arg" in
        --dev) DEV_MODE=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

os_name=$(uname -s)
install_dir="/usr/local/bin"
sudo_cmd="sudo"

if [ "$os_name" = "Darwin" ]; then
    if [ "$(uname -m)" = "arm64" ]; then
        install_dir="/opt/homebrew/bin"
    fi
    sudo_cmd=""
elif [ "$(id -u)" -eq 0 ]; then
    sudo_cmd=""
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_script="$script_dir/plak.sh"
destination="$install_dir/plak"

if [ "$DEV_MODE" = true ]; then
    if [ ! -f "$source_script" ]; then
        echo "plak.sh not found. Run ./compile.sh first." >&2
        exit 1
    fi
else
    echo "Only --dev install is available in this scaffold." >&2
    echo "Run: ./compile.sh && ./install-plak.sh --dev" >&2
    exit 1
fi

if [ ! -d "$install_dir" ]; then
    $sudo_cmd mkdir -p "$install_dir"
fi

$sudo_cmd cp "$source_script" "$destination"
$sudo_cmd chmod +x "$destination"

echo "Installed Plak to $destination"
