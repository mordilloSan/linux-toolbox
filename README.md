# Linux toolbox

[![Check](https://github.com/mordilloSan/linux-toolbox/actions/workflows/check.yml/badge.svg)](https://github.com/mordilloSan/linux-toolbox/actions/workflows/check.yml)

Small, standalone Linux host utilities.

## Install

On a fresh system, run the complete installer as your regular user:

```bash
curl -fsSL https://setup.engmariz.com | bash
```

If `curl` is unavailable but `wget` is installed:

```bash
wget -qO- https://setup.engmariz.com | bash
```

From an existing checkout, run:

```bash
./install.sh
```

The installer prompts for `sudo` and installs system packages, Go, Node.js,
Codex, Claude Code, and their shared skills. When run interactively, it also
offers Git and GitHub setup and optional Ubuntu cleanup.

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

This configures the current computer only. Repository checks and releases are
handled by GitHub Actions.

## Releases

Every push and pull request to `main` checks the shell scripts with Bash and
ShellCheck. To publish pinned installer files, push a semantic version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The release workflow publishes all scripts as GitHub release assets and makes
that release's `install.sh` download the matching versions of its child scripts.
