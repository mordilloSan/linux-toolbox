#!/usr/bin/env bash
# Install Codex, Claude Code, and shared skills for the current user.
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

run_quiet() {
	local output
	if ! output=$("$@" </dev/null 2>&1); then
		[[ -z $output ]] || printf '%s\n' "$output" >&2
		return 1
	fi
}

run_installer() {
	local url=$1 output
	shift
	if ! output=$({ curl -fsSL "$url" | "$@"; } 2>&1); then
		[[ -z $output ]] || printf '%s\n' "$output" >&2
		return 1
	fi
}

# Include tools installed by the preceding user-level installer step.
export PATH="$HOME/.local/bin:$PATH"
info "Installing or updating bubblewrap..."
if ! command -v bwrap >/dev/null; then
	command -v sudo >/dev/null || {
		echo "sudo is required to install bubblewrap." >&2
		exit 1
	}
	if command -v apt-get >/dev/null && command -v dpkg >/dev/null; then
		run_quiet sudo apt-get install -y -qq bubblewrap
	elif command -v dnf >/dev/null && command -v rpm >/dev/null; then
		run_quiet sudo dnf install -y -q bubblewrap
	elif command -v yum >/dev/null && command -v rpm >/dev/null; then
		run_quiet sudo yum install -y -q bubblewrap
	else
		echo "Install bubblewrap with your system package manager." >&2
		exit 1
	fi
fi
ok "bubblewrap installed"
for command in actionlint curl jq npx rg shellcheck shfmt; do
	command -v "$command" >/dev/null || {
		echo "$command is required. Run the complete installer first." >&2
		exit 1
	}
done

info "Installing or updating Claude Code..."
run_installer https://claude.ai/install.sh bash
command -v claude >/dev/null || {
	echo "Claude Code installation failed." >&2
	exit 1
}
ok "Claude Code installed"

info "Installing or updating Codex..."
run_installer https://chatgpt.com/codex/install.sh env CODEX_NON_INTERACTIVE=1 sh
command -v codex >/dev/null || {
	echo "Codex installation failed." >&2
	exit 1
}
ok "Codex installed"

info "Installing or updating Ponytail..."
run_quiet claude plugin marketplace add DietrichGebert/ponytail
run_quiet claude plugin install ponytail@ponytail --yes
run_quiet codex plugin marketplace add DietrichGebert/ponytail
run_quiet codex plugin add ponytail@ponytail
ok "Ponytail installed"

interface_skills=(
	better-accessibility better-colors better-interface better-layout
	better-typography better-ui better-writing break explain-interface
	interface-review variant
)
info "Installing interface skills..."
run_quiet npx --yes skills add jakubkrehel/skills --global \
	--agent codex claude-code --skill "${interface_skills[@]}" --yes
for skill in "${interface_skills[@]}"; do
	ok "$skill installed"
done

info "Installing find-skills..."
run_quiet npx --yes skills add vercel-labs/skills@find-skills --global \
	--agent codex claude-code --yes
ok "find-skills installed"

info "Installing context-handoff..."
run_quiet npx --yes skills add timyeou1234/context-handoff --global \
	--agent codex claude-code --skill context-handoff --yes
ok "context-handoff installed"

go_skills=(golang-concurrency golang-context golang-security golang-troubleshooting)
info "Installing Go skills..."
run_quiet npx --yes skills add https://github.com/samber/cc-skills-golang --global \
	--agent codex claude-code \
	--skill "${go_skills[@]}" --yes
for skill in "${go_skills[@]}"; do
	ok "$skill installed"
done

if [[ ${LINUX_TOOLBOX_SKIP_AGENT_GUIDANCE:-0} != 1 ]]; then
	info "Configuring AI agent guidance..."
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
	ok "AI agent guidance configured"
fi
