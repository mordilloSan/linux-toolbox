#!/usr/bin/env bash
# Install Codex, Claude Code, and shared skills for the current user.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
	echo "Run as your regular user, not with sudo." >&2
	exit 1
fi

# Include tools installed by the preceding user-level installer step.
export PATH="$HOME/.local/bin:$PATH"
if ! command -v bwrap >/dev/null; then
	command -v sudo >/dev/null || {
		echo "sudo is required to install bubblewrap." >&2
		exit 1
	}
	if command -v apt-get >/dev/null && command -v dpkg >/dev/null; then
		sudo apt-get install -y -qq bubblewrap
	elif command -v dnf >/dev/null && command -v rpm >/dev/null; then
		sudo dnf install -y -q bubblewrap
	elif command -v yum >/dev/null && command -v rpm >/dev/null; then
		sudo yum install -y -q bubblewrap
	else
		echo "Install bubblewrap with your system package manager." >&2
		exit 1
	fi
fi
for command in actionlint curl jq npx rg shellcheck shfmt; do
	command -v "$command" >/dev/null || {
		echo "$command is required. Run the complete installer first." >&2
		exit 1
	}
done

printf ' [ INFO ] Installing Claude Code...\n'
curl -fsSL https://claude.ai/install.sh | bash
command -v claude >/dev/null || {
	echo "Claude Code installation failed." >&2
	exit 1
}
printf ' [  OK  ] Claude Code installed\n'

printf ' [ INFO ] Installing Codex...\n'
curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
command -v codex >/dev/null || {
	echo "Codex installation failed." >&2
	exit 1
}
printf ' [  OK  ] Codex installed\n'

printf ' [ INFO ] Installing AI plugins and skills...\n'
claude plugin marketplace add DietrichGebert/ponytail
claude plugin install ponytail@ponytail --yes
codex plugin marketplace add DietrichGebert/ponytail
codex plugin add ponytail@ponytail

npx --yes skills add jakubkrehel/skills --global \
	--agent codex claude-code --skill '*' 
npx --yes skills add vercel-labs/skills@find-skills --global \
	--agent codex claude-code 
npx --yes skills add https://github.com/samber/cc-skills-golang --global \
	--agent codex claude-code \
	--skill golang-concurrency golang-context golang-security \
	golang-troubleshooting 
printf ' [  OK  ] AI plugins and skills installed\n'

if [[ ${LINUX_TOOLBOX_SKIP_AGENT_GUIDANCE:-0} != 1 ]]; then
	shell_guidance="- For shell-script work, use \`shellcheck <files> && shfmt -d <files>\` for validation; target relevant files instead of reading every script just to check it."
	json_guidance="- For JSON, especially \`gh api\` output, use \`jq\` or \`gh --jq\` to extract only the fields needed instead of loading raw JSON."
	search_guidance="- For codebase searches, use \`rg <pattern>\` and \`rg --files\` to narrow the relevant files instead of reading directories or whole files."
	workflow_guidance="- For GitHub Actions workflows, run \`actionlint\` after changes."
	for file in "$HOME/.codex/AGENTS.md" "$HOME/.claude/CLAUDE.md"; do
		mkdir -p "${file%/*}"
		if [[ -s $file ]] && ! tail -c 1 "$file" | grep -q '^$'; then
			printf '\n' >>"$file"
		fi
		for guidance in "$shell_guidance" "$json_guidance" "$search_guidance" "$workflow_guidance"; do
			grep -Fqxs -- "$guidance" "$file" || printf '%s\n' "$guidance" >>"$file"
		done
	done
fi
