# Linux toolbox

Small, standalone Linux host utilities.

## Install

Run the complete installer as your regular user; it prompts for `sudo` when
installing system packages, Go, and Node.js:

```bash
./install.sh
```

This also installs Codex, Claude Code, and their shared skills.

## Ubuntu cleanup

Removes Ubuntu MOTD noise and Snap, then prevents `snapd` from being installed
again. It is destructive and intended for Ubuntu hosts only.

Review and run it directly:

```bash
curl -fsSL https://raw.githubusercontent.com/mordilloSan/linux-toolbox/main/ubuntu-cleanup.sh | sudo bash
```

To inspect it first:

```bash
curl -fLO https://raw.githubusercontent.com/mordilloSan/linux-toolbox/main/ubuntu-cleanup.sh
less ubuntu-cleanup.sh
sudo bash ubuntu-cleanup.sh
```

## Git and GitHub authentication

Configure your global Git identity, authenticate GitHub CLI over HTTPS, and
use GitHub CLI as Git's credential helper:

```bash
./setup-git.sh
```

Run it as your regular user. Existing name and email values are kept when you
press Enter.
