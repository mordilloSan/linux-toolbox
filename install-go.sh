#!/bin/bash
# Install the current stable Go system-wide using LinuxIO's toolchain flow.
# Usage: sudo bash install-go.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "Run as root: sudo bash $0" >&2
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

version=$(curl -fsSL 'https://go.dev/VERSION?m=text' | sed -n '1s/^go//p')
[[ $version =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || {
	echo "Invalid Go version returned by go.dev: $version" >&2
	exit 1
}

case $(uname -m) in
x86_64 | amd64) goarch=amd64 ;;
aarch64 | arm64) goarch=arm64 ;;
*)
	echo "Unsupported architecture: $(uname -m)" >&2
	exit 1
	;;
esac

versions_dir=/usr/local/go-versions
go_dir=$versions_dir/go$version
current=$versions_dir/current

# Variables intentionally expand in future login shells.
# shellcheck disable=SC2016
profile_line='export PATH="/usr/local/go-versions/current/bin:$HOME/go/bin:$PATH"'
conflicts=()
for existing in /usr/local/bin/go /usr/local/go/bin/go /usr/bin/go "$(command -v go || true)"; do
	[[ -n $existing && -x $existing ]] || continue
	[[ $(readlink -f "$existing") == "$versions_dir"/* ]] && continue
	[[ " ${conflicts[*]} " == *" $existing "* ]] && continue
	conflicts+=("$existing")
done
if [[ -e /etc/profile.d/go.sh && $(</etc/profile.d/go.sh) != "$profile_line" ]]; then
	conflicts+=(/etc/profile.d/go.sh)
fi
if ((${#conflicts[@]})) &&
	! confirm "Existing Go setup found: ${conflicts[*]}. Install Go $version as the default and replace /usr/local/bin/go and /etc/profile.d/go.sh?"; then
	notice "Kept the existing Go setup"
	exit 0
fi

if [[ ! -x $go_dir/bin/go ]]; then
	tmp_dir=$(mktemp -d)
	trap 'rm -rf "$tmp_dir"' EXIT
	curl -fsSL "https://go.dev/dl/go$version.linux-$goarch.tar.gz" \
		-o "$tmp_dir/go.tar.gz"
	tar -C "$tmp_dir" -xzf "$tmp_dir/go.tar.gz"
	mkdir -p "$versions_dir"
	rm -rf "$go_dir"
	mv "$tmp_dir/go" "$go_dir"
fi

ln -sfn "$go_dir" "$current"
printf '%s\n' "$profile_line" >/etc/profile.d/go.sh
chmod 644 /etc/profile.d/go.sh
ln -sfn "$current/bin/go" /usr/local/bin/go
ln -sfn "$current/bin/gofmt" /usr/local/bin/gofmt
