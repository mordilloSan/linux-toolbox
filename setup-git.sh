#!/usr/bin/env bash
set -euo pipefail

if ((EUID == 0)); then
	echo 'Run this script as your regular user, not with sudo.' >&2
	exit 1
fi

for command in git gh; do
	command -v "$command" >/dev/null 2>&1 || {
		echo "$command is not installed. Run sudo ./install-dependencies.sh first." >&2
		exit 1
	}
done

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

if [[ -n ${WSL_INTEROP:-} ]] && command -v explorer.exe >/dev/null 2>&1; then
	gh config set browser explorer.exe
fi

if gh auth status --hostname github.com >/dev/null 2>&1; then
	echo 'GitHub CLI is already authenticated.'
else
	gh auth login --hostname github.com --git-protocol https --web
fi
gh auth setup-git --hostname github.com

echo "Git configured for $name <$email>."
gh auth status --hostname github.com
