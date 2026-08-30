#!/usr/bin/env bash
set -euo pipefail

if ((EUID == 0)); then
    echo "Run this installer as your regular user, not with sudo." >&2
    exit 1
fi

base_url=https://raw.githubusercontent.com/mordilloSan/linux-toolbox/main
scripts=(install.sh install-dependencies.sh install-go.sh install-node.sh install-ai-tools.sh)
install_dir=$(mktemp -d)
trap 'rm -rf "$install_dir"' EXIT

# ponytail: main can move between downloads; use a release archive when atomic releases matter.
for script in "${scripts[@]}"; do
    curl -fsSL "$base_url/$script" -o "$install_dir/$script"
done

bash "$install_dir/install.sh"
