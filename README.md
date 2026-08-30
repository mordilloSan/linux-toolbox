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
Codex, Claude Code, shared skills, and AI-friendly shell tools: ShellCheck,
`shfmt`, `jq`, ripgrep, actionlint, and the `gh-release-flow` extension. When run
interactively, it also offers Git and GitHub setup and optional Ubuntu cleanup.

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

Every pull request and push to `main` checks the shell scripts. Releases use
`dev/v*` branches and the installed GitHub CLI extension:

```bash
gh release-flow start-dev v1.2.0
# Commit your changes, then:
gh release-flow open-pr
gh release-flow merge
```

The merge command waits for checks, merges the PR, monitors the release, and
cleans up the release branch. The workflow tags the merge commit, publishes all
scripts as release assets, and pins that release's child-script downloads.
