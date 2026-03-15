# pve-dcv-integration

`pve-dcv-integration` is an external, open-source enhancement layer for Proxmox VE. It adds a visible DCV action to VM views in the Proxmox web UI and ships a Linux thin-client assistant that can turn a local device into a dedicated SPICE, noVNC or NICE DCV endpoint.

The project is intentionally independent from Proxmox core. It does not patch Proxmox packages and can be versioned, deployed and packaged on its own.

## Product scope

### 1. Proxmox browser extension

- Adds a visible `DCV` action on QEMU VM pages.
- Detects `node` and `vmid` from the current Proxmox route.
- Resolves guest IPs through the Proxmox API and QEMU guest agent where available.
- Supports metadata fallbacks from the VM description if no guest IP is available.
- Opens either a generated NICE DCV URL or a metadata-provided direct URL.
- Hooks the existing Proxmox `Konsole` dropdown and appends a `DCV` menu item next to `noVNC` and `SPICE`.
- Adds a `USB Installer` toolbar button beside the console menu for downloading the thin-client USB writer script.

### 1b. Proxmox host UI integration

- Can deploy the same UI behavior directly on a Proxmox host without requiring a browser extension.
- Installs a server-side JavaScript asset into `/usr/share/pve-manager/js/`.
- Patches `index.html.tpl` with a backup and restarts `pveproxy`.
- Can terminate DCV TLS on the Proxmox host with the existing Proxmox certificate and proxy traffic to a backend DCV VM.

### 2. Linux thin-client assistant

- Provides an installer-oriented base for local deployment onto a Linux-backed thin client.
- Includes an interactive setup menu with three target modes: `SPICE`, `noVNC`, `DCV`.
- Stores the target runtime configuration in a dedicated config file.
- Installs runtime launchers, XDG autostart integration and systemd preparation logic.
- Separates installer logic, runtime logic, templates and system assets.
- Adds a bootable USB/live installer path inspired by the existing ThinOverNet provisioning flow.

## Repository layout

- `extension/` Chromium extension for the Proxmox DCV action
- `thin-client-assistant/` installer, runtime, templates, systemd unit and sample configs
- `docs/` architecture, security and installation documentation
- `scripts/` release packaging helpers
- `proxmox-ui/` server-side Proxmox UI integration asset

## Browser extension behavior

The extension supports these placeholders in the configurable DCV URL template:

- `{ip}` guest IPv4 resolved through guest agent or metadata
- `{node}` current Proxmox node
- `{vmid}` current VM ID
- `{host}` browser host of the current Proxmox session

Default template:

`https://{ip}:8443/`

If guest-agent IP lookup fails, the extension parses VM description metadata such as:

- `dcv-url: https://dcv.example.local:8443/`
- `dcv-host: dcv.example.local`
- `dcv-ip: 10.20.30.40`

## Thin-client assistant behavior

The thin-client assistant installs a first real implementation baseline:

- `installer/install.sh` performs installation and asset deployment
- `installer/setup-menu.sh` collects mode, connection, network and credential values
- `installer/write-config.sh` writes runtime, network and credential state
- `runtime/launch-session.sh` starts the chosen client mode
- `runtime/prepare-runtime.sh` validates runtime prerequisites on boot
- `runtime/apply-network-config.sh` applies persisted hostname and systemd-networkd settings during runtime boot
- `systemd/pve-thin-client-prepare.service` prepares the environment before graphical login
- `templates/` provides config, autostart and environment file templates
- `usb/pve-thin-client-usb-installer.sh` writes a bootable BIOS+UEFI installer USB, can list/select target devices interactively and self-escalates to `sudo`
- `usb/pve-thin-client-live-menu.sh` provides the USB-side setup menu
- `usb/pve-thin-client-local-installer.sh` installs a local bootable thin-client disk from the live environment
- `live-build/` defines the live installer image that is written to USB

Runtime modes:

- `SPICE` launches `remote-viewer`, optionally with fresh Proxmox API tickets
- `noVNC` launches Chromium in kiosk mode against a configured URL
- `DCV` launches the native `dcvviewer` client with generated connection files when credentials are provided

USB/live installer highlights:

- rootless launcher path with `sudo` escalation only for disk writes
- interactive disk discovery with `--list-devices`
- bootable GPT layout with both BIOS GRUB and EFI support
- live installer menu that collects connection mode, network and credentials before local-disk installation
- local-disk runtime that boots the live image from disk and re-applies the saved network profile on startup

## Installation and packaging

Developer-loading the extension:

1. Open `chrome://extensions` or `edge://extensions`
2. Enable developer mode
3. Choose `Load unpacked`
4. Select `extension/`

Build release artifacts:

```bash
cd ~/pve-dcv-integration
./scripts/package.sh
```

Artifacts are written to `dist/`:

- browser extension zip
- thin-client assistant tarball
- USB installer shell script
- thin-client assistant `latest` tarball for the standalone USB writer bootstrap path
- `SHA256SUMS`

Install the latest release on any Proxmox host:

```bash
tmpdir="$(mktemp -d)"
cd "$tmpdir"
curl -fsSLo pve-dcv.tar.gz \
  https://github.com/meinzeug/pve-dcv-integration/releases/latest/download/pve-dcv-thin-client-assistant-latest.tar.gz
tar -xzf pve-dcv.tar.gz
./scripts/install-proxmox-host.sh
```

This installs the project under `/opt/pve-dcv-integration`, rebuilds the packaged artifacts there and deploys the Proxmox UI integration if `/usr/share/pve-manager/` is present.
If a DCV backend can be identified, it also configures an HTTPS proxy on `https://<proxmox-host>:8443/` using the same certificate as the Proxmox web UI.

To force the DCV proxy installation for a specific VM or backend:

```bash
PVE_DCV_PROXY_VMID=100 ./scripts/install-proxmox-host.sh
```

or

```bash
PVE_DCV_PROXY_BACKEND_HOST=10.10.10.100 PVE_DCV_PROXY_BACKEND_PORT=8443 ./scripts/install-proxmox-host.sh
```

Install only the Proxmox UI integration from a release tarball:

```bash
tmpdir="$(mktemp -d)"
cd "$tmpdir"
curl -fsSLo pve-dcv.tar.gz \
  https://github.com/meinzeug/pve-dcv-integration/releases/latest/download/pve-dcv-thin-client-assistant-latest.tar.gz
tar -xzf pve-dcv.tar.gz
./scripts/install-proxmox-ui-integration.sh
```

Build the live installer assets used by the USB writer:

```bash
cd ~/pve-dcv-integration
./scripts/build-thin-client-installer.sh
```

Write a bootable installer stick as a normal user:

```bash
./thin-client-assistant/usb/pve-thin-client-usb-installer.sh
```

List candidate disks before writing:

```bash
./thin-client-assistant/usb/pve-thin-client-usb-installer.sh --list-devices
```

Install the packaged project assets from a local checkout onto a Proxmox host:

```bash
./scripts/install-proxmox-host.sh
```

This deploys the current repository state under `/opt/pve-dcv-integration` and refreshes packaged artifacts there for admin-side distribution.

Install only the Proxmox UI integration on a host:

```bash
./scripts/install-proxmox-ui-integration.sh
```

Install or refresh the DCV TLS proxy on a Proxmox host:

```bash
./scripts/install-proxmox-dcv-proxy.sh
```

## Documentation

- [docs/architecture.md](docs/architecture.md)
- [docs/security.md](docs/security.md)
- [docs/thin-client-installation.md](docs/thin-client-installation.md)
- [thin-client-assistant/README.md](thin-client-assistant/README.md)

## Compatibility assumptions

- Proxmox VE 8.x web UI route patterns
- Chromium-based browsers for the extension
- Debian or Ubuntu style Linux environments for the thin-client assistant baseline
- Local physical thin clients with a graphical session and network access to Proxmox or DCV targets

## License

MIT
