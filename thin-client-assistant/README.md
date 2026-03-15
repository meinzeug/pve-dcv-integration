# Thin-Client Assistant

This directory contains the first deployment-oriented baseline for turning a Linux device into a dedicated Proxmox thin client.

## Structure

- `installer/` installation and setup menu scripts
- `runtime/` launch and preparation scripts
- `systemd/` system service unit
- `templates/` config and autostart templates
- `examples/` sample configuration files
- `usb/` USB writer, live installer menu and local-disk installer
- `live-build/` bootable installer image definition

## Supported modes

- `SPICE` via `remote-viewer`
- `NOVNC` via Chromium kiosk mode
- `DCV` via native `dcvviewer`

## Install

```bash
sudo ./thin-client-assistant/installer/install.sh
```

## Bootable USB installer

The standalone writer script can be started as a normal user:

```bash
./thin-client-assistant/usb/pve-thin-client-usb-installer.sh
```

It escalates to `sudo` only for partitioning and writing the selected USB device. If it is executed outside the repository, it should be the host-provided standalone script from `https://<proxmox-host>:8443/pve-dcv-downloads/`, which already knows the matching local payload URL.
It can also show candidate targets up front:

```bash
./thin-client-assistant/usb/pve-thin-client-usb-installer.sh --list-devices
```

The generated USB and the local install target both use a BIOS+UEFI-compatible GPT layout with a dedicated `bios_grub` partition for GRUB.

## Config file

The installer writes:

`/etc/pve-thin-client/thinclient.conf`

## Important note about DCV

The generic in-place installer still expects a working `dcvviewer` binary on the target system. The bootable live installer path now installs NICE DCV Viewer into the generated image automatically.

## Proxmox-backed SPICE mode

`SPICE` can now operate in two ways:

- direct URL / `.vv` target
- Proxmox API ticket mode with stored Proxmox host, node, VMID and credentials

The Proxmox ticket path generates a fresh `.vv` file on each launch and starts `remote-viewer` automatically.
