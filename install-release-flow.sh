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

# make splits MAKEFILES at spaces, so it can never load the targets from such a home.
[[ $HOME != *' '* ]] || {
	notice "make cannot load files from a path with spaces; skipped the Make targets. Use gh release-flow directly."
	exit 0
}

make_config="$HOME/.config/make/release-flow.mk"
make_targets=$(printf '%s\n' \
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
# The v1.10.0 targets: this script wrote them, so they are replaced without asking.
old_targets=$(printf '%s\n' '.PHONY: start-dev open-pr merge-release' '' \
	'start-dev open-pr merge-release:' $'\t@gh release-flow "$@"')
if [[ -e $make_config && $(<"$make_config") != "$make_targets" && $(<"$make_config") != "$old_targets" ]] &&
	! confirm "$make_config has different content. Replace it with the release-flow targets?"; then
	notice "Kept the existing $make_config"
else
	install -d "${make_config%/*}"
	printf '%s\n' "$make_targets" >"$make_config"
fi

# A make function for interactive shells: make help ends with the release-flow targets, after the project's
# own help when it has one, and they are all that plain make without a Makefile prints.
# This script owns the file and rewrites it on each run.
cat >"$HOME/.config/make/release-flow.sh" <<'EOF'
# Written by linux-toolbox install-release-flow.sh, which replaces it on each run.
make() {
	local code=0 targets='release-flow: make start-dev | open-pr | merge-release | rf-version | rf-upgrade'
	if [ $# -eq 0 ] && [ ! -e GNUmakefile ] && [ ! -e makefile ] && [ ! -e Makefile ]; then
		printf '%s\n' "$targets"
		return 0
	fi
	if [ "$*" != help ]; then
		command make "$@"
		return
	fi
	case $(LC_ALL=C command make -q help 2>&1 >/dev/null) in
	*"No rule to make target 'help'"*) ;;
	*) command make help || code=$? ;;
	esac
	printf '%s\n' "$targets"
	return "$code"
}
EOF

# shellcheck disable=SC2016
makefiles_profile='case " ${MAKEFILES:-} " in *" $HOME/.config/make/release-flow.mk "*) ;; *) export MAKEFILES="$HOME/.config/make/release-flow.mk${MAKEFILES:+ $MAKEFILES}" ;; esac'
# shellcheck disable=SC2016
function_profile='[ ! -f "$HOME/.config/make/release-flow.sh" ] || . "$HOME/.config/make/release-flow.sh"'
# The lines are plain sh, so zsh reads them too; .zshrc only gets them when the user already has one.
for rc in "$HOME/.bashrc" "${ZDOTDIR:-$HOME}/.zshrc"; do
	[[ $rc == "$HOME/.bashrc" || -e $rc ]] || continue
	added=0
	for line in "$makefiles_profile" "$function_profile"; do
		grep -Fqxs -- "$line" "$rc" && continue
		if [[ -s $rc ]] && ! tail -c 1 "$rc" | grep -q '^$'; then
			printf '\n' >>"$rc"
		fi
		printf '%s\n' "$line" >>"$rc"
		added=1
	done
	((added)) || continue
	printf ' [NOTICE] Run source %s or open a new terminal before using the Make targets.\n' "${rc/#$HOME/\~}"
done
