#!/usr/bin/env bash
# Install Codex, Claude Code, and shared skills for the current user.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "Run as your regular user, not with sudo." >&2
    exit 1
fi

command -v curl >/dev/null || { echo "curl is required." >&2; exit 1; }
command -v npx >/dev/null || { echo "npx is required; run install-node.sh first." >&2; exit 1; }

curl -fsSL https://chatgpt.com/codex/install.sh | sh
curl -fsSL https://claude.ai/install.sh | bash

npx --yes skills add jakubkrehel/skills --global \
    --agent codex claude-code --skill '*' --yes
npx --yes skills add vercel-labs/skills@find-skills --global \
    --agent codex claude-code --yes
