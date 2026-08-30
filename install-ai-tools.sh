#!/usr/bin/env bash
# Install Codex, Claude Code, and shared skills for the current user.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
	echo "Run as your regular user, not with sudo." >&2
	exit 1
fi

# Include tools installed by the preceding user-level installer step.
export PATH="$HOME/.local/bin:$PATH"
for command in actionlint curl jq npx rg shellcheck shfmt; do
	command -v "$command" >/dev/null || {
		echo "$command is required. Run the complete installer first." >&2
		exit 1
	}
done

curl -fsSL https://chatgpt.com/codex/install.sh | sh
curl -fsSL https://claude.ai/install.sh | bash

command -v claude >/dev/null || {
	echo "Claude Code installation failed." >&2
	exit 1
}
command -v codex >/dev/null || {
	echo "Codex installation failed." >&2
	exit 1
}

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
