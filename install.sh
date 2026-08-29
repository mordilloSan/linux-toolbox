#!/usr/bin/env bash
set -euo pipefail

if ((EUID == 0)); then
    echo "Run this installer as your regular user, not with sudo." >&2
    exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

sudo bash "$script_dir/install-dependencies.sh"
sudo bash "$script_dir/install-go.sh"
sudo bash "$script_dir/install-node.sh"
bash "$script_dir/install-ai-tools.sh"
