# Thin-Client Installation

## Target scenario

This assistant is designed as a first implementation base for a Linux-backed thin client that boots into a dedicated Proxmox access mode.

Supported runtime choices:

- `SPICE`
- `NOVNC`
- `DCV`

The repository also ships a USB writer helper that prepares a removable drive with the thin-client installer payload and a local start menu.

## Current assumptions

- Debian or Ubuntu style package management
- a local graphical environment is already present
- installation is performed as `root`
- a local runtime user exists or will be created before rollout

## Installer flow

1. Run `thin-client-assistant/installer/install.sh`
2. Choose the target mode in the setup menu
3. Enter the relevant launch target values
4. Let the installer deploy config, runtime files, XDG autostart and systemd assets
5. Reboot or restart the graphical session

## Mode-specific notes

### SPICE

- requires `remote-viewer` from `virt-viewer`
- expects a SPICE URI or `.vv` URL in the config

### NOVNC

- requires Chromium or a compatible browser
- launches the configured URL in kiosk mode

### DCV

- requires the native `dcvviewer` client
- this repository wires the runtime integration but does not redistribute NICE binaries

## Example commands

Interactive install:

```bash
sudo ./thin-client-assistant/installer/install.sh
```

Install project assets on a Proxmox host for local operator distribution:

```bash
sudo ./scripts/install-proxmox-host.sh
```

Non-interactive install:

```bash
sudo ./thin-client-assistant/installer/install.sh \
  --mode DCV \
  --runtime-user thinclient \
  --dcv-url dcv://dcv-gateway.internal/session/example
```

Prepare a USB installer stick:

```bash
sudo ./thin-client-assistant/usb/pve-thin-client-usb-installer.sh --device /dev/sdX
```

## Post-install verification

- inspect `/etc/pve-thin-client/thinclient.conf`
- run `systemctl status pve-thin-client-prepare.service`
- verify `remote-viewer`, `chromium` or `dcvviewer` is available depending on the mode
- log into the thin-client desktop session and verify the intended client autostarts
