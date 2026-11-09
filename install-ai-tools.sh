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
	if ! output=$({ curl -fsSL --speed-limit 1 --speed-time 60 "$url" | "$@"; } 2>&1); then
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
# npx and 'claude plugin' read the project in the current folder, so start from the home folder instead.
cd "$HOME" 2>/dev/null || cd /
claude_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
codex_dir=${CODEX_HOME:-$HOME/.codex}
for command in curl jq npx; do
	command -v "$command" >/dev/null || {
		echo "$command is required. Run the complete installer first." >&2
		exit 1
	}
done
# Claude Code's sandbox needs both bubblewrap and socat on Linux.
info "Installing or updating bubblewrap and socat..."
if ! command -v bwrap >/dev/null || ! command -v socat >/dev/null; then
	command -v sudo >/dev/null || {
		echo "sudo is required to install bubblewrap and socat." >&2
		exit 1
	}
	# sudo resets the environment, so pass any proxy settings on explicitly.
	root_env=()
	for var in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
		[[ -z ${!var:-} ]] || root_env+=("$var=${!var}")
	done
	if command -v apt-get >/dev/null && command -v dpkg >/dev/null; then
		run_quiet sudo env "${root_env[@]}" apt-get -o DPkg::Lock::Timeout=300 install -y -qq bubblewrap socat
	elif command -v dnf >/dev/null && command -v rpm >/dev/null; then
		run_quiet sudo env "${root_env[@]}" dnf install -y -q bubblewrap socat
	else
		echo "Install bubblewrap and socat with your system package manager." >&2
		exit 1
	fi
fi
# Ubuntu 23.10+ blocks unprivileged user namespaces, and bwrap then needs an AppArmor profile.
if [[ $(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null) == 1 ]] &&
	! bwrap --unshare-user --unshare-net --dev-bind / / true 2>/dev/null; then
	printf ' [NOTICE] AppArmor blocks bubblewrap, so the agent sandbox is off. See https://code.claude.com/docs/en/sandboxing#add-an-apparmor-profile-for-bubblewrap\n' >&2
fi
ok "bubblewrap and socat installed"

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
	# Users on the stable channel run a release about a week behind 'latest'; compare with their channel.
	case $(jq -r '.autoUpdatesChannel // empty' "$claude_dir/settings.json" 2>/dev/null) in
	stable | rc) channel=stable ;;
	*) channel=latest ;;
	esac
	latest=$(curl -fsSL --speed-limit 1 --speed-time 60 "https://downloads.claude.ai/claude-code-releases/$channel" 2>/dev/null || true)
	install_agent 'Claude Code' claude "$latest" https://claude.ai/install.sh bash
	skill_agents+=(claude-code)
fi

if selected codex; then
	latest=$(curl -fsSL --speed-limit 1 --speed-time 60 https://releases.openai.com/codex/channels/latest 2>/dev/null |
		sed -n 's/.*"tag_name": *"rust-v\([^"]*\)".*/\1/p' || true)
	install_agent Codex codex "$latest" https://chatgpt.com/codex/install.sh env CODEX_NON_INTERACTIVE=1 sh
	skill_agents=(codex "${skill_agents[@]}")
fi

if selected claude; then
	info "Installing the Go and TypeScript language server plugins..."
	# Anthropic's official marketplace; Claude Code normally has it already.
	claude plugin marketplace update claude-plugins-official >/dev/null 2>&1 ||
		run_quiet claude plugin marketplace add anthropics/claude-plugins-official
	# They run gopls and typescript-language-server, which the Go and Node.js steps install.
	for plugin in gopls-lsp typescript-lsp; do
		run_quiet claude plugin install "$plugin@claude-plugins-official" --yes
		ok "$plugin installed"
	done
fi

interface_skills=(
	better-accessibility better-colors better-interface better-layout
	better-typography better-ui better-writing break explain-interface
	interface-review variant
)
# The skills CLI version and skill sources (#sha) are pinned; bump both after reading the upstream changes.
# The skills CLI reports installs to skills.sh unless this is set.
export DO_NOT_TRACK=1
info "Installing interface skills..."
run_quiet npx --yes skills@1.7.6 add jakubkrehel/skills#157da62016338e8693dcff93d47154a9e36f2157 --global \
	--agent "${skill_agents[@]}" --skill "${interface_skills[@]}" --yes
for skill in "${interface_skills[@]}"; do
	ok "$skill installed"
done

info "Installing find-skills..."
run_quiet npx --yes skills@1.7.6 add vercel-labs/skills#d3701c11b1101251af14c9d148f026e1a47ebe17 --global \
	--agent "${skill_agents[@]}" --skill find-skills --yes
ok "find-skills installed"

if selected codex; then
	info "Installing context-handoff..."
	run_quiet npx --yes skills@1.7.6 add timyeou1234/context-handoff#00f4ad1af40ecdcd3bad1c7c9a31423b0fa1b272 --global \
		--agent codex --skill context-handoff --yes
	ok "context-handoff installed"
fi

go_skills=(
	golang-concurrency golang-context golang-error-handling golang-lint golang-modernize
	golang-security golang-stretchr-testify golang-testing golang-troubleshooting
)
info "Installing Go skills..."
run_quiet npx --yes skills@1.7.6 add samber/cc-skills-golang#bb1d43d98a3f8ab639a0042f90d0ec524e39a477 --global \
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
	! selected codex || guidance_files+=("$codex_dir/AGENTS.md")
	! selected claude || guidance_files+=("$claude_dir/CLAUDE.md")
	for file in "${guidance_files[@]}"; do
		mkdir -p "${file%/*}"
		touch "$file"
		# Both awk passes drop Windows line endings first, so markers in a CRLF file still match.
		# A start marker not closed by a later end marker would make the rewrite drop the rest of the file.
		if ! GUIDANCE_BEGIN=$guidance_begin GUIDANCE_END=$guidance_end awk '
			{ sub(/\r$/, "") }
			$0 == ENVIRON["GUIDANCE_BEGIN"] { open = 1 }
			$0 == ENVIRON["GUIDANCE_END"] { open = 0 }
			END { exit open }
		' "$file"; then
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
			{ sub(/\r$/, "") }
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
	settings="$claude_dir/settings.json"
	lint_hook="$claude_dir/hooks/linux-toolbox-lint.sh"
	mkdir -p "${lint_hook%/*}"
	cat >"$lint_hook" <<'EOF'
#!/usr/bin/env bash
# Installed by linux-toolbox: lints the file Claude Code just edited.
# Findings go to stderr with exit 2, which Claude reads; a missing tool or any other problem exits 0.
file=$(jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ -f $file ]] || exit 0
lint_shell() {
	# SC1071: a .sh file for a shell ShellCheck cannot read, such as zsh.
	! command -v shellcheck >/dev/null || shellcheck -e SC1091,SC1071 -- "$1"
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
	# attribution.commit "" stops Claude Code adding Co-Authored-By; the removal keeps dropping the older guard hook.
	# jq reads the file from a pipe, which a sandboxed Snap jq can do even though it cannot open home files.
	if updated=$(jq --arg lint "bash $(printf %q "$lint_hook")" '
		def merge_rules($key; $rules): .permissions[$key] = ((.permissions[$key] // []) as $old | $old + ($rules - $old));
		def without_ours: [(. // [])[] | del(.hooks[]? | select((.command // "") | test("/hooks/linux-toolbox-lint\\.sh|linux-toolbox: commits"))) | select(.hooks != [])];
		merge_rules("deny"; ["Bash(git push:*)", "Bash(git tag:*)", "Bash(gh release create:*)"])
		| merge_rules("ask"; ["Bash(git commit:*)", "Bash(gh pr merge:*)"])
		| if .attribution == false then . else .attribution.commit //= "" | if .includeCoAuthoredBy == false then .attribution.pr //= "" else . end end
		| .hooks.PreToolUse = (.hooks.PreToolUse | without_ours)
		| .hooks.PostToolUse = (.hooks.PostToolUse | without_ours) + [{matcher: "Edit|Write|MultiEdit", hooks: [{type: "command", command: $lint}]}]
	' < <(cat -- "$settings") 2>/dev/null) && [[ -n $updated ]]; then
		printf '%s\n' "$updated" >"$settings"
		ok "Claude Code settings configured"
	else
		printf ' [NOTICE] %s is not valid JSON; Claude Code settings left unchanged.\n' "$settings" >&2
	fi
fi
