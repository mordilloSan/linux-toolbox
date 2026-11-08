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
		run_quiet sudo apt-get -o DPkg::Lock::Timeout=300 install -y -qq bubblewrap
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
	# Ponytail comes from this repository's marketplace, pinned to the commit in .claude-plugin/marketplace.json.
	claude plugin marketplace update linux-toolbox >/dev/null 2>&1 ||
		run_quiet claude plugin marketplace add https://github.com/mordilloSan/linux-toolbox.git
	run_quiet claude plugin install ponytail@linux-toolbox --yes
	run_quiet claude plugin update ponytail@linux-toolbox
	# Drop the unpinned copy older versions installed, only once the pinned one is in place.
	claude plugin uninstall ponytail@ponytail >/dev/null 2>&1 || true
	claude plugin marketplace remove ponytail >/dev/null 2>&1 || true
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
# Skill sources are pinned to reviewed commits (#sha); bump a sha after reading the upstream changes.
info "Installing interface skills..."
run_quiet npx --yes skills add jakubkrehel/skills#157da62016338e8693dcff93d47154a9e36f2157 --global \
	--agent "${skill_agents[@]}" --skill "${interface_skills[@]}" --yes
for skill in "${interface_skills[@]}"; do
	ok "$skill installed"
done

info "Installing find-skills..."
run_quiet npx --yes skills add vercel-labs/skills#d3701c11b1101251af14c9d148f026e1a47ebe17 --global \
	--agent "${skill_agents[@]}" --skill find-skills --yes
ok "find-skills installed"

if selected codex; then
	info "Installing context-handoff..."
	run_quiet npx --yes skills add timyeou1234/context-handoff#00f4ad1af40ecdcd3bad1c7c9a31423b0fa1b272 --global \
		--agent codex --skill context-handoff --yes
	ok "context-handoff installed"
fi

go_skills=(golang-concurrency golang-context golang-security golang-troubleshooting)
info "Installing Go skills..."
run_quiet npx --yes skills add samber/cc-skills-golang#bb1d43d98a3f8ab639a0042f90d0ec524e39a477 --global \
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

if selected claude && [[ ${LINUX_TOOLBOX_SKIP_AGENT_GUIDANCE:-0} != 1 ]]; then
	info "Configuring Claude Code settings..."
	settings="$HOME/.claude/settings.json"
	lint_hook="$HOME/.claude/hooks/linux-toolbox-lint.sh"
	# Exit 2 blocks the call; any error of the hook itself falls through to exit 0, so it never blocks by mistake.
	# shortcut: misses messages read from a file (git commit -F); move to a script hook if that shows up.
	guard_command=$(
		cat <<-'EOF'
			jq -e '.tool_input.command // "" | test("co-authored-by"; "i") and test("\\bcommit\\b")' >/dev/null && { echo 'linux-toolbox: commits carry no Co-Authored-By trailer; remove it and run the command again.' >&2; exit 2; }; exit 0
		EOF
	)
	mkdir -p "${lint_hook%/*}"
	cat >"$lint_hook" <<'EOF'
#!/usr/bin/env bash
# Installed by linux-toolbox: lints the file Claude Code just edited.
# Findings go to stderr with exit 2, which Claude reads; a missing tool or any other problem exits 0.
file=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -f $file ]] || exit 0
lint_shell() {
	! command -v shellcheck >/dev/null || shellcheck -e SC1091 -- "$1"
	# Formatting is only checked in repositories that already use shfmt.
	if command -v shfmt >/dev/null && git -C "${1%/*}" grep -qI shfmt 2>/dev/null; then
		shfmt -d -- "$1"
	fi
}
case $file in
*/.github/workflows/*.yml | */.github/workflows/*.yaml)
	command -v actionlint >/dev/null || exit 0
	# actionlint exits 1 for findings; other codes are its own errors.
	findings=$(actionlint -no-color "$file" 2>&1) || [[ $? == 1 ]] || exit 0
	;;
*.sh | *.bash) findings=$(lint_shell "$file" 2>&1) ;;
*)
	head -n 1 -- "$file" | grep -Eq '^#!.*\b(ba|da)?sh\b' || exit 0
	findings=$(lint_shell "$file" 2>&1)
	;;
esac
[[ -n $findings ]] || exit 0
printf 'linux-toolbox lint: fix these findings in %s\n%s\n' "$file" "$findings" >&2
exit 2
EOF
	[[ -s $settings ]] || printf '{}\n' >"$settings"
	# Adds missing rules without reordering yours, and replaces older linux-toolbox hooks instead of stacking them.
	if updated=$(jq --arg guard "$guard_command" --arg lint "bash \"\$HOME/.claude/hooks/${lint_hook##*/}\"" '
		def merge_rules($key; $rules): .permissions[$key] = ((.permissions[$key] // []) as $old | $old + ($rules - $old));
		def without_ours: [(. // [])[] | del(.hooks[]? | select((.command // "") | test("/hooks/linux-toolbox-lint\\.sh|linux-toolbox: commits"))) | select(.hooks != [])];
		merge_rules("deny"; ["Bash(git push:*)", "Bash(git tag:*)", "Bash(gh release create:*)"])
		| merge_rules("ask"; ["Bash(git commit:*)", "Bash(gh pr merge:*)"])
		| .hooks.PreToolUse = (.hooks.PreToolUse | without_ours) + [{matcher: "Bash", hooks: [{type: "command", command: $guard}]}]
		| .hooks.PostToolUse = (.hooks.PostToolUse | without_ours) + [{matcher: "Edit|Write|MultiEdit", hooks: [{type: "command", command: $lint}]}]
	' "$settings" 2>/dev/null) && [[ -n $updated ]]; then
		printf '%s\n' "$updated" >"$settings"
		ok "Claude Code settings configured"
	else
		printf ' [NOTICE] %s is not valid JSON; Claude Code settings left unchanged.\n' "$settings" >&2
	fi
fi
