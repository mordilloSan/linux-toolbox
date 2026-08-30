#!/bin/bash
# Install the latest Node.js LTS using LinuxIO's user-local nvm flow.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
	echo "Run as your regular user, not with sudo." >&2
	exit 1
fi

for command in awk curl grep sed tar; do
	command -v "$command" >/dev/null || {
		echo "$command is required. Run the complete installer first." >&2
		exit 1
	}
done

export NVM_DIR=${NVM_DIR:-$HOME/.nvm}
if [[ ! -s $NVM_DIR/nvm.sh ]]; then
	nvm_version=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://latest.nvm.sh)
	nvm_version=${nvm_version##*/}
	[[ $nvm_version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
		echo "Invalid nvm version: $nvm_version" >&2
		exit 1
	}
	curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$nvm_version/install.sh" |
		METHOD=script bash >/dev/null
fi

install_node() (
	# nvm is not compatible with errexit.
	set +e
	set -uo pipefail
	# shellcheck source=/dev/null
	. "$NVM_DIR/nvm.sh" || return
	local log current
	log=$(mktemp)
	trap 'rm -f "$log"' EXIT
	if ! nvm install --lts --no-progress >"$log" 2>&1; then
		cat "$log" >&2
		return 1
	fi
	nvm alias default 'lts/*' >/dev/null || return
	current=$(nvm version 'lts/*') || return
	mkdir -p "$NVM_DIR/versions/node" || return
	ln -snf "$NVM_DIR/versions/node/$current" "$NVM_DIR/versions/node/current"
)

install_node
