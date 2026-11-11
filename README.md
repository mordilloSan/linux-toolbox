# Linux Toolbox

[![Check](https://github.com/mordilloSan/linux-toolbox/actions/workflows/check.yml/badge.svg)](https://github.com/mordilloSan/linux-toolbox/actions/workflows/check.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An opinionated installer for turning a fresh Linux environment into a ready-to-use development workstation.

## What it installs

| Area | Tools |
| --- | --- |
| System | Git, GitHub CLI, Make, archive utilities, and `awk` when missing |
| Runtimes | Latest Go with `gopls`, and latest Node.js LTS through NVM with `typescript-language-server` |
| Shell | ShellCheck, shfmt, jq, ripgrep, and actionlint |
| AI (optional) | Claude Code and/or Codex CLI, with Bubblewrap and socat for the agent sandbox (on Ubuntu 24.04 it also needs [an AppArmor profile](https://code.claude.com/docs/en/sandboxing#add-an-apparmor-profile-for-bubblewrap); the installer says so when it does), interface skills, `find-skills`, and selected Go skills for each selected agent. On apt and dnf systems Claude Code comes from Anthropic's signed package repository (the `latest` channel, or `stable` when `autoUpdatesChannel` is `stable` in `~/.claude/settings.json`), so system upgrades update it; a copy from the native installer is replaced. Other systems get the native installer. `context-handoff` is installed only with Codex. Claude Code also gets Anthropic's official `gopls-lsp` and `typescript-lsp` plugins (not pinned), which give it Go and TypeScript code intelligence, and the `superpowers`, `frontend-design` and `claude-code-setup` plugins from the same marketplace (not pinned either). The skills are pinned to reviewed commits. Claude Code also gets git guardrails (deny rules for the usual `git push`, `git tag` and `gh release create` commands, approval before `git commit` and `gh pr merge`, no Co-Authored-By trailers; other spellings such as `git -C dir push` are not matched) and a hook that lints shell scripts and workflows after each edit. |
| Releases | `gh-release-flow` and user-wide `make` targets |

The installer supports x86-64 and ARM64 on Ubuntu, Debian, Fedora, and RHEL 8 or newer (and compatible) distributions using `apt` or `dnf`.

## Install

Run the complete installer as your regular user:

```bash
curl -fsSL https://setup.engmariz.com | bash
```

With `wget`:

```bash
wget -qO- https://setup.engmariz.com | bash
```

The installer asks for `sudo` before making system changes. It starts with a menu that shows what is already installed:

```text
 [?] Components to install or update
     Up/Down move, Space or number toggles, Enter installs
   > [x] 1) System packages: git, gh, make, tar             installed
     [x] 2) Go                                              go1.27.2
     [x] 3) Node.js LTS through nvm                         v24.21.0
     [x] 4) Shell tools: jq, ShellCheck, rg, shfmt          installed
     [x] 5) GitHub release flow                             not installed
     [x] 6) Claude Code                                     2.1.296 (Claude Code)
     [x] 7) Codex CLI                                       not installed
     [ ] 8) Git identity and GitHub sign-in                 Jane Doe, GitHub janedoe
     [ ] 9) Ubuntu cleanup: remove Snaps and all Snap data  Snap present
```

Components 1 to 7 start checked. Move with the arrow keys and toggle with Space, or press an item's number to toggle it. Enter installs the checked items. Git setup starts checked only when the Git name or email is missing or the GitHub CLI is not signed in; when checked, it runs both parts of [Git and GitHub setup](#git-and-github-setup) after the installs. The cleanup appears only on Ubuntu and starts unchecked. Without a terminal, the installer prints the list and uses the default selection, with Git setup unchecked.

Installed components are updated in place. Before a step replaces something you may have set up yourself, it asks first, and the default answer keeps what you have:

| Step | It asks before |
| --- | --- |
| System packages | Replacing a GitHub CLI package source that has different content |
| Go | Replacing another Go installation or a different `/etc/profile.d/go.sh` |
| Node.js | Installing next to a Node.js that nvm does not manage (one without `npx`, or older than 22.20, is not kept), or changing a custom nvm default |
| Shell tools | Adding a copy in `~/.local/bin` when the tool already exists elsewhere (a Snap copy does not count) |
| Release flow | Replacing a `~/.config/make/release-flow.mk` that has different content |

To review the entrypoint first:

```bash
curl -fsSL https://setup.engmariz.com -o install.sh
less install.sh
bash install.sh
```

After installing Go, log out and back in, or run `. /etc/profile.d/go.sh`, so programs from `go install` (in `~/go/bin`) are on PATH.

## Options

Skip the linux-toolbox guidance block in `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`, and its permission rules and hooks in `~/.claude/settings.json`:

```bash
LINUX_TOOLBOX_SKIP_AGENT_GUIDANCE=1 bash install.sh
```

Without this option, each run adds back those git rules if you removed them.

Skip the menu and the installer's own questions (sudo may still ask for your password; with no terminal it needs passwordless or recently cached sudo). This installs or updates components 1 to 7, keeps anything you set up yourself, and skips Git setup and the Ubuntu cleanup:

```bash
LINUX_TOOLBOX_NONINTERACTIVE=1 bash install.sh
```

Install the AI tools for a single agent directly (Node.js and jq must already be installed, for example by components 3 and 4):

```bash
./install-ai-tools.sh claude
./install-ai-tools.sh codex
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

Choose option 8 in the installer menu to run the cleanup. It removes Snap applications together with every user's Snap app data, with no backup: on Ubuntu Desktop that includes the Firefox and Thunderbird profiles, so back them up first. It also blocks `snapd` from being reinstalled, disables Ubuntu MOTD news, and purges `apport` (crash reporter), `multipath-tools` (SAN-only, spams the journal), `kdump-tools` (reserves crashkernel RAM) and `landscape-common` (the login sysinfo block; kept on hosts managed by Landscape). Tools that exist only as Snaps, for example a Snap Go or Node.js, are removed too, so keep their menu items checked to get the installer's own copies. On bare-metal installs where cloud-init has no datasource it also disables cloud-init (`/etc/cloud/cloud-init.disabled`); cloud, Proxmox and WSL hosts are left alone. This is destructive and intended only for Ubuntu hosts.

To review and run it on its own:

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
make start-dev  # shows the latest tag and asks for the version; or pass VERSION=v1.7.0
# Commit your changes, then:
make open-pr
make merge-release

# Show or upgrade the installed gh-release-flow:
make rf-version
make rf-upgrade
```

`make help` ends with a line that lists these targets, after the project's own `help` output when the Makefile has a `help` target. Plain `make` in a folder without a Makefile prints only that line. Other `make` runs are unchanged.

The targets and this `make` behaviour belong to gh-release-flow: the installer runs `gh release-flow setup-make`, and `make rf-upgrade` updates the extension and then refreshes them.

Open a new terminal after first installing the targets, or when the installer or `make rf-upgrade` says so. Release branches use the `dev/v*` naming convention. If a project Makefile already defines `start-dev`, `open-pr` or `merge-release`, make warns "overriding recipe" on every run there; delete those targets from the project Makefile.

Run `make check` for syntax and style checks, and `make test` for the isolated installer behavior tests. Pull requests run both targets, and a release is published only when the PR's Check workflow passed. Merging a release PR then creates the tag, publishes all scripts as release assets, and pins the entrypoint to that release.

## Security and privacy

No credentials, API keys, access tokens, private keys, or personal configuration are intentionally stored in this repository. Tracked content consists only of public project files.

Authentication is handled interactively by the installed CLIs. Their credentials remain in the current user's local configuration and are not copied into this repository. Never commit `.env` files, tokens, generated credentials, or machine-specific configuration.

## License

Licensed under the [MIT License](LICENSE).
