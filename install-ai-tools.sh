#!/usr/bin/env bash
# Install Codex, Claude Code, and shared skills for the current user.
# Usage: install-ai-tools.sh [claude] [codex]   (no arguments installs both)
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

agents=("$@")
((${#agents[@]})) || agents=(claude codex)
for agent in "${agents[@]}"; do
	[[ $agent == claude || $agent == codex ]] || {
		echo "Unknown agent: $agent (expected claude or codex)" >&2
		exit 1
	}
done
selected() { [[ " ${agents[*]} " == *" $1 "* ]]; }

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

# Print a command's version number, or nothing when it is missing.
version_of() {
	command -v "$1" >/dev/null || return 0
	"$1" --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+)+' | head -n 1 || true
}

# Install or update an agent unless it already runs the latest version.
# Arguments: name, command, latest version (may be empty), installer URL and runner.
install_agent() {
	local name=$1 command=$2 latest=$3 before after
	shift 3
	before=$(version_of "$command")
	if [[ -n $before && $before == "$latest" ]]; then
		ok "$name $before is already up to date"
		return
	fi
	info "Installing or updating $name${before:+ (found $before)}..."
	run_installer "$@"
	command -v "$command" >/dev/null || {
		echo "$name installation failed." >&2
		exit 1
	}
	after=$(version_of "$command")
	if [[ -n $before && $before == "$after" ]]; then
		ok "$name $after is already up to date"
	elif [[ -n $before && -n $after ]]; then
		ok "$name updated from $before to $after"
	else
		ok "$name${after:+ $after} installed"
	fi
}

skill_agents=()
if selected claude; then
	latest=$(curl -fsSL https://downloads.claude.ai/claude-code-releases/latest 2>/dev/null || true)
	install_agent 'Claude Code' claude "$latest" https://claude.ai/install.sh bash
	skill_agents+=(claude-code)
fi

if selected codex; then
	latest=$(curl -fsSL https://releases.openai.com/codex/channels/latest 2>/dev/null |
		sed -n 's/.*"tag_name": *"rust-v\([^"]*\)".*/\1/p' || true)
	install_agent Codex codex "$latest" https://chatgpt.com/codex/install.sh env CODEX_NON_INTERACTIVE=1 sh
	skill_agents=(codex "${skill_agents[@]}")
fi

info "Installing or updating Ponytail..."
if selected claude; then
	run_quiet claude plugin marketplace add DietrichGebert/ponytail
	run_quiet claude plugin install ponytail@ponytail --yes
fi
if selected codex; then
	run_quiet codex plugin marketplace add DietrichGebert/ponytail
	run_quiet codex plugin add ponytail@ponytail
fi
ok "Ponytail installed"

interface_skills=(
	better-accessibility better-colors better-interface better-layout
	better-typography better-ui better-writing break explain-interface
	interface-review variant
)
info "Installing interface skills..."
run_quiet npx --yes skills add jakubkrehel/skills --global \
	--agent "${skill_agents[@]}" --skill "${interface_skills[@]}" --yes
for skill in "${interface_skills[@]}"; do
	ok "$skill installed"
done

info "Installing find-skills..."
run_quiet npx --yes skills add vercel-labs/skills@find-skills --global \
	--agent "${skill_agents[@]}" --yes
ok "find-skills installed"

if selected codex; then
	info "Installing context-handoff..."
	run_quiet npx --yes skills add timyeou1234/context-handoff --global \
		--agent codex --skill context-handoff --yes
	ok "context-handoff installed"
fi

go_skills=(golang-concurrency golang-context golang-security golang-troubleshooting)
info "Installing Go skills..."
run_quiet npx --yes skills add https://github.com/samber/cc-skills-golang --global \
	--agent "${skill_agents[@]}" \
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
	guidance_files=()
	! selected codex || guidance_files+=("$HOME/.codex/AGENTS.md")
	! selected claude || guidance_files+=("$HOME/.claude/CLAUDE.md")
	for file in "${guidance_files[@]}"; do
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
