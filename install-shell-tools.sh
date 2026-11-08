#!/usr/bin/env bash
# Install the latest shell tools for the current user.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
	echo "Run as your regular user, not with sudo." >&2
	exit 1
fi

readonly RESET=$'\033[0m'
readonly GREEN=$'\033[38;5;154m'
readonly GREY=$'\033[90m'
readonly BOLD=$'\033[1m'

info() {
	printf ' %s[%s INFO %s]%s %s\n' "$GREY" "$BOLD" "$GREY" "$RESET" "$1"
}

ok() {
	printf ' %s[%s  OK  %s]%s %s\n' "$GREY" "$GREEN" "$GREY" "$RESET" "$1"
}

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

for command in awk curl gzip install sha256sum tar; do
	command -v "$command" >/dev/null || {
		echo "$command is required. Run the complete installer first." >&2
		exit 1
	}
done

case $(uname -m) in
x86_64 | amd64)
	archive_arch=x86_64
	go_arch=amd64
	;;
aarch64 | arm64)
	archive_arch=aarch64
	go_arch=arm64
	;;
*)
	echo "Unsupported architecture: $(uname -m)" >&2
	exit 1
	;;
esac

# Not /tmp: it may be mounted noexec, and the downloaded binaries are run from here.
mkdir -p "$HOME/.cache"
tmp_dir=$(mktemp -d "$HOME/.cache/linux-toolbox.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT
install_dir=${LINUX_TOOLBOX_BIN_DIR:-$HOME/.local/bin}

# Install a tool unless a copy outside install_dir exists and the user keeps it.
wanted() {
	local existing
	existing=$(command -v "$1" || true)
	# A Snap copy is sandboxed away from home files, and the Ubuntu cleanup deletes it: treat it as missing.
	[[ -z $existing || $existing == "$install_dir/$1" || $existing == /snap/* ]] && return 0
	confirm "$1 found at $existing. Also install the latest $1 in $install_dir?" && return 0
	notice "Kept $existing"
	return 1
}

# jq is always downloaded because it resolves the other release assets.
jq_asset="jq-linux-$go_arch"
jq_checksum=$(curl -fsSL --speed-limit 1 --speed-time 60 https://github.com/jqlang/jq/releases/latest/download/sha256sum.txt |
	awk -v asset="$jq_asset" '$2 == asset { print $1 }')
[[ $jq_checksum =~ ^[0-9a-f]{64}$ ]] || {
	echo "Could not verify the latest jq release." >&2
	exit 1
}
curl -fsSL --speed-limit 1 --speed-time 60 "https://github.com/jqlang/jq/releases/latest/download/$jq_asset" -o "$tmp_dir/jq"
printf '%s  %s\n' "$jq_checksum" "$tmp_dir/jq" | sha256sum --check --quiet
chmod 755 "$tmp_dir/jq"
if wanted jq; then
	info "Installing or updating jq..."
	install -Dm755 "$tmp_dir/jq" "$install_dir/jq"
	ok "jq installed"
fi

# A GitHub login raises the API limit from 60 to 5,000 requests an hour.
token=${GH_TOKEN:-$(gh auth token 2>/dev/null </dev/null || true)}

download() {
	local repo=$1 pattern=$2 output=$3 asset url digest
	# The token goes to curl on stdin (-K -), so other users cannot read it from the process list.
	# jq expands $pattern, not the shell.
	# shellcheck disable=SC2016
	asset=$(curl -fsSL --speed-limit 1 --speed-time 60 -K - "https://api.github.com/repos/$repo/releases/latest" \
		<<<"${token:+header = \"Authorization: Bearer $token\"}" |
		"$tmp_dir/jq" -er --arg pattern "$pattern" \
			'[.assets[] | select(.name | test($pattern))] |
			if length == 1 then .[0] | [.browser_download_url, .digest] | @tsv
			else error("expected one matching release asset") end') || {
		echo "Could not resolve the latest $repo release. Without a login, GitHub allows 60 API requests an hour per IP; run 'gh auth login' or set GH_TOKEN, then try again." >&2
		exit 1
	}
	IFS=$'\t' read -r url digest <<<"$asset"
	[[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || {
		echo "GitHub did not provide a SHA-256 digest for $repo." >&2
		exit 1
	}
	curl -fsSL --speed-limit 1 --speed-time 60 "$url" -o "$output"
	printf '%s  %s\n' "${digest#sha256:}" "$output" | sha256sum --check --quiet
}

mkdir "$tmp_dir/shellcheck" "$tmp_dir/ripgrep" "$tmp_dir/actionlint"

if wanted shellcheck; then
	info "Installing or updating ShellCheck..."
	shellcheck_archive="$tmp_dir/shellcheck.tar.gz"
	download koalaman/shellcheck "\\.linux\\.${archive_arch}\\.tar\\.gz$" "$shellcheck_archive"
	tar -xzf "$shellcheck_archive" -C "$tmp_dir/shellcheck" --strip-components=1
	install -Dm755 "$tmp_dir/shellcheck/shellcheck" "$install_dir/shellcheck"
	ok "ShellCheck installed"
fi

if wanted rg; then
	info "Installing or updating ripgrep..."
	ripgrep_archive="$tmp_dir/ripgrep.tar.gz"
	download BurntSushi/ripgrep "-${archive_arch}-unknown-linux-musl\\.tar\\.gz$" "$ripgrep_archive"
	tar -xzf "$ripgrep_archive" -C "$tmp_dir/ripgrep" --strip-components=1
	install -Dm755 "$tmp_dir/ripgrep/rg" "$install_dir/rg"
	ok "ripgrep installed"
fi

if wanted shfmt; then
	info "Installing or updating shfmt..."
	download mvdan/sh "_linux_${go_arch}$" "$tmp_dir/shfmt"
	install -Dm755 "$tmp_dir/shfmt" "$install_dir/shfmt"
	ok "shfmt installed"
fi

if wanted actionlint; then
	info "Installing or updating actionlint..."
	actionlint_archive="$tmp_dir/actionlint.tar.gz"
	download rhysd/actionlint "_linux_${go_arch}\\.tar\\.gz$" "$actionlint_archive"
	tar -xzf "$actionlint_archive" -C "$tmp_dir/actionlint"
	install -Dm755 "$tmp_dir/actionlint/actionlint" "$install_dir/actionlint"
	ok "actionlint installed"
fi
