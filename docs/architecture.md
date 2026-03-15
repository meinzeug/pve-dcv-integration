# Architecture

## Overview

The repository is split into two deployable product surfaces:

- `extension/` adds a DCV action to the Proxmox VE web UI
- `proxmox-ui/` and `scripts/` install the same UI behavior plus optional host-side DCV TLS proxying directly on a Proxmox host
- `thin-client-assistant/` prepares a Linux endpoint for SPICE, noVNC or DCV access

These components are intentionally decoupled. The browser extension enhances the Proxmox operator workflow, while the thin-client assistant standardizes endpoint behavior on dedicated client devices.

## Extension architecture

The browser extension is implemented as a Manifest V3 content-script extension.

Core behavior:

1. Detect Proxmox VM context from the URL hash.
2. Resolve `node` and `vmid` from route state or cluster resource data.
3. Query the Proxmox API on the same origin.
4. Attempt guest-agent IP lookup through `network-get-interfaces`.
5. Fall back to VM config metadata from the VM description.
6. Hook the console dropdown at render time and append a `DCV` action beside `noVNC` and `SPICE`.
7. Render a neighboring `USB Installer` toolbar button for downloading the USB writer script.
8. Build a launch URL and open the target in a new tab.

Important design constraints:

- No Proxmox package patching
- No embedded credentials
- Same-origin API usage only
- Configurable launch template and fallback metadata keys

## Proxmox host integration architecture

The host-side installation path adds two operational pieces:

1. a JavaScript asset loaded by the Proxmox web UI
2. an optional `nginx` reverse proxy on `8443` that reuses `/etc/pve/local/pveproxy-ssl.pem`

The DCV proxy is designed for environments where the backend VM exposes a self-signed DCV web certificate.
The installer can either:

- auto-detect a single matching backend from VM metadata such as `dcv-url` and `dcv-ip`
- use an explicit `PVE_DCV_PROXY_VMID`
- use an explicit `PVE_DCV_PROXY_BACKEND_HOST` and `PVE_DCV_PROXY_BACKEND_PORT`

When enabled, the host installer also removes old `iptables` DNAT rules on the same DCV port so that local TLS termination can bind cleanly.

## Thin-client assistant architecture

The thin-client assistant is intentionally split into installer, runtime, system assets and templates.

- `installer/` writes configuration and deploys assets
- `runtime/` contains the actual launch and boot preparation logic
- `systemd/` contains the system service unit
- `templates/` contains default config, environment and XDG autostart assets
- `examples/` contains sample configuration profiles
- `usb/` contains the USB writer, live menu and local disk installer
- `live-build/` contains the bootable live installer definition

### Runtime model

The current implementation baseline assumes:

- either an existing Linux system converted in place
- or a bootable live installer / local-disk runtime created from the repository
- a dedicated local user account for kiosk operation
- tty1 autologin and `startx` based session startup in the live/local-disk image

Boot flow:

1. the live or local-disk boot medium exposes `vmlinuz`, `initrd.img` and `filesystem.squashfs`
2. tty1 autologin enters the `thinclient` shell wrapper
3. installer boots dispatch into the USB/live menu
4. runtime boots dispatch into `startx`
5. `prepare-runtime.sh` validates the selected runtime configuration, applies hostname/network state and writes a status file
6. `launch-session.sh` loads config from `/etc/pve-thin-client` or from the live medium state directory
7. the chosen mode starts one of:
   - `remote-viewer`
   - `chromium --kiosk`
   - `dcvviewer`

Storage / boot layout:

- installer USB media uses GPT with a dedicated `bios_grub` partition plus a FAT32 EFI/data partition
- local installs use GPT with `bios_grub`, EFI system partition and ext4 runtime partition
- local GRUB entries pin `live-media=UUID=...` so the disk runtime does not accidentally boot from a still-inserted USB stick

## Configuration model

Primary config file:

- `/etc/pve-thin-client/thinclient.conf`
- `/run/live/medium/pve-thin-client/state/thinclient.conf`

The config file defines:

- mode selection: `SPICE`, `NOVNC`, `DCV`
- target URLs
- connection method such as direct URLs or Proxmox-backed SPICE tickets
- Proxmox host/node/vmid settings
- stored username/password/token fields
- kiosk browser path and flags
- local runtime user and autostart toggles

## Packaging model

The release script creates:

- a browser extension zip for manual browser installation
- a thin-client assistant tarball for host-side deployment
- the host deployment scripts that can install UI integration and DCV TLS proxying from a release tarball
- sha256 checksums for release verification
