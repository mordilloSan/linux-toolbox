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

# Ask on the terminal. No terminal or LINUX_TOOLBOX_NONINTERACTIVE=1 answers No.
confirm() {
	local answer
	[[ ${LINUX_TOOLBOX_NONINTERACTIVE:-0} != 1 ]] || return 1
	{ exec 3<>/dev/tty; } 2>/dev/null || return 1
	printf '\n \033[33m[?]\033[0m %s [y/N] ' "$1" >&3
	IFS= read -r answer <&3 || answer=
	exec 3>&-
	[[ $answer == [yY] ]]
}

notice() {
	printf ' \033[90m[\033[33mNOTICE\033[90m]\033[0m %s\n' "$1"
}

export NVM_DIR=${NVM_DIR:-$HOME/.nvm}
existing=$(command -v node || true)
if [[ -n $existing && $(readlink -f "$existing") != "$NVM_DIR"/* ]] &&
	! confirm "Node.js $("$existing" --version 2>/dev/null) found at $existing. Install Node.js LTS with nvm? nvm's copy comes first in new shells."; then
	notice "Kept the existing Node.js"
	exit 0
fi
set_default=1
if [[ -s $NVM_DIR/alias/default && $(<"$NVM_DIR/alias/default") != 'lts/*' ]] &&
	! confirm "The nvm default is $(<"$NVM_DIR/alias/default"). Change it to the latest LTS?"; then
	notice "Kept the nvm default $(<"$NVM_DIR/alias/default")"
	set_default=
fi
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
	[[ -z $set_default ]] || nvm alias default 'lts/*' >/dev/null || return
	current=$(nvm version 'lts/*') || return
	mkdir -p "$NVM_DIR/versions/node" || return
	ln -snf "$NVM_DIR/versions/node/$current" "$NVM_DIR/versions/node/current"
)

install_node
