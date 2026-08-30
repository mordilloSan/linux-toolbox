#!/usr/bin/env bash
set -euo pipefail

if ((EUID == 0)); then
    echo "Run this installer as your regular user, not with sudo." >&2
    exit 1
fi

readonly RESET=$'\033[0m'
readonly GREEN=$'\033[38;5;154m'
readonly GREY=$'\033[90m'
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

confirm() {
    local answer
    if ! { exec 3<>/dev/tty; } 2>/dev/null; then
        return 1
    fi
    printf '\n %s[?]%s %s [y/N] ' "$YELLOW" "$RESET" "$1" >&3
    IFS= read -r answer <&3 || { exec 3>&-; return 1; }
    exec 3>&-
    [[ $answer == [yY] ]]
}

banner "Linux Toolbox Installer"

# ponytail: main can move between downloads; use release URLs when atomic releases matter.
step "1/4 System dependencies"
curl -fsSL "$base_url/install-dependencies.sh" | sudo bash
ok "System dependencies installed"

step "2/4 Go"
curl -fsSL "$base_url/install-go.sh" | sudo bash
ok "Go installed"

step "3/4 Node.js"
curl -fsSL "$base_url/install-node.sh" | sudo bash
ok "Node.js installed"

step "4/4 AI tools and skills"
curl -fsSL "$base_url/install-ai-tools.sh" | bash
ok "AI tools and skills installed"

if confirm "Set up your Git identity and GitHub authentication now?"; then
    step "Git and GitHub setup"
    git_setup=$(curl -fsSL "$base_url/setup-git.sh")
    bash -c "$git_setup" </dev/tty
    ok "Git and GitHub configured"
else
    notice "Git and GitHub setup skipped"
fi

if grep -Eq '^ID="?ubuntu"?$' /etc/os-release 2>/dev/null; then
    if confirm "Remove all Snap apps, disable MOTD news, and block Snap from being reinstalled?"; then
        step "Ubuntu cleanup"
        curl -fsSL "$base_url/ubuntu-cleanup.sh" | sudo bash
        ok "Ubuntu cleanup complete"
    else
        notice "Ubuntu cleanup skipped"
    fi
fi

banner "Setup complete"
