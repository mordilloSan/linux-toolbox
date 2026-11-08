#!/bin/bash
# Install the latest Node.js LTS with a user-local nvm.
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

ok() {
	printf ' \033[90m[\033[38;5;154m  OK  \033[90m]\033[0m %s\n' "$1"
}

export NVM_DIR=${NVM_DIR:-$HOME/.nvm}
existing=$(command -v node || true)
# Only a Node.js with its own npx (the distro nodejs package has none) that the skills CLI can run
# (22.20 or newer; raise it when the skills pin moves) is offered to keep.
if [[ -n $existing && $(readlink -f "$existing") != "$(readlink -m "$NVM_DIR")"/* && -x ${existing%/*}/npx ]] &&
	[[ $(printf '%s\n' v22.20.0 "$("$existing" --version 2>/dev/null)" | sort -V | head -n 1) == v22.20.0 ]] &&
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
# nvm refuses to run when ~/.npmrc sets prefix or globalconfig.
if grep -Eqs '^[[:space:]]*(prefix|globalconfig)[[:space:]]*=' "$HOME/.npmrc"; then
	echo "$HOME/.npmrc sets prefix or globalconfig, which nvm cannot use. Remove that line, then run the installer again." >&2
	exit 1
fi
if [[ ! -s $NVM_DIR/nvm.sh ]]; then
	nvm_version=$(curl -fsSL --speed-limit 1 --speed-time 60 -o /dev/null -w '%{url_effective}' https://latest.nvm.sh)
	nvm_version=${nvm_version##*/}
	[[ $nvm_version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
		echo "Invalid nvm version: $nvm_version" >&2
		exit 1
	}
	# nvm's installer rejects a missing NVM_DIR unless it is nvm's own default, which XDG_CONFIG_HOME changes.
	mkdir -p "$NVM_DIR"
	curl -fsSL --speed-limit 1 --speed-time 60 "https://raw.githubusercontent.com/nvm-sh/nvm/$nvm_version/install.sh" |
		METHOD=script bash >/dev/null
fi

install_node() (
	# nvm is not compatible with errexit.
	set +e
	# shellcheck source=/dev/null
	. "$NVM_DIR/nvm.sh" || return
	local output current previous
	if ! output=$(nvm install --lts --no-progress 2>&1); then
		printf '%s\n' "$output" >&2
		return 1
	fi
	[[ -z $set_default ]] || nvm alias default 'lts/*' >/dev/null || return
	current=$(nvm version 'lts/*') || return
	previous=$(readlink "$NVM_DIR/versions/node/current")
	ln -snf "$NVM_DIR/versions/node/$current" "$NVM_DIR/versions/node/current"
	previous=${previous##*/}
	# Work in the new version: nvm refuses to copy packages out of the active one, and npm -g below must land here.
	nvm use "$current" >/dev/null || return
	# Global npm packages live inside each version: bring them to the new one. Old versions stay for .nvmrc pins.
	if [[ $previous == v* && $previous != "$current" ]]; then
		nvm reinstall-packages "$previous" >/dev/null 2>&1 || notice "Could not copy global npm packages from Node.js $previous"
	fi
	if [[ $previous == "$current" ]]; then
		ok "Node.js $current is already up to date"
	elif [[ $previous == v* ]]; then
		ok "Node.js updated from $previous to $current"
	else
		ok "Node.js $current installed"
	fi
	# Claude Code's typescript-lsp plugin runs typescript-language-server, which needs typescript next to it.
	if ! output=$(npm install -g --no-fund --no-audit typescript typescript-language-server 2>&1); then
		printf '%s\n' "$output" >&2
		notice "Could not install the TypeScript language server; run: npm install -g typescript typescript-language-server"
	fi
)

install_node
