#!/bin/bash
# Install the current stable Go system-wide using LinuxIO's toolchain flow.
# Usage: sudo bash install-go.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

version=$(curl -fsSL 'https://go.dev/VERSION?m=text' | sed -n '1s/^go//p')
[[ $version =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || {
    echo "Invalid Go version returned by go.dev: $version" >&2
    exit 1
}

case $(uname -m) in
    x86_64 | amd64) goarch=amd64 ;;
    aarch64 | arm64) goarch=arm64 ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

versions_dir=/usr/local/go-versions
go_dir=$versions_dir/go$version
current=$versions_dir/current

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
printf '%s\n' 'export PATH="/usr/local/go-versions/current/bin:$HOME/go/bin:$PATH"' \
    >/etc/profile.d/go.sh
chmod 644 /etc/profile.d/go.sh
ln -sfn "$current/bin/go" /usr/local/bin/go
ln -sfn "$current/bin/gofmt" /usr/local/bin/gofmt

"$current/bin/go" version
