#!/usr/bin/env bash
# Install Codex, Claude Code, AI shell tools, and shared skills for the current user.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
	echo "Run as your regular user, not with sudo." >&2
	exit 1
fi

for command in curl go jq npx; do
	command -v "$command" >/dev/null || {
		echo "$command is required. Run the complete installer first." >&2
		exit 1
	}
done

curl -fsSL https://chatgpt.com/codex/install.sh | sh
curl -fsSL https://claude.ai/install.sh | bash

# Installers place their launchers here; include it in this shell immediately.
export PATH="$HOME/.local/bin:$PATH"
command -v claude >/dev/null || {
	echo "Claude Code installation failed." >&2
	exit 1
}
command -v codex >/dev/null || {
	echo "Codex installation failed." >&2
	exit 1
}

shellcheck_version=v0.11.0
case $(uname -m) in
x86_64 | amd64)
	shellcheck_arch=x86_64
	shellcheck_sha256=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
	;;
aarch64 | arm64)
	shellcheck_arch=aarch64
	shellcheck_sha256=12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588
	;;
*)
	echo "Unsupported architecture: $(uname -m)" >&2
	exit 1
	;;
esac
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
shellcheck_archive="$tmp_dir/shellcheck.tar.xz"
curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/$shellcheck_version/shellcheck-$shellcheck_version.linux-$shellcheck_arch.tar.xz" \
	-o "$shellcheck_archive"
printf '%s  %s\n' "$shellcheck_sha256" "$shellcheck_archive" | sha256sum --check
tar -xJf "$shellcheck_archive" -C "$tmp_dir"
install -d "$HOME/.local/bin"
install -m 755 "$tmp_dir/shellcheck-$shellcheck_version/shellcheck" "$HOME/.local/bin/shellcheck"
GOBIN="$HOME/.local/bin" go install mvdan.cc/sh/v3/cmd/shfmt@v3.13.1

claude plugin marketplace add DietrichGebert/ponytail
claude plugin install ponytail@ponytail --yes
codex plugin marketplace add DietrichGebert/ponytail
codex plugin add ponytail@ponytail

npx --yes skills add jakubkrehel/skills --global \
	--agent codex claude-code --skill '*' --yes
npx --yes skills add vercel-labs/skills@find-skills --global \
	--agent codex claude-code --yes
npx --yes skills add https://github.com/samber/cc-skills-golang --global \
	--agent codex claude-code \
	--skill golang-concurrency golang-context golang-security \
	golang-troubleshooting --yes

printf '\nAI shell tools available to Codex and Claude Code:\n'
shellcheck --version | sed -n 's/^version: /  shellcheck /p'
printf '  shfmt %s\n' "$(shfmt --version)"
printf '  %s\n' "$(jq --version)"
