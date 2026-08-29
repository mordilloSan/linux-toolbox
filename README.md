# LinuxIO tools

Small, standalone Linux host utilities.

## Ubuntu cleanup

Removes Ubuntu MOTD noise and Snap, then prevents `snapd` from being installed
again. It is destructive and intended for Ubuntu hosts only.

Review and run it directly:

```bash
curl -fsSL https://raw.githubusercontent.com/mordilloSan/linuxio-tools/main/ubuntu-cleanup.sh | sudo bash
```

To inspect it first:

```bash
curl -fLO https://raw.githubusercontent.com/mordilloSan/linuxio-tools/main/ubuntu-cleanup.sh
less ubuntu-cleanup.sh
sudo bash ubuntu-cleanup.sh
```

Validate the checked-out script with `make check`.
