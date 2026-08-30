#!/usr/bin/env bash
set -euo pipefail

if ((EUID == 0)); then
	echo 'Run this script as your regular user, not with sudo.' >&2
	exit 1
fi

mode=${1:-all}
case $mode in
all | identity | github) ;;
*)
	echo "Usage: $0 [identity|github]" >&2
	exit 1
	;;
esac

command -v git >/dev/null 2>&1 || {
	echo "git is not installed. Run sudo ./install-dependencies.sh first." >&2
	exit 1
}
if [[ $mode != identity ]] && ! command -v gh >/dev/null 2>&1; then
	echo "gh is not installed. Run sudo ./install-dependencies.sh first." >&2
	exit 1
fi

if [[ $mode != github ]]; then
	name=$(git config --global --get user.name || true)
	email=$(git config --global --get user.email || true)
	read -r -p "Git name${name:+ [$name]}: " input
	name=${input:-$name}
	read -r -p "Git email${email:+ [$email]}: " input
	email=${input:-$email}
	[[ -n $name ]] || {
		echo 'Enter a Git name.' >&2
		exit 1
	}
	[[ -n $email ]] || {
		echo 'Enter a Git email.' >&2
		exit 1
	}
	git config --global user.name "$name"
	git config --global user.email "$email"
	echo "Git configured for $name <$email>."
fi

if [[ $mode != identity ]]; then
	if [[ -n ${WSL_INTEROP:-} ]] && command -v explorer.exe >/dev/null 2>&1; then
		gh config set browser explorer.exe
	fi
	if gh auth status --hostname github.com >/dev/null 2>&1; then
		echo 'GitHub CLI is already authenticated.'
	else
		gh auth login --hostname github.com --git-protocol https --web
	fi
	gh auth setup-git --hostname github.com
	gh auth status --hostname github.com
fi
