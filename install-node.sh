#!/bin/bash
# Install the latest Node.js LTS system-wide using LinuxIO's nvm flow.
# Usage: sudo bash install-node.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

export NVM_DIR=/usr/local/nvm
if [[ ! -s $NVM_DIR/nvm.sh ]]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh |
        PROFILE=/dev/null bash
fi

# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'

current=$(nvm current)
ln -sfn "$NVM_DIR/versions/node/$current" "$NVM_DIR/versions/node/current"
printf '%s\n' 'export PATH="/usr/local/nvm/versions/node/current/bin:$PATH"' \
    >/etc/profile.d/node.sh
chmod 644 /etc/profile.d/node.sh
for command in node npm npx corepack; do
    ln -sfn "$NVM_DIR/versions/node/current/bin/$command" "/usr/local/bin/$command"
done

"$NVM_DIR/versions/node/current/bin/node" --version
"$NVM_DIR/versions/node/current/bin/npm" --version
