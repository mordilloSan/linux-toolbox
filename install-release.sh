#!/usr/bin/env bash
set -euo pipefail

if ((EUID != 0)); then
    echo "Run with sudo: sudo ./install-release.sh" >&2
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
install -Dm644 "$script_dir/release.mk" /usr/local/include/release.mk

echo "Installed release.mk globally."
