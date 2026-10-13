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

if ! extension_output=$(gh extension install mordilloSan/gh-release-flow --force 2>&1); then
	printf '%s\n' "$extension_output" >&2
	exit 1
fi

make_config="$HOME/.config/make/release-flow.mk"
make_targets=$(printf '%s\n' \
	'.PHONY: start-dev open-pr merge-release' \
	'' \
	'start-dev open-pr merge-release:' \
	$'\t@gh release-flow "$@"')
if [[ -e $make_config && $(<"$make_config") != "$make_targets" ]] &&
	! confirm "$make_config has different content. Replace it with the release-flow targets?"; then
	notice "Kept the existing $make_config"
else
	install -d "${make_config%/*}"
	printf '%s\n' "$make_targets" >"$make_config"
	test_dir=$(mktemp -d)
	trap 'rm -rf "$test_dir"' EXIT
	MAKEFILES="$make_config" make --directory="$test_dir" --no-print-directory --dry-run merge-release |
		grep -Fqx 'gh release-flow "merge-release"'
fi

# shellcheck disable=SC2016
makefiles_profile='case " ${MAKEFILES:-} " in *" $HOME/.config/make/release-flow.mk "*) ;; *) export MAKEFILES="$HOME/.config/make/release-flow.mk${MAKEFILES:+ $MAKEFILES}" ;; esac'
if ! grep -Fqxs -- "$makefiles_profile" "$HOME/.bashrc"; then
	if [[ -s $HOME/.bashrc ]] && ! tail -c 1 "$HOME/.bashrc" | grep -q '^$'; then
		printf '\n' >>"$HOME/.bashrc"
	fi
	printf '%s\n' "$makefiles_profile" >>"$HOME/.bashrc"
	printf ' [NOTICE] Run source ~/.bashrc or open a new terminal before using the Make targets.\n'
fi
