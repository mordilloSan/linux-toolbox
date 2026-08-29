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
    nvm_version=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://latest.nvm.sh)
    nvm_version=${nvm_version##*/}
    [[ $nvm_version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
        echo "Invalid nvm version: $nvm_version" >&2
        exit 1
    }
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$nvm_version/install.sh" |
        PROFILE=/dev/null bash
fi

# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'

current=$(nvm current)
ln -sfn "$NVM_DIR/versions/node/$current" "$NVM_DIR/versions/node/current"
# PATH intentionally expands in future login shells.
# shellcheck disable=SC2016
printf '%s\n' 'export PATH="/usr/local/nvm/versions/node/current/bin:$PATH"' \
    >/etc/profile.d/node.sh
chmod 644 /etc/profile.d/node.sh
for command in node npm npx corepack; do
    ln -sfn "$NVM_DIR/versions/node/current/bin/$command" "/usr/local/bin/$command"
done

"$NVM_DIR/versions/node/current/bin/node" --version
"$NVM_DIR/versions/node/current/bin/npm" --version
