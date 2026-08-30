#!/usr/bin/env bash
# Install gh-release-flow and user-wide Make targets.
set -euo pipefail

if ((EUID == 0)); then
	echo "Run as your regular user, not with sudo." >&2
	exit 1
fi

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
install -d "${make_config%/*}"
printf '%s\n' \
	'.PHONY: start-dev open-pr merge-release' \
	'' \
	'start-dev open-pr merge-release:' \
	$'\t@gh release-flow "$@"' >"$make_config"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
MAKEFILES="$make_config" make --directory="$test_dir" --no-print-directory --dry-run merge-release |
	grep -Fqx 'gh release-flow "merge-release"'

# shellcheck disable=SC2016
makefiles_profile='case " ${MAKEFILES:-} " in *" $HOME/.config/make/release-flow.mk "*) ;; *) export MAKEFILES="$HOME/.config/make/release-flow.mk${MAKEFILES:+ $MAKEFILES}" ;; esac'
if [[ -s $HOME/.bashrc ]] && ! tail -c 1 "$HOME/.bashrc" | grep -q '^$'; then
	printf '\n' >>"$HOME/.bashrc"
fi
grep -Fqxs -- "$makefiles_profile" "$HOME/.bashrc" || printf '%s\n' "$makefiles_profile" >>"$HOME/.bashrc"

printf 'Run source ~/.bashrc or open a new terminal before using the Make targets.\n'
