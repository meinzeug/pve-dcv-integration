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

### 2. Linux thin-client assistant

- Provides an installer-oriented base for local deployment onto a Linux-backed thin client.
- Includes an interactive setup menu with three target modes: `SPICE`, `noVNC`, `DCV`.
- Stores the target runtime configuration in a dedicated config file.
- Installs runtime launchers, XDG autostart integration and systemd preparation logic.
- Separates installer logic, runtime logic, templates and system assets.

## Repository layout

- `extension/` Chromium extension for the Proxmox DCV action
- `thin-client-assistant/` installer, runtime, templates, systemd unit and sample configs
- `docs/` architecture, security and installation documentation
- `scripts/` release packaging helpers

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
- `installer/setup-menu.sh` collects the target mode and launch values
- `runtime/launch-session.sh` starts the chosen client mode
- `runtime/prepare-runtime.sh` validates runtime prerequisites on boot
- `systemd/pve-thin-client-prepare.service` prepares the environment before graphical login
- `templates/` provides config, autostart and environment file templates

Runtime modes:

- `SPICE` launches `remote-viewer`
- `noVNC` launches Chromium in kiosk mode against a configured URL
- `DCV` launches the native `dcvviewer` client

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
- `SHA256SUMS`

Install the packaged project assets onto a Proxmox host:

```bash
sudo ./scripts/install-proxmox-host.sh
```

This deploys the current repository state under `/opt/pve-dcv-integration` and refreshes packaged artifacts there for admin-side distribution.

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
