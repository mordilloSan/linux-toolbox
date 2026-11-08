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

# Ask on the terminal. No terminal or LINUX_TOOLBOX_NONINTERACTIVE=1 answers No.
confirm() {
	local answer
	[[ ${LINUX_TOOLBOX_NONINTERACTIVE:-0} != 1 ]] || return 1
	{ exec 3<>/dev/tty; } 2>/dev/null || return 1
	printf '\n \033[33m[?]\033[0m %s [y/N] ' "$1" >&3
	IFS= read -r answer <&3 || answer=
	exec 3>&-
	[[ $answer == [yY] ]]
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
	local package output
	local -a installer
	for package; do
		Show 2 "Installing or updating ${package}..."
		if [[ "$PKG_MGR" == apt ]]; then
			installer=(apt-get -o DPkg::Lock::Timeout=300 install -y -qq "$package")
		else
			installer=("$PKG_MGR" install -y -q "$package")
		fi
		if ! output=$("${installer[@]}" 2>&1); then
			printf '%s\n' "$output" >&2
			Show 1 "Failed to install ${package}"
		fi
		Show 0 "${package} installed"
	done
}

# apt-get update ignores DPkg::Lock::Timeout, so wait while another apt refreshes the lists.
apt_update() {
	local output tries=0
	# LC_ALL=C: sudo keeps the user's language, and the lock check below matches apt's English text.
	until output=$(LC_ALL=C apt-get update -qq 2>&1 >/dev/null); do
		if [[ $output != *'Could not get lock'* ]] || ((++tries >= 30)); then
			printf '%s\n' "$output" >&2
			Show 1 "Failed to update package lists"
		fi
		sleep 10
	done
	[[ -z $output ]] || printf '%s\n' "$output" >&2
}

# ---------- Packages ----------
install_packages() {
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
	# A Snap curl cannot write outside the home folder, so install the distro curl.
	case $(command -v curl || true) in "" | /snap/*) bootstrap+=(curl) ;; esac
	if ((${#bootstrap[@]})); then
		if [[ "$PKG_MGR" == apt ]]; then
			Show 2 "Updating package lists..."
			apt_update
		fi
		pkg_install "${bootstrap[@]}"
	fi

	# GitHub's repository avoids obsolete distro builds and is signed by its keyring.
	Show 2 "Configuring the GitHub CLI repository..."
	if [[ "$PKG_MGR" == apt ]]; then
		local source_file=/etc/apt/sources.list.d/github-cli.list source_line
		source_line="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main"
		# Another file may already hold this source, e.g. github-cli.sources written by apt modernize-sources.
		if grep -qsE --exclude=github-cli.list '^[^#]*cli\.github\.com/packages' \
			/etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; then
			Show 3 "Kept the GitHub CLI repository that is already configured"
		elif [[ -e $source_file && $(<"$source_file") != "$source_line" ]] &&
			! confirm "$source_file has different content. Replace it with the official GitHub CLI source?"; then
			Show 3 "Kept the existing GitHub CLI repository"
		else
			install -d -m 755 /etc/apt/keyrings /etc/apt/sources.list.d
			curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
				-o /etc/apt/keyrings/githubcli-archive-keyring.gpg
			chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
			printf '%s\n' "$source_line" >"$source_file"
		fi
		apt_update
	else
		local repo_file=/etc/yum.repos.d/gh-cli.repo repo
		repo=$(curl -fsSL https://cli.github.com/packages/rpm/gh-cli.repo)
		if [[ -e $repo_file && $(<"$repo_file") != "$repo" ]] &&
			! confirm "$repo_file has different content. Replace it with the official GitHub CLI repository?"; then
			Show 3 "Kept the existing GitHub CLI repository"
		else
			install -d -m 755 /etc/yum.repos.d
			printf '%s\n' "$repo" >"$repo_file"
		fi
	fi
	Show 0 "GitHub CLI repository configured"

	pkg_install "${packages[@]}"
}

# ---------- Main ----------
require_root() {
	if [[ $EUID -ne 0 ]]; then
		Show 1 "This script must be run as root"
	fi
}

main() {

	require_root

	detect_distro
	Show 2 "Detected distribution: ${BOLD}${DISTRO}${COLOUR_RESET}"

	install_packages
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
	main "$@"
fi
