# Architecture

## Overview

The repository is split into two deployable product surfaces:

- `extension/` adds a DCV action to the Proxmox VE web UI
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

## Thin-client assistant architecture

The thin-client assistant is intentionally split into installer, runtime, system assets and templates.

- `installer/` writes configuration and deploys assets
- `runtime/` contains the actual launch and boot preparation logic
- `systemd/` contains the system service unit
- `templates/` contains default config, environment and XDG autostart assets
- `examples/` contains sample configuration profiles

### Runtime model

The current implementation baseline assumes:

- a Linux host with a graphical session
- a dedicated local user account for kiosk operation
- autologin or otherwise guaranteed local session startup

Boot flow:

1. `pve-thin-client-prepare.service` runs as root after networking is available.
2. `prepare-runtime.sh` validates the runtime configuration and writes a status file.
3. the desktop session reads the installed XDG autostart entry
4. `launch-session.sh` loads `/etc/pve-thin-client/thinclient.conf`
5. the chosen mode starts one of:
   - `remote-viewer`
   - `chromium --kiosk`
   - `dcvviewer`

## Configuration model

Primary config file:

- `/etc/pve-thin-client/thinclient.conf`

The config file defines:

- mode selection: `SPICE`, `NOVNC`, `DCV`
- target URLs
- kiosk browser path and flags
- local runtime user and autostart toggles

## Packaging model

The release script creates:

- a browser extension zip for manual browser installation
- a thin-client assistant tarball for host-side deployment
- sha256 checksums for release verification
