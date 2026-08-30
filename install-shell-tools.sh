#!/usr/bin/env bash
# Install pinned shell tools for the current user.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
	echo "Run as your regular user, not with sudo." >&2
	exit 1
fi

for command in curl gzip install sha256sum tar; do
	command -v "$command" >/dev/null || {
		echo "$command is required. Run the complete installer first." >&2
		exit 1
	}
done

shellcheck_version=v0.11.0
ripgrep_version=15.2.0
shfmt_version=v3.13.1
actionlint_version=v1.7.12
jq_version=jq-1.8.2

case $(uname -m) in
x86_64 | amd64)
	archive_arch=x86_64
	go_arch=amd64
	shellcheck_sha256=b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6
	ripgrep_sha256=33e15bcf1624b25cdd2a55813a47a2f95dbe126268203e76aa6a585d1e7b149c
	shfmt_sha256=fb096c5d1ac6beabbdbaa2874d025badb03ee07929f0c9ff67563ce8c75398b1
	actionlint_sha256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
	jq_sha256=b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f
	;;
aarch64 | arm64)
	archive_arch=aarch64
	go_arch=arm64
	shellcheck_sha256=68a8133197a50beb8803f8d42f9908d1af1c5540d4bb05fdfca8c1fa47decefc
	ripgrep_sha256=800b1e7206afe799dfb5a6901f23147cfaabe0e52210538100f61e86e1740915
	shfmt_sha256=32d92acaa5cd8abb29fc49dac123dc412442d5713967819d8af2c29f1b3857c7
	actionlint_sha256=325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6
	jq_sha256=8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309
	;;
*)
	echo "Unsupported architecture: $(uname -m)" >&2
	exit 1
	;;
esac

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
install_dir=${LINUX_TOOLBOX_BIN_DIR:-$HOME/.local/bin}

download() {
	local url=$1 checksum=$2 output=$3
	curl -fsSL "$url" -o "$output"
	printf '%s  %s\n' "$checksum" "$output" | sha256sum --check --quiet
}

shellcheck_archive="$tmp_dir/shellcheck.tar.gz"
download "https://github.com/koalaman/shellcheck/releases/download/$shellcheck_version/shellcheck-$shellcheck_version.linux.$archive_arch.tar.gz" \
	"$shellcheck_sha256" "$shellcheck_archive"
tar -xzf "$shellcheck_archive" -C "$tmp_dir"

ripgrep_archive="$tmp_dir/ripgrep.tar.gz"
download "https://github.com/BurntSushi/ripgrep/releases/download/$ripgrep_version/ripgrep-$ripgrep_version-$archive_arch-unknown-linux-musl.tar.gz" \
	"$ripgrep_sha256" "$ripgrep_archive"
tar -xzf "$ripgrep_archive" -C "$tmp_dir"

download "https://github.com/mvdan/sh/releases/download/$shfmt_version/shfmt_${shfmt_version}_linux_$go_arch" \
	"$shfmt_sha256" "$tmp_dir/shfmt"

actionlint_archive="$tmp_dir/actionlint.tar.gz"
download "https://github.com/rhysd/actionlint/releases/download/$actionlint_version/actionlint_${actionlint_version#v}_linux_$go_arch.tar.gz" \
	"$actionlint_sha256" "$actionlint_archive"
tar -xzf "$actionlint_archive" -C "$tmp_dir"

download "https://github.com/jqlang/jq/releases/download/$jq_version/jq-linux-$go_arch" \
	"$jq_sha256" "$tmp_dir/jq"

install -Dm755 "$tmp_dir/shellcheck-$shellcheck_version/shellcheck" "$install_dir/shellcheck"
install -Dm755 "$tmp_dir/ripgrep-$ripgrep_version-$archive_arch-unknown-linux-musl/rg" "$install_dir/rg"
install -Dm755 "$tmp_dir/shfmt" "$install_dir/shfmt"
install -Dm755 "$tmp_dir/actionlint" "$install_dir/actionlint"
install -Dm755 "$tmp_dir/jq" "$install_dir/jq"

printf '\nShell tools installed in %s:\n' "$install_dir"
for command in shellcheck shfmt jq rg actionlint; do
	printf '  %s\n' "$command"
done
