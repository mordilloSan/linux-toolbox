# Linux toolbox

Small, standalone Linux host utilities.

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

Validate the checked-out script with `make check`.

## Codex and Claude Code

Install both command-line tools and their shared interface and discovery skills:

```bash
./install-ai-tools.sh
```

Run the script as your regular user, not with `sudo`. It requires `curl` and
`npx`; run `sudo bash install-node.sh` first if Node.js is not installed.
