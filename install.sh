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
if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
	script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fi

load_script() {
	local name=$1
	if [[ -n $script_dir && -f $script_dir/$name ]]; then
		cat -- "$script_dir/$name"
	else
		"${fetch[@]}" "$base_url/$name"
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

# Ask on the terminal. No terminal or LINUX_TOOLBOX_NONINTERACTIVE=1 answers No.
confirm() {
	local answer
	[[ ${LINUX_TOOLBOX_NONINTERACTIVE:-0} != 1 ]] || return 1
	{ exec 3<>/dev/tty; } 2>/dev/null || return 1
	printf '\n %s[?]%s %s [y/N] ' "$YELLOW" "$RESET" "$1" >&3
	IFS= read -r answer <&3 || answer=
	exec 3>&-
	[[ $answer == [yY] ]]
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

# Show every component with its detected state, then read the selection.
choose_components() {
	local keys labels states i release=
	keys=(packages go node shell release claude codex)
	labels=('System packages: git, gh, make, tar' Go 'Node.js LTS through nvm'
		'Shell tools: jq, ShellCheck, rg, shfmt' 'GitHub release flow' 'Claude Code' 'Codex CLI')
	if command -v gh >/dev/null && gh extension list 2>/dev/null | grep -q release-flow; then
		release=installed
	fi
	states=(
		"$(installed_state git gh make tar)"
		"$(version_state go env GOVERSION)"
		"$(version_state node --version)"
		"$(installed_state jq shellcheck shfmt rg actionlint)"
		"${release:-not installed}"
		"$(version_state claude --version)"
		"$(version_state codex --version)"
	)
	if grep -Eq '^ID="?ubuntu"?$' /etc/os-release 2>/dev/null; then
		keys+=(cleanup)
		labels+=('Ubuntu cleanup: remove Snap, disable MOTD news')
		if command -v snap >/dev/null; then states+=('Snap present'); else states+=('Snap not present'); fi
	fi
	local count=${#keys[@]} picked=()
	for i in "${!keys[@]}"; do
		picked[i]=1
	done
	[[ ${keys[count - 1]} != cleanup ]] || picked[count - 1]=0

	if [[ ${LINUX_TOOLBOX_NONINTERACTIVE:-0} == 1 ]] || ! { exec 3<>/dev/tty; } 2>/dev/null; then
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
	local count=${#keys[@]} cursor=0 key rest i drawn=''
	printf '\n %s[?]%s Components to install or update\n' "$YELLOW" "$RESET" >&3
	printf '     %sUp/Down move, Space or number toggles, Enter installs%s\n' "$GREY" "$RESET" >&3
	while :; do
		# Redraw the list in place after the first pass.
		[[ -z $drawn ]] || printf '\033[%dA' "$count" >&3
		drawn=1
		for i in "${!keys[@]}"; do
			printf '\r\033[K   %s %s %d) %-47s %s%s%s\n' \
				"$( ((i == cursor)) && printf '%s>%s' "$GREEN" "$RESET" || echo ' ')" \
				"$( ((picked[i])) && printf '%s[x]%s' "$GREEN" "$RESET" || echo '[ ]')" \
				$((i + 1)) "${labels[i]}" "$GREY" "${states[i]}" "$RESET" >&3
		done
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
			case $rest in
			'[A') cursor=$(((cursor + count - 1) % count)) ;;
			'[B') cursor=$(((cursor + 1) % count)) ;;
			esac
			;;
		esac
	done
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
	fetch=(curl -fsSL)
elif command -v wget >/dev/null; then
	fetch=(wget -qO-)
else
	fail "curl or wget is required."
fi
sudo -v || fail "Unable to authenticate with sudo."
ok "Linux $(uname -m) is supported"

# Detect tools from earlier runs that are not on the default PATH yet.
export PATH="$HOME/.nvm/versions/node/current/bin:$HOME/.local/bin:$PATH"
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
# sudo resets the environment, so pass the prompt mode on explicitly.
as_root=(sudo env "LINUX_TOOLBOX_NONINTERACTIVE=${LINUX_TOOLBOX_NONINTERACTIVE:-0}" bash)
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
	ok "Go step complete"
	commands+=(go)
fi

if selected node; then
	run_step "Node.js"
	load_script install-node.sh | bash
	ok "Node.js step complete"
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
	if ! ai_tools_script=$(load_script install-ai-tools.sh); then
		fail "Unable to download the AI tools installer."
	fi
	if ! bash -c "$ai_tools_script" -- "${agents[@]}" </dev/null; then
		fail "Unable to install AI tools and skills."
	fi
	ok "AI tools and skills installed"
	commands+=("${agents[@]}" bwrap)
fi

step "Verifying installation"
for command in "${commands[@]}"; do
	command -v "$command" >/dev/null || fail "$command was not found after installation."
done
if selected release; then
	gh release-flow --help >/dev/null || fail "gh-release-flow was not found after installation."
fi
ok "All installed commands are available"

git_setup=
identity_prompt="Set up your Git identity now?"
if command -v git >/dev/null; then
	name=$(git config --global --get user.name || true)
	email=$(git config --global --get user.email || true)
	if [[ -n $name$email ]]; then
		identity_prompt="Git identity is already set to ${name:-no name}${email:+ <$email>}. Change it?"
	fi
fi
if confirm "$identity_prompt"; then
	step "Git identity"
	git_setup=${git_setup:-$(load_script setup-git.sh)}
	bash -c "$git_setup" -- identity </dev/tty
	ok "Git identity configured"
else
	notice "Git identity setup skipped"
fi

github_prompt="Set up GitHub authentication now?"
if command -v gh >/dev/null && auth_status=$(gh auth status --hostname github.com 2>&1); then
	account=$(sed -n 's/.*account \([^ ]*\).*/\1/p' <<<"$auth_status" | head -n 1)
	github_prompt="GitHub CLI is already authenticated${account:+ as $account}. Re-run setup? This reconfigures Git's credential helper for github.com."
fi
if confirm "$github_prompt"; then
	step "GitHub authentication"
	git_setup=${git_setup:-$(load_script setup-git.sh)}
	bash -c "$git_setup" -- github </dev/tty
	ok "GitHub authentication configured"
else
	notice "GitHub authentication setup skipped"
fi

if selected cleanup; then
	step "Ubuntu cleanup"
	load_script ubuntu-cleanup.sh | sudo bash
	ok "Ubuntu cleanup complete"
fi

banner "Setup complete"
