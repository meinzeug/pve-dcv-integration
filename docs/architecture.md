# Architecture

## Overview

The repository is split into two deployable product surfaces:

- `extension/` adds Beagle operator actions to Proxmox VE VM pages
- `proxmox-ui/`, `proxmox-host/` and `scripts/` install the same Beagle workflow directly on a Proxmox host
- `thin-client-assistant/` prepares a Moonlight-based endpoint that boots into a dedicated streaming session
- `beagle-os/` builds the dedicated endpoint operating system and kernel profile

These parts are intentionally aligned around one runtime path:

- `Proxmox` is the management system
- `Sunshine` runs inside the streamed VM
- `Moonlight` runs on the Beagle endpoint

## Proxmox operator surface

The browser extension and the host-installed UI integration both expose the same operator model on VM pages:

1. Detect the current Proxmox VM context (`node`, `vmid`)
2. Read the VM config and cluster resource state through the Proxmox API
3. Parse Beagle metadata from the VM description
4. Resolve the Sunshine target, Moonlight defaults and Beagle installer URL
5. Show a Beagle profile dialog with export and download actions

The Beagle profile view is now a first-class management primitive.
It gives the operator a resolved endpoint profile for the selected VM instead of only a raw download link.

The profile dialog exposes:

- VM identity and live status
- guest-agent IP discovery where available
- Sunshine host and API URL
- Moonlight app, codec, decoder, bitrate and FPS defaults
- exported endpoint environment data for reproducible rollouts
- direct jump points to the hosted installer and control-plane health

## Proxmox host integration

The host-side installation path adds four operational pieces:

1. a JavaScript asset loaded by the Proxmox web UI
2. a runtime config asset that publishes hosted Beagle URLs into the UI
3. an `nginx` endpoint on `8443` that serves hosted downloads and the Beagle API proxy
4. a local Beagle control-plane service that publishes health and VM inventory data

The Beagle host path is intentionally simple:

- the Proxmox host generates per-VM installer artifacts
- the host publishes them under `/beagle-downloads/`
- the host also runs a small control plane for health and inventory data
- refresh services keep those artifacts current after host-side changes

This turns a Proxmox host into a Beagle management node instead of just a VM hypervisor.

## Thin-client assistant architecture

The thin-client assistant is split into installer, runtime, system assets and templates.

- `installer/` writes configuration and deploys assets
- `runtime/` contains the actual launch and boot preparation logic
- `systemd/` contains the system service units
- `templates/` contains default config and autostart assets
- `usb/` contains the USB writer, installer UI and local disk installer
- `live-build/` contains the bootable installer definition

### Runtime model

The current Beagle endpoint baseline assumes:

- a dedicated local user account for kiosk operation
- tty/X11 based autologin into a controlled session
- a preseeded Moonlight profile bound to one Proxmox VM
- Sunshine trust and API settings coming from the Beagle profile

Boot flow:

1. the live or local-disk boot medium exposes `vmlinuz`, `initrd.img` and `filesystem.squashfs`
2. the endpoint prepares hostname and networking from the stored profile
3. the runtime loads its Beagle configuration from disk or live media state
4. the session launcher validates that the selected mode is `MOONLIGHT`
5. `launch-moonlight.sh` pairs or reuses trust and starts the configured Sunshine app

## Configuration model

Primary runtime config files:

- `/etc/pve-thin-client/thinclient.conf`
- `/run/live/medium/pve-thin-client/state/thinclient.conf`
- `/etc/beagle-os/endpoint.env` inside the Beagle OS image path

The effective profile contains:

- Proxmox host, node and VMID binding
- Moonlight host and target app
- Moonlight codec, decoder, bitrate, FPS and audio defaults
- Sunshine API URL, username, password and pairing PIN
- local runtime user and autostart toggles

## Packaging model

The release scripts create:

- a browser extension zip for manual installation
- a Beagle host tarball for Proxmox deployment
- hosted USB payload and installer artifacts
- optional Beagle OS image artifacts produced by `build-beagle-os.sh`
- sha256 checksums for release verification

Operationally, GitHub only needs to carry the deployable artifacts.
After installation on a Proxmox host, the host rebuilds and republishes its own local `/beagle-downloads/` tree for operators and endpoints.
