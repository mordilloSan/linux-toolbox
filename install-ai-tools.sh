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
ripgrep_version=15.2.0
case $(uname -m) in
x86_64 | amd64)
	shellcheck_arch=x86_64
	shellcheck_sha256=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
	ripgrep_arch=x86_64
	ripgrep_sha256=33e15bcf1624b25cdd2a55813a47a2f95dbe126268203e76aa6a585d1e7b149c
	;;
aarch64 | arm64)
	shellcheck_arch=aarch64
	shellcheck_sha256=12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588
	ripgrep_arch=aarch64
	ripgrep_sha256=800b1e7206afe799dfb5a6901f23147cfaabe0e52210538100f61e86e1740915
	;;
*)
	echo "Unsupported architecture: $(uname -m)" >&2
	exit 1
	;;
esac
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
shellcheck_archive="$tmp_dir/shellcheck.tar.xz"
ripgrep_archive="$tmp_dir/ripgrep.tar.gz"
curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/$shellcheck_version/shellcheck-$shellcheck_version.linux-$shellcheck_arch.tar.xz" \
	-o "$shellcheck_archive"
printf '%s  %s\n' "$shellcheck_sha256" "$shellcheck_archive" | sha256sum --check
tar -xJf "$shellcheck_archive" -C "$tmp_dir"
curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/$ripgrep_version/ripgrep-$ripgrep_version-$ripgrep_arch-unknown-linux-musl.tar.gz" \
	-o "$ripgrep_archive"
printf '%s  %s\n' "$ripgrep_sha256" "$ripgrep_archive" | sha256sum --check
tar -xzf "$ripgrep_archive" -C "$tmp_dir"
install -d "$HOME/.local/bin"
install -m 755 "$tmp_dir/shellcheck-$shellcheck_version/shellcheck" "$HOME/.local/bin/shellcheck"
install -m 755 "$tmp_dir/ripgrep-$ripgrep_version-$ripgrep_arch-unknown-linux-musl/rg" "$HOME/.local/bin/rg"
GOBIN="$HOME/.local/bin" go install mvdan.cc/sh/v3/cmd/shfmt@v3.13.1
GOBIN="$HOME/.local/bin" go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.12

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

shell_guidance="- For shell-script work, use \`shellcheck <files> && shfmt -d <files>\` for validation; target relevant files instead of reading every script just to check it."
json_guidance="- For JSON, especially \`gh api\` output, use \`jq\` or \`gh --jq\` to extract only the fields needed instead of loading raw JSON."
search_guidance="- For codebase searches, use \`rg <pattern>\` and \`rg --files\` to narrow the relevant files instead of reading directories or whole files."
workflow_guidance="- For GitHub Actions workflows, run \`actionlint\` after changes."
for file in "$HOME/.codex/AGENTS.md" "$HOME/.claude/CLAUDE.md"; do
	mkdir -p "${file%/*}"
	touch "$file"
	for guidance in "$shell_guidance" "$json_guidance" "$search_guidance" "$workflow_guidance"; do
		grep -Fqx -- "$guidance" "$file" || printf '%s\n' "$guidance" >>"$file"
	done
done

printf '\nAI shell tools available to Codex and Claude Code:\n'
shellcheck --version | sed -n 's/^version: /  shellcheck /p'
printf '  shfmt %s\n' "$(shfmt --version)"
printf '  %s\n' "$(jq --version)"
printf '  %s\n' "$(rg --version | sed -n '1p')"
printf '  actionlint %s\n' "$(actionlint -version | sed -n '1p')"
