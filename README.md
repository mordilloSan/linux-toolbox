# Linux Toolbox

[![Check](https://github.com/mordilloSan/linux-toolbox/actions/workflows/check.yml/badge.svg)](https://github.com/mordilloSan/linux-toolbox/actions/workflows/check.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An opinionated installer for turning a fresh Linux environment into a ready-to-use development workstation.

## What it installs

| Area | Tools |
| --- | --- |
| System | Git, GitHub CLI, Make, archive utilities, and `awk` when missing |
| Runtimes | Latest Go and latest Node.js LTS through NVM |
| Shell | ShellCheck, shfmt, jq, ripgrep, and actionlint |
| AI | Codex CLI, Claude Code, Bubblewrap, Ponytail, interface skills, `find-skills`, and selected Go skills |
| Releases | `gh-release-flow` and user-wide `make` targets |

The installer supports x86-64 and ARM64 on Ubuntu, Debian, Fedora, and RHEL-family distributions using `apt`, `dnf`, or `yum`.

## Install

Run the complete installer as your regular user:

```bash
curl -fsSL https://setup.engmariz.com | bash
```

With `wget`:

```bash
wget -qO- https://setup.engmariz.com | bash
```

The installer asks for `sudo` before making system changes. Interactive runs separately offer Git identity setup, GitHub authentication, and Ubuntu cleanup.

To review the entrypoint first:

```bash
curl -fsSL https://setup.engmariz.com -o install.sh
less install.sh
bash install.sh
```

## Options

Skip changes to global Codex and Claude instruction files:

```bash
LINUX_TOOLBOX_SKIP_AGENT_GUIDANCE=1 bash install.sh
```

Skip optional confirmation prompts:

```bash
LINUX_TOOLBOX_NONINTERACTIVE=1 bash install.sh
```

## Git and GitHub setup

Configure both Git identity and GitHub authentication:

```bash
./setup-git.sh
```

Configure them separately:

```bash
./setup-git.sh identity
./setup-git.sh github
```

Existing Git name and email values are kept when you press Enter. GitHub CLI authenticates over HTTPS and becomes Git's credential helper.

## Ubuntu cleanup

The optional cleanup removes Snap applications, blocks `snapd` from being reinstalled, and disables Ubuntu MOTD news. This is destructive and intended only for Ubuntu hosts.

Review and run it directly:

```bash
curl -fLO https://raw.githubusercontent.com/mordilloSan/linux-toolbox/main/ubuntu-cleanup.sh
less ubuntu-cleanup.sh
sudo bash ubuntu-cleanup.sh
```

## Local development

Run the local installer from the repository root:

```bash
./install.sh
```

Local runs use the sibling scripts in the checkout. Piped installs download child scripts from the entrypoint's configured remote source.

## Releases

The installer provides release targets without requiring a repository Makefile:

```bash
make start-dev VERSION=v1.7.0
# Commit your changes, then:
make open-pr
make merge-release
```

Run `source ~/.bashrc` or open a new terminal after first installing the targets. Release branches use the `dev/v*` naming convention.

Every pull request and push to `main` checks Bash syntax, ShellCheck, shfmt, and GitHub Actions workflows. Merging a release PR creates the tag, publishes all scripts as release assets, and pins the entrypoint to that release.

## Security and privacy

No credentials, API keys, access tokens, private keys, or personal configuration are intentionally stored in this repository. Tracked content consists only of public project files.

Authentication is handled interactively by the installed CLIs. Their credentials remain in the current user's local configuration and are not copied into this repository. Never commit `.env` files, tokens, generated credentials, or machine-specific configuration.

## License

Licensed under the [MIT License](LICENSE).
