#!/usr/bin/env bash
# Install gh-release-flow and user-wide Make targets.
set -euo pipefail

if ((EUID == 0)); then
	echo "Run as your regular user, not with sudo." >&2
	exit 1
fi

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

for command in gh make; do
	command -v "$command" >/dev/null || {
		echo "$command is required. Run the complete installer first." >&2
		exit 1
	}
done

# install --force reports an upgrade of an installed extension without moving its checkout, so upgrade it instead.
if gh extension list 2>/dev/null | grep -Fq 'mordilloSan/gh-release-flow'; then
	extension_command=(upgrade release-flow)
else
	extension_command=(install mordilloSan/gh-release-flow)
fi
if ! extension_output=$(gh extension "${extension_command[@]}" 2>&1); then
	printf '%s\n' "$extension_output" >&2
	exit 1
fi

# make splits MAKEFILES at spaces, so it can never load the targets from such a home.
[[ $HOME != *' '* ]] || {
	notice "make cannot load files from a path with spaces; skipped the Make targets. Use gh release-flow directly."
	exit 0
}

# gh release-flow setup-make owns the Make targets and the make shell function; make rf-upgrade refreshes them.
make_config="$HOME/.config/make/release-flow.mk"
replace_answer=
if [[ -e $make_config && $(head -n 1 "$make_config") != '# Written by gh release-flow setup-make'* ]]; then
	# The targets this script wrote up to v1.14.0 are replaced without asking.
	old_targets=$(printf '%s\n' '.PHONY: start-dev open-pr merge-release' '' \
		'start-dev open-pr merge-release:' $'\t@gh release-flow "$@"')
	current_targets=$(printf '%s\n' \
		'.PHONY: start-dev open-pr merge-release rf-version rf-upgrade' \
		'' \
		'start-dev open-pr merge-release:' \
		$'\t@gh release-flow "$@"' \
		'' \
		'rf-version rf-upgrade:' \
		$'\t@gh release-flow "$(@:rf-%=%)"' \
		'' \
		'# Keep project Makefiles that read MAKEFILE_LIST unaware of this file.' \
		'MAKEFILE_LIST :=')
	if [[ $(<"$make_config") != "$old_targets" && $(<"$make_config") != "$current_targets" ]] &&
		! confirm "$make_config has different content. Replace it with the release-flow targets?"; then
		notice "Kept the existing $make_config; skipped the Make targets."
		exit 0
	fi
	replace_answer=y
fi

# setup-make asks before it replaces a file it did not write. The answer is fed to it, because stdin
# may be the piped installer script.
if ! setup_output=$(gh release-flow setup-make <<<"$replace_answer" 2>&1); then
	printf '%s\n' "$setup_output" >&2
	exit 1
fi
[[ $setup_output != *'Open a new terminal'* ]] ||
	notice "Open a new terminal before using the Make targets."
