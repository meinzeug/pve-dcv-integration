# Thin-Client Assistant

This directory contains the first deployment-oriented baseline for turning a Linux device into a dedicated Proxmox thin client.

## Structure

- `installer/` installation and setup menu scripts
- `runtime/` launch and preparation scripts
- `systemd/` system service unit
- `templates/` config and autostart templates
- `examples/` sample configuration files

## Supported modes

- `SPICE` via `remote-viewer`
- `NOVNC` via Chromium kiosk mode
- `DCV` via native `dcvviewer`

## Install

```bash
sudo ./thin-client-assistant/installer/install.sh
```

## Config file

The installer writes:

`/etc/pve-thin-client/thinclient.conf`

## Important note about DCV

The DCV client is not bundled here. Install the NICE DCV Viewer package on the target system and point the config to a valid `dcv://` or supported connection URL.
