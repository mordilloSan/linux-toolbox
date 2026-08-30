#!/usr/bin/env bash
set -euo pipefail

if ((EUID == 0)); then
    echo "Run this installer as your regular user, not with sudo." >&2
    exit 1
fi

base_url=https://raw.githubusercontent.com/mordilloSan/linux-toolbox/main

# ponytail: main can move between downloads; use release URLs when atomic releases matter.
curl -fsSL "$base_url/install-dependencies.sh" | sudo bash
curl -fsSL "$base_url/install-go.sh" | sudo bash
curl -fsSL "$base_url/install-node.sh" | sudo bash
curl -fsSL "$base_url/install-ai-tools.sh" | bash
