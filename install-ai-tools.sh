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
	# Never change the markers: older blocks are found by them and replaced whole on every run.
	guidance_begin='<!-- linux-toolbox guidance: managed by install-ai-tools.sh, edits inside are replaced -->'
	guidance_end='<!-- end linux-toolbox guidance -->'
	guidance_rules=$(
		cat <<-'EOF'
			- For shell-script work, use `shellcheck <files> && shfmt -d <files>` for validation; target relevant files instead of reading every script just to check it.
			- For JSON, especially `gh api` output, use `jq` or `gh --jq` to extract only the fields needed instead of loading raw JSON.
			- For codebase searches, use `rg <pattern>` and `rg --files` to narrow the relevant files instead of reading directories or whole files.
			- For GitHub Actions workflows, run `actionlint` after changes.
			- To read code, locate it with `rg -n` and read only the relevant line range; don't `cat` whole files or several files at once, since everything read stays in context for the rest of the session.
			- When spawning a subagent, name the exact files or line ranges and one deliverable; do quick lookups inline instead of delegating them.
			- After changing code (not after reviews or questions), end with a suggested commit message in Conventional Commits format (`type(scope): subject`, scope optional; types like feat, fix, docs, refactor, test, chore): an imperative subject of at most 72 characters, a blank line, then a body explaining what and why, with no Co-Authored-By trailers. Never create, amend, or push commits unless asked.
			- Never read, print, or commit secrets such as `.env` files, tokens, or private keys; refer to them by name.
			- In repositories with `dev/vX.Y.Z` release branches, releases go through gh-release-flow (`gh release-flow start-dev vX.Y.Z`, `open-pr`, `merge`); never create tags or GitHub Releases by hand, and merge only when asked.
		EOF
	)
	guidance_files=()
	! selected codex || guidance_files+=("$HOME/.codex/AGENTS.md")
	! selected claude || guidance_files+=("$HOME/.claude/CLAUDE.md")
	for file in "${guidance_files[@]}"; do
		mkdir -p "${file%/*}"
		touch "$file"
		# A start marker without its end marker would make the rewrite drop the rest of the file.
		if grep -Fqx -- "$guidance_begin" "$file" && ! grep -Fqx -- "$guidance_end" "$file"; then
			printf ' [NOTICE] %s has a linux-toolbox start marker but no end marker; left unchanged.\n' "$file" >&2
			continue
		fi
		# Replace the block in place, or append it; drop loose copies of its rules left by older installers.
		content=$(GUIDANCE_BEGIN=$guidance_begin GUIDANCE_END=$guidance_end GUIDANCE_RULES=$guidance_rules awk '
			function block() {
				print ENVIRON["GUIDANCE_BEGIN"]
				for (i = 1; i <= n; i++) print rules[i]
				print ENVIRON["GUIDANCE_END"]
				done = 1
			}
			BEGIN {
				n = split(ENVIRON["GUIDANCE_RULES"], rules, "\n")
				for (i = 1; i <= n; i++) managed[rules[i]]
			}
			$0 == ENVIRON["GUIDANCE_BEGIN"] { skip = 1; if (!done) block(); next }
			skip { if ($0 == ENVIRON["GUIDANCE_END"]) skip = 0; next }
			$0 in managed { next }
			{ print; last = $0; printed = 1 }
			END { if (!done) { if (printed && last != "") print ""; block() } }
		' "$file")
		printf '%s\n' "$content" >"$file"
	done
	ok "AI agent guidance configured"
fi
