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

confirm() {
	local answer
	[[ ${LINUX_TOOLBOX_NONINTERACTIVE:-0} != 1 ]] || return 1
	if ! { exec 3<>/dev/tty; } 2>/dev/null; then
		return 1
	fi
	printf '\n %s[?]%s %s [y/N] ' "$YELLOW" "$RESET" "$1" >&3
	IFS= read -r answer <&3 || {
		exec 3>&-
		return 1
	}
	exec 3>&-
	[[ $answer == [yY] ]]
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

step "1/6 System dependencies"
"${fetch[@]}" "$base_url/install-dependencies.sh" | sudo bash
ok "System dependencies installed"

step "2/6 Go"
"${fetch[@]}" "$base_url/install-go.sh" | sudo bash
ok "Go installed"

step "3/6 Node.js"
"${fetch[@]}" "$base_url/install-node.sh" | sudo bash
ok "Node.js installed"

step "4/6 Shell tools"
"${fetch[@]}" "$base_url/install-shell-tools.sh" | bash
ok "Shell tools installed"

step "5/6 GitHub release flow"
"${fetch[@]}" "$base_url/install-release-flow.sh" | bash
ok "GitHub release flow installed"

step "6/6 AI tools and skills"
"${fetch[@]}" "$base_url/install-ai-tools.sh" | bash
ok "AI tools and skills installed"

step "Verifying installation"
export PATH="$HOME/.local/bin:$PATH"
for command in git gh jq make go node npm npx codex claude shellcheck shfmt rg actionlint; do
	command -v "$command" >/dev/null || fail "$command was not found after installation."
done
gh release-flow --help >/dev/null || fail "gh-release-flow was not found after installation."
ok "All installed commands are available"

if confirm "Set up your Git identity and GitHub authentication now?"; then
	step "Git and GitHub setup"
	git_setup=$("${fetch[@]}" "$base_url/setup-git.sh")
	bash -c "$git_setup" </dev/tty
	ok "Git and GitHub configured"
else
	notice "Git and GitHub setup skipped"
fi

if grep -Eq '^ID="?ubuntu"?$' /etc/os-release 2>/dev/null; then
	if confirm "Remove all Snap apps, disable MOTD news, and block Snap from being reinstalled?"; then
		step "Ubuntu cleanup"
		"${fetch[@]}" "$base_url/ubuntu-cleanup.sh" | sudo bash
		ok "Ubuntu cleanup complete"
	else
		notice "Ubuntu cleanup skipped"
	fi
fi

banner "Setup complete"
