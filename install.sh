#!/usr/bin/env bash
set -euo pipefail

if ((EUID == 0)); then
	echo "Run this installer as your regular user, not with sudo." >&2
	exit 1
fi

readonly RESET=$'\033[0m'
readonly GREEN=$'\033[38;5;154m'
readonly GREY=$'\033[90m'
readonly RED=$'\033[91m'
readonly YELLOW=$'\033[33m'
readonly BOLD=$'\033[1m'
readonly LINE=' ───────────────────────────────────────────────────────'

base_url=https://raw.githubusercontent.com/mordilloSan/linux-toolbox/main
script_dir=
# Only a checkout runs its sibling scripts; a release copy (base_url rewritten) always runs its own release's.
if [[ $base_url == */main && -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
	script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fi

load_script() {
	local name=$1 text
	if [[ -n $script_dir && -f $script_dir/$name ]]; then
		cat -- "$script_dir/$name"
	else
		# Download in full first: bash would run the partial last line of a cut-off download.
		text=$("${fetch[@]}" "$base_url/$name") || fail "Unable to download $name."
		printf '%s\n' "$text"
	fi
}

banner() {
	printf '\n%s%s%s\n %s%s%s\n%s%s%s\n' \
		"$GREEN" "$LINE" "$RESET" "$BOLD" "$1" "$RESET" "$GREEN" "$LINE" "$RESET"
}

step() {
	printf '\n %s[%s INFO %s]%s %s\n' "$GREY" "$BOLD" "$GREY" "$RESET" "$1"
}

ok() {
	printf ' %s[%s  OK  %s]%s %s\n' "$GREY" "$GREEN" "$GREY" "$RESET" "$1"
}

notice() {
	printf ' %s[%sNOTICE%s]%s %s\n' "$GREY" "$YELLOW" "$GREY" "$RESET" "$1"
}

fail() {
	printf ' %s[%sFAILED%s]%s %s\n' "$GREY" "$RED" "$GREY" "$RESET" "$1" >&2
	exit 1
}

selected() { [[ " $components " == *" $1 "* ]]; }

# Print "installed", or which of the given commands are missing.
installed_state() {
	local command missing=()
	for command; do
		command -v "$command" >/dev/null || missing+=("$command")
	done
	if ((${#missing[@]})); then
		echo "missing: ${missing[*]}"
	else
		echo installed
	fi
}

# Print the first line of a command's version output, or "not installed".
version_state() {
	local version
	command -v "$1" >/dev/null || {
		echo 'not installed'
		return
	}
	version=$("$@" 2>/dev/null | head -n 1) || true
	echo "${version:-installed}"
}

# Set the caller's git_state to the Git identity and GitHub sign-in, and git_ready=1 when both are set.
read_git_state() {
	local name email status account signed_in=0
	command -v git >/dev/null || {
		git_state='git not installed'
		return
	}
	name=$(git config --global --get user.name || true)
	email=$(git config --global --get user.email || true)
	if command -v gh >/dev/null && status=$(gh auth status --hostname github.com 2>&1 </dev/null); then
		signed_in=1
		account=$(sed -n 's/.*account \([^ ]*\).*/\1/p' <<<"$status" | head -n 1)
	fi
	if [[ -n $name && -n $email ]]; then git_state=$name; else git_state='no identity'; fi
	if ((! signed_in)); then
		git_state+=', not signed in to GitHub'
	elif [[ -n $account ]]; then
		git_state+=", GitHub $account"
	else
		git_state+=', signed in to GitHub'
	fi
	[[ -z $name || -z $email ]] || ((! signed_in)) || git_ready=1
}

# Show every component with its detected state, then read the selection.
choose_components() {
	local keys labels states i release='' git_state='' git_ready=0 interactive=1
	keys=(packages go node shell release claude codex git)
	labels=('System packages: git, gh, make, tar' Go 'Node.js LTS through nvm'
		'Shell tools: jq, ShellCheck, rg, shfmt' 'GitHub release flow' 'Claude Code' 'Codex CLI'
		'Git identity and GitHub sign-in')
	# 'gh extension list' needs a login; the extension's own help does not.
	if command -v gh >/dev/null && gh release-flow --help >/dev/null 2>&1 </dev/null; then
		release=installed
	fi
	read_git_state
	# GOTOOLCHAIN=local: show the installed Go, not a toolchain that a project in this folder asks for.
	states=(
		"$(installed_state git gh make tar)"
		"$(GOTOOLCHAIN=local version_state go env GOVERSION)"
		"$(version_state node --version)"
		"$(installed_state jq shellcheck shfmt rg actionlint)"
		"${release:-not installed}"
		"$(version_state claude --version)"
		"$(version_state codex --version)"
		"$git_state"
	)
	if grep -Eq '^ID="?ubuntu"?$' /etc/os-release 2>/dev/null; then
		keys+=(cleanup)
		labels+=('Ubuntu cleanup: remove Snaps and all Snap data')
		if command -v snap >/dev/null; then states+=('Snap present'); else states+=('Snap not present'); fi
	fi
	local count=${#keys[@]} picked=()
	for i in "${!keys[@]}"; do
		picked[i]=1
	done
	[[ ${keys[count - 1]} != cleanup ]] || picked[count - 1]=0
	if [[ ${LINUX_TOOLBOX_NONINTERACTIVE:-0} == 1 ]] || ! { exec 3<>/dev/tty; } 2>/dev/null; then
		interactive=0
	fi
	# Git setup asks on the terminal, so it starts checked only when something is missing and someone can answer.
	((interactive && ! git_ready)) || picked[7]=0

	if ((! interactive)); then
		printf '\n %s[?]%s Components to install or update:\n' "$YELLOW" "$RESET"
		for i in "${!keys[@]}"; do
			printf '     %s %d) %-47s %s%s%s\n' "$( ((picked[i])) && echo '[x]' || echo '[ ]')" \
				$((i + 1)) "${labels[i]}" "$GREY" "${states[i]}" "$RESET"
		done
	else
		pick_components
	fi
	components=
	for i in "${!keys[@]}"; do
		((picked[i] == 0)) || components+="${keys[i]} "
	done
}

# Arrow-key checklist on fd 3. Uses the caller's keys, labels, states and picked.
pick_components() {
	local count=${#keys[@]} cursor=0 key rest i drawn='' frame
	printf '\n %s[?]%s Components to install or update\n' "$YELLOW" "$RESET" >&3
	printf '     %sUp/Down move, Space or number toggles, Enter installs%s\n' "$GREY" "$RESET" >&3
	# Hide the terminal cursor while the list redraws; restore it on exit or Ctrl+C.
	printf '\033[?25l' >&3
	trap 'printf "\033[?25h" >&3' EXIT
	while :; do
		# Build the whole frame first and write it once, so the terminal never shows a half-drawn list.
		# Redraw in place after the first pass. No line wrap: a wrapped row would make the cursor-up miss.
		frame=''
		[[ -z $drawn ]] || frame+=$(printf '\033[%dA' "$count")
		drawn=1
		frame+=$'\033[?7l'
		for i in "${!keys[@]}"; do
			frame+=$(printf '\r\033[K   %s %s %d) %-47s %s%s%s\n' \
				"$( ((i == cursor)) && printf '%s>%s' "$GREEN" "$RESET" || echo ' ')" \
				"$( ((picked[i])) && printf '%s[x]%s' "$GREEN" "$RESET" || echo '[ ]')" \
				$((i + 1)) "${labels[i]}" "$GREY" "${states[i]}" "$RESET")$'\n'
		done
		frame+=$'\033[?7h'
		printf '%s' "$frame" >&3
		IFS= read -rsn1 key <&3 || key=
		case $key in
		'') break ;;
		' ') picked[cursor]=$((! picked[cursor])) ;;
		[1-9])
			if ((key <= count)); then
				cursor=$((key - 1))
				picked[cursor]=$((! picked[cursor]))
			fi
			;;
		$'\033')
			IFS= read -rsn2 -t 0.1 rest <&3 || rest=
			# Drop the rest of longer keys (F5 is ESC [15~, Shift+Down is ESC [1;2B) so its digits do not toggle items.
			[[ $rest != '['[0-9] ]] || while IFS= read -rsn1 -t 0.1 key <&3 && [[ $key != [~A-Za-z] ]]; do :; done
			case $rest in
			'[A' | OA) cursor=$(((cursor + count - 1) % count)) ;;
			'[B' | OB) cursor=$(((cursor + 1) % count)) ;;
			esac
			;;
		esac
	done
	printf '\033[?25h' >&3
	trap - EXIT
	exec 3>&-
}

step_number=0
run_step() {
	step "$((++step_number))/$step_total $1"
}

banner "Linux Toolbox Installer"

step "Preflight checks"
[[ $(uname -s) == Linux ]] || fail "This installer supports Linux only."
case $(uname -m) in
x86_64 | amd64 | aarch64 | arm64) ;;
*) fail "Unsupported architecture: $(uname -m)" ;;
esac
command -v sudo >/dev/null || fail "sudo is required."
if command -v curl >/dev/null; then
	# Give up after a minute with no data instead of hanging.
	fetch=(curl -fsSL --speed-limit 1 --speed-time 60)
elif command -v wget >/dev/null; then
	fetch=(wget -qO-)
else
	fail "curl or wget is required."
fi
sudo -v || fail "Unable to authenticate with sudo."
ok "Linux $(uname -m) is supported"

user_path=$PATH
# Detect tools from earlier runs that are not on the default PATH yet.
export PATH="${NVM_DIR:-$HOME/.nvm}/versions/node/current/bin:$HOME/.local/bin:$PATH"
choose_components
agents=()
for agent in claude codex; do
	! selected "$agent" || agents+=("$agent")
done
step_total=0
for component in packages go node shell release; do
	! selected "$component" || ((++step_total))
done
((${#agents[@]} == 0)) || ((++step_total))
# sudo resets the environment, so pass the prompt mode and any proxy settings on explicitly.
root_env=("LINUX_TOOLBOX_NONINTERACTIVE=${LINUX_TOOLBOX_NONINTERACTIVE:-0}")
for var in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
	[[ -z ${!var:-} ]] || root_env+=("$var=${!var}")
done
as_root=(sudo env "${root_env[@]}" bash)
commands=()

if selected packages; then
	run_step "System dependencies"
	load_script install-dependencies.sh | "${as_root[@]}"
	ok "System dependencies installed"
	commands+=(git gh make)
fi

if selected go; then
	run_step "Go"
	load_script install-go.sh | "${as_root[@]}"
	go_path=$(command -v go || true)
	# The root step cannot see a Go on the user's PATH.
	[[ -z $go_path || $(readlink -f "$go_path") == /usr/local/go/* ]] ||
		notice "go on your PATH is $go_path, not /usr/local/bin/go."
	# Claude Code's gopls-lsp plugin runs gopls; as the user it lands in GOBIN (~/go/bin by default).
	if output=$(cd "$HOME" && go install golang.org/x/tools/gopls@latest 2>&1 </dev/null); then
		ok "gopls installed"
	else
		printf '%s\n' "$output" >&2
		notice "Could not install gopls; run: go install golang.org/x/tools/gopls@latest"
	fi
	commands+=(go)
fi

if selected node; then
	run_step "Node.js"
	load_script install-node.sh | bash
	commands+=(node npm npx)
fi

if selected shell; then
	run_step "Shell tools"
	load_script install-shell-tools.sh | bash
	ok "Shell tools installed"
	commands+=(jq shellcheck shfmt rg actionlint)
fi

if selected release; then
	run_step "GitHub release flow"
	load_script install-release-flow.sh | bash
	ok "GitHub release flow installed"
fi

if ((${#agents[@]})); then
	run_step "AI tools and skills"
	ai_tools_script=$(load_script install-ai-tools.sh)
	if ! bash -c "$ai_tools_script" -- "${agents[@]}" </dev/null; then
		fail "Unable to install AI tools and skills."
	fi
	ok "AI tools and skills installed"
	commands+=("${agents[@]}" bwrap socat)
fi

# Before the check, so a kept Snap tool that the cleanup removes is reported missing.
if selected cleanup; then
	step "Ubuntu cleanup"
	load_script ubuntu-cleanup.sh | sudo bash
	ok "Ubuntu cleanup complete"
	# A gh Snap pointed Git's GitHub sign-in into /snap, which the cleanup just removed.
	if git config --global --get-regexp '^credential\..*helper$' 2>/dev/null | grep -q '!/snap/' &&
		command -v gh >/dev/null; then
		gh auth setup-git --hostname github.com </dev/null ||
			notice "Run gh auth setup-git to repair Git's GitHub sign-in."
	fi
fi

step "Verifying installation"
for command in "${commands[@]}"; do
	command -v "$command" >/dev/null || fail "$command was not found after installation."
done
if selected release; then
	gh release-flow --help >/dev/null || fail "gh-release-flow was not found after installation."
fi
ok "All installed commands are available"

if selected git; then
	git_setup=$(load_script setup-git.sh)
	step "Git identity"
	if bash -c "$git_setup" -- identity </dev/tty; then
		ok "Git identity configured"
	else
		notice "Git identity was not changed"
	fi
	step "GitHub authentication"
	if bash -c "$git_setup" -- github </dev/tty; then
		ok "GitHub authentication configured"
	else
		notice "GitHub authentication was not changed"
	fi
else
	notice "Git and GitHub setup skipped"
fi

# ~/.profile adds ~/.local/bin only when it existed at login, so new terminals would miss these tools.
if [[ -d $HOME/.local/bin && :$user_path: != *":$HOME/.local/bin:"* ]]; then
	# shellcheck disable=SC2016
	path_line='export PATH="$HOME/.local/bin:$PATH"'
	grep -Fqxs -- "$path_line" "$HOME/.bashrc" || printf '\n%s\n' "$path_line" >>"$HOME/.bashrc"
	notice "Open a new terminal so your shell finds the tools in ~/.local/bin."
fi

banner "Setup complete"
