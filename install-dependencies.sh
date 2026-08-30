#!/usr/bin/env bash
# =============================================================================
# Common Linux Tools Installation
# 2026 Miguel Mariz (mordilloSan)
# =============================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
trap 'echo -e "\e[0m"; exit 1' INT

# ---------- Colors & Styling ----------
readonly COLOUR_RESET='\e[0m'
readonly GREEN='\e[38;5;154m'
readonly BOLD='\e[1m'
readonly GREY='\e[90m'
readonly RED='\e[91m'
readonly YELLOW='\e[33m'

readonly LINE=" ${GREEN}───────────────────────────────────────────────────────${COLOUR_RESET}"
Show() {
	local status="$1"
	shift
	case "$status" in
	0) echo -e " ${GREY}[${GREEN}  OK  ${GREY}]${COLOUR_RESET} $*" ;;
	1)
		echo -e " ${GREY}[${RED}FAILED${GREY}]${COLOUR_RESET} $*"
		exit 1
		;;
	2) echo -e " ${GREY}[${BOLD} INFO ${GREY}]${COLOUR_RESET} $*" ;;
	3) echo -e " ${GREY}[${YELLOW}NOTICE${GREY}]${COLOUR_RESET} $*" ;;
	esac
}

Header() {
	echo ""
	echo -e "${LINE}"
	echo -e " ${BOLD} $*${COLOUR_RESET}"
	echo -e "${LINE}"
	echo ""
}

# ---------- Distro Detection ----------
DISTRO=""
PKG_MGR=""
select_package_manager() {
	local family=" $1 ${2:-} "
	PKG_MGR=""

	if command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1 &&
		[[ "$family" == *" debian "* || "$family" == *" ubuntu "* ]]; then
		PKG_MGR=apt
	elif command -v dnf >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1 &&
		[[ "$family" == *" fedora "* || "$family" == *" rhel "* ]]; then
		PKG_MGR=dnf
	elif command -v yum >/dev/null 2>&1 && command -v rpm >/dev/null 2>&1 &&
		[[ "$family" == *" fedora "* || "$family" == *" rhel "* ]]; then
		PKG_MGR=yum
	fi
}

detect_distro() {
	local ID="" ID_LIKE=""
	if [[ -f /etc/os-release ]]; then
		# shellcheck disable=SC1091
		. /etc/os-release
	elif [[ -f /etc/debian_version ]]; then
		ID=debian
	elif [[ -f /etc/redhat-release ]]; then
		ID=rhel
	fi
	DISTRO="${ID:-unknown}"
	select_package_manager "$DISTRO" "$ID_LIKE"
}

# ---------- Package helpers ----------
# Check if a package is already installed
pkg_installed() {
	if [[ "$PKG_MGR" == apt ]]; then
		[[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null || true)" == "install ok installed" ]]
	elif [[ "$PKG_MGR" == dnf || "$PKG_MGR" == yum ]]; then
		rpm -q "$1" &>/dev/null
	else
		return 1
	fi
}

pkg_install() {
	if [[ "$PKG_MGR" == apt ]]; then
		apt-get install -y -qq "$@"
	else
		"$PKG_MGR" install -y -q "$@"
	fi
}

# ---------- Packages ----------
install_packages() {
	Header "Installing Packages"

	if [[ -z "$PKG_MGR" ]]; then
		Show 1 "Unsupported distribution: ${DISTRO}"
	fi

	local packages=(git gh make tar gzip)
	[[ "$PKG_MGR" == apt ]] && packages+=(xz-utils) || packages+=(xz)
	if ! command -v awk >/dev/null 2>&1; then
		[[ "$PKG_MGR" == apt ]] && packages+=(mawk) || packages+=(gawk)
	fi

	local bootstrap=()
	pkg_installed ca-certificates || bootstrap+=(ca-certificates)
	if ! command -v curl >/dev/null 2>&1; then
		bootstrap+=(curl)
	fi
	if ((${#bootstrap[@]})); then
		if [[ "$PKG_MGR" == apt ]]; then
			Show 2 "Updating package lists..."
			apt-get update -qq >/dev/null || Show 1 "Failed to update package lists"
		fi
		Show 2 "Installing HTTPS prerequisites..."
		pkg_install "${bootstrap[@]}"
	fi

	# GitHub's repository avoids obsolete distro builds and is signed by its keyring.
	Show 2 "Configuring the GitHub CLI repository..."
	if [[ "$PKG_MGR" == apt ]]; then
		install -d -m 755 /etc/apt/keyrings /etc/apt/sources.list.d
		curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
			-o /etc/apt/keyrings/githubcli-archive-keyring.gpg
		chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
		printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
			"$(dpkg --print-architecture)" >/etc/apt/sources.list.d/github-cli.list
		apt-get update -qq >/dev/null || Show 1 "Failed to update package lists"
	else
		install -d -m 755 /etc/yum.repos.d
		curl -fsSL https://cli.github.com/packages/rpm/gh-cli.repo -o /etc/yum.repos.d/gh-cli.repo
	fi
	Show 0 "GitHub CLI repository configured"

	Show 2 "Installing or updating ${#packages[@]} packages..."
	pkg_install "${packages[@]}"
	Show 0 "Packages installed"
}

# ---------- Main ----------
require_root() {
	if [[ $EUID -ne 0 ]]; then
		Show 1 "This script must be run as root"
	fi
}

main() {

	require_root

	Header "${GREY} Linux Tools Installer${COLOUR_RESET}"

	detect_distro
	Show 2 "Detected distribution: ${BOLD}${DISTRO}${COLOUR_RESET}"

	install_packages

	echo ""
	echo -e "${LINE}"
	echo -e " ${GREEN}${BOLD}Installation complete!${COLOUR_RESET}"
	echo -e "${LINE}"
	echo ""
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
	main "$@"
fi
