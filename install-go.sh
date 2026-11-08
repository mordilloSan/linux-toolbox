#!/bin/bash
# Install the current stable Go system-wide.
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

ok() {
	printf ' \033[90m[\033[38;5;154m  OK  \033[90m]\033[0m %s\n' "$1"
}

version=$(curl -fsSL --speed-limit 1 --speed-time 60 'https://go.dev/VERSION?m=text' | sed -n '1s/^go//p')
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

# Go's official location. Other versions per project come from Go itself (GOTOOLCHAIN, go.mod).
go_root=/usr/local/go
# Earlier versions of this script kept Go in versioned folders here; they are migrated and removed.
old_versions_dir=/usr/local/go-versions

# Variables intentionally expand in future login shells.
# shellcheck disable=SC2016
profile_line='export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"'
# shellcheck disable=SC2016
old_profile_line='export PATH="/usr/local/go-versions/current/bin:$HOME/go/bin:$PATH"'
conflicts=()
owned=
if [[ -e /etc/profile.d/go.sh ]]; then
	case $(</etc/profile.d/go.sh) in
	"$profile_line" | "$old_profile_line") owned=1 ;;
	*) conflicts+=(/etc/profile.d/go.sh) ;;
	esac
fi
# A Go in /usr/local/go is ours to update only when our profile line is in place; otherwise someone else put it there.
[[ -n $owned || ! -e $go_root ]] || conflicts+=("$go_root")
for existing in /usr/local/bin/go /usr/bin/go "$(command -v go || true)"; do
	[[ -n $existing && -x $existing ]] || continue
	case $(readlink -f "$existing") in
	"$(readlink -m "$go_root")"/* | "$(readlink -m "$old_versions_dir")"/*) continue ;;
	esac
	[[ " ${conflicts[*]} " == *" $existing "* ]] && continue
	conflicts+=("$existing")
done
if ((${#conflicts[@]})) &&
	! confirm "Existing Go setup found: ${conflicts[*]}. Install Go $version as the default and replace $go_root, /usr/local/bin/go and /etc/profile.d/go.sh?"; then
	notice "Kept the existing Go setup"
	exit 0
fi

installed=$(sed -n '1s/^go//p' "$go_root/VERSION" 2>/dev/null || true)
if [[ $installed != "$version" ]]; then
	# Unpack next to /usr/local/go (same filesystem), then swap with two renames,
	# so a failed download or unpack never leaves the machine without a working Go.
	tmp_dir=$(mktemp -d "$go_root.new.XXXXXX")
	trap 'rm -rf "$tmp_dir"' EXIT
	curl -fsSL --speed-limit 1 --speed-time 60 "https://go.dev/dl/go$version.linux-$goarch.tar.gz" \
		-o "$tmp_dir/go.tar.gz"
	tar -C "$tmp_dir" -xzf "$tmp_dir/go.tar.gz"
	[[ ! -e $go_root && ! -L $go_root ]] || mv "$go_root" "$tmp_dir/old"
	mv "$tmp_dir/go" "$go_root"
fi

printf '%s\n' "$profile_line" >/etc/profile.d/go.sh
chmod 644 /etc/profile.d/go.sh
ln -sfn "$go_root/bin/go" /usr/local/bin/go
ln -sfn "$go_root/bin/gofmt" /usr/local/bin/gofmt
rm -rf "$old_versions_dir"
if [[ $installed == "$version" ]]; then
	ok "Go $version is already up to date"
elif [[ -n $installed ]]; then
	ok "Go updated from $installed to $version"
else
	ok "Go $version installed"
fi
