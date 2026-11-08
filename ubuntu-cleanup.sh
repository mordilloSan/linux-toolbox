#!/bin/bash
# =============================================================================
# Ubuntu cleanup - remove MOTD noise, motd-news, snap, apport, multipath-tools, kdump-tools
# Idempotent: safe to re-run.
# Usage: sudo bash ubuntu-cleanup.sh
# =============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root (sudo bash $0)" >&2
	exit 1
fi

if [[ ! -r /etc/os-release ]]; then
	echo "Cannot determine the operating system (/etc/os-release is unreadable)" >&2
	exit 1
fi
os_id=$(sed -n 's/^ID=//p' /etc/os-release | head -n1 | tr -d '"')
if [[ $os_id != ubuntu ]]; then
	echo "This script supports Ubuntu only (detected: ${os_id:-unknown})" >&2
	exit 1
fi

say() { echo -e "\e[1;32m==>\e[0m $*"; }

# ========== 1. MOTD cleanup ==========
say "Removing Ubuntu MOTD noise scripts..."
rm -f /etc/update-motd.d/10-help-text \
	/etc/update-motd.d/50-motd-news 2>/dev/null || true
# dpkg does not restore deleted conffiles on upgrade, so removal is permanent.

say "Disabling and masking motd-news..."
if [[ -f /etc/default/motd-news ]]; then
	sed -i 's/^ENABLED=1/ENABLED=0/' /etc/default/motd-news
fi
systemctl disable --now motd-news.timer 2>/dev/null || true
# Mask so a future base-files upgrade cannot re-enable it.
systemctl mask motd-news.timer motd-news.service 2>/dev/null || true

# ========== 2. Snap removal ==========
if command -v snap >/dev/null 2>&1; then
	say "Removing installed snaps..."
	# Remove leaf snaps first; bases/snapd refuse removal while dependents
	# exist, so loop until nothing is removable, then take snapd itself.
	for _ in 1 2 3 4 5; do
		mapfile -t snaps < <(snap list 2>/dev/null | awk 'NR>1 {print $1}' | grep -vx snapd || true)
		[[ ${#snaps[@]} -eq 0 ]] && break
		for s in "${snaps[@]}"; do
			snap remove --purge "$s" 2>/dev/null || true
		done
	done
	snap remove --purge snapd 2>/dev/null || true
else
	say "snap command not present, skipping snap removal step"
fi

say "Stopping snapd services..."
systemctl disable --now snapd.socket snapd.service snapd.seeded.service 2>/dev/null || true

say "Purging snapd, apport, multipath-tools, kdump-tools and landscape-common..."
export DEBIAN_FRONTEND=noninteractive
# apport: crash reporter that phones home to Canonical.
# multipath-tools: SAN-only; elsewhere multipathd just spams the journal.
# kdump-tools: reserves crashkernel RAM for dumps nobody reads.
# landscape-common: the login sysinfo block; its upgrades bring the MOTD link back.
candidates=(snapd apport multipath-tools kdump-tools gnome-software-plugin-snap)
# landscape-client (a Landscape-managed host) depends on landscape-common, so keep both there.
[[ $(dpkg-query -W -f='${db:Status-Status}' landscape-client 2>/dev/null) == installed ]] ||
	candidates+=(landscape-common)
# Purge only names dpkg knows: apt refuses the whole command over one unknown name.
purge_packages=()
for package in "${candidates[@]}"; do
	case $(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null) in
	not-installed | '') ;;
	*) purge_packages+=("$package") ;;
	esac
done
# snapd, apport and multipath-tools are hard Depends of these metapackages,
# so purging them drops the metapackage. Keep its other dependencies
# out of reach of a later `apt autoremove`.
for meta in ubuntu-server ubuntu-server-minimal ubuntu-wsl; do
	if dpkg-query -W -f='${Status}' "$meta" 2>/dev/null | grep -q 'ok installed'; then
		apt-cache depends --no-recommends --no-suggests "$meta" |
			awk '/^ *[|]?Depends:/ && $2 !~ /^</ {print $2}' |
			xargs -r apt-mark manual >/dev/null
	fi
done
((${#purge_packages[@]} == 0)) || apt-get -o DPkg::Lock::Timeout=300 purge -y "${purge_packages[@]}"

say "Removing leftover snap directories..."
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd
for home in /home/* /root; do
	rm -rf "$home/snap" 2>/dev/null || true
done

say "Blocking snapd from ever being reinstalled as a dependency..."
cat >/etc/apt/preferences.d/nosnap.pref <<'EOF'
# Prevent snapd from being installed (removed by ubuntu-cleanup.sh).
# Delete this file to allow snapd again.
Package: snapd
Pin: release *
Pin-Priority: -10
EOF

# ========== 3. cloud-init ==========
# Only when cloud-init found no datasource (bare-metal installs): on cloud,
# Proxmox and WSL hosts it provisions users, keys and network, so leave it.
# Disable rather than purge so re-templating can turn it back on.
if command -v cloud-id >/dev/null 2>&1 && [[ $(cloud-id 2>/dev/null) == none ]]; then
	say "Disabling cloud-init (no datasource)..."
	touch /etc/cloud/cloud-init.disabled
else
	say "cloud-init is in use, already disabled or not installed; leaving it alone"
fi

say "Done. MOTD noise removed, motd-news masked, snap, apport, multipath-tools, kdump-tools and landscape-common purged."
echo "    (To ever restore snap: rm /etc/apt/preferences.d/nosnap.pref && apt install snapd)"
echo "    (To re-enable cloud-init: rm -f /etc/cloud/cloud-init.disabled)"
