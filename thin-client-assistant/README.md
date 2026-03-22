# Thin-Client Assistant

This directory contains the deployment-oriented endpoint path for Beagle OS.
It turns a Linux device or installer image into a dedicated Moonlight thin client that is bound to a Proxmox-managed Sunshine VM.

## Structure

- `installer/` installation and setup menu scripts
- `runtime/` launch and preparation scripts
- `systemd/` system service units
- `templates/` runtime config and autostart templates
- `examples/` sample profile fragments
- `usb/` USB writer, live installer menu and local-disk installer
- `live-build/` bootable installer image definition

## Runtime model

The assistant is intentionally single-purpose:

- `Proxmox` supplies the VM binding and profile metadata
- `Sunshine` runs inside the streamed VM
- `Moonlight` runs on the endpoint

The runtime launcher validates that the selected mode is `MOONLIGHT` and then starts the configured Sunshine app.

## Install

```bash
sudo ./thin-client-assistant/installer/install.sh
```

## Bootable USB installer

The standalone writer script can be started as a normal user:

```bash
./thin-client-assistant/usb/pve-thin-client-usb-installer.sh
```

It escalates to `sudo` only for partitioning and writing the selected USB device.
For operator rollouts, prefer the host-provided per-VM installer from:

```text
https://<proxmox-host>:8443/beagle-downloads/pve-thin-client-usb-installer-vm-<vmid>.sh
```

That installer already knows the matching payload URL and embeds the VM-specific Beagle profile directly into the USB medium.
When a graphical desktop is available, the writer prefers a GUI selection flow, and the generated live media boots into a graphical installer dashboard instead of a plain text-only menu.

List candidate targets before writing:

```bash
./thin-client-assistant/usb/pve-thin-client-usb-installer.sh --list-devices
```

The generated USB and the local install target both use a BIOS+UEFI-compatible GPT layout with a dedicated `bios_grub` partition for GRUB.

## Config file

The installer writes:

`/etc/pve-thin-client/thinclient.conf`

A profile typically includes:

- Proxmox host, node and VMID
- Sunshine host and API URL
- Moonlight app, codec, decoder, bitrate and FPS
- Sunshine credentials or pairing PIN when unattended startup is desired

## Operational note

A Beagle endpoint is not meant to behave like a generic workstation.
It is expected to boot straight into the assigned Moonlight session and stay aligned with the Proxmox VM profile that generated it.
