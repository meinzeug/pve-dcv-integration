# Thin-Client Installation

## Target scenario

This assistant is designed as a first implementation base for a Linux-backed thin client that boots into a dedicated Proxmox access mode.

Supported runtime choices:

- `SPICE`
- `NOVNC`
- `DCV`

The repository also ships a USB writer helper that prepares a removable drive with the thin-client installer payload and a local start menu.
The current USB flow now consists of three layers:

- a local USB writer that can self-escalate to `sudo`
- a host-served payload bundle with prebuilt live assets for the standalone writer path
- a bootable live installer environment
- a local-disk installer that copies the thin-client runtime to the target disk

## Current assumptions

- Debian or Ubuntu style package management
- the USB writer is executed on a Linux workstation with `sudo`
- the live installer is booted on the target device from USB
- the resulting thin-client disk boots a live-style runtime from local disk assets
- the local runtime reapplies its saved hostname and `systemd-networkd` profile before starting the kiosk session

## Installer flow

1. Run `thin-client-assistant/usb/pve-thin-client-usb-installer.sh` on a Linux workstation
2. Select the target USB device
   Or inspect candidates first with `--list-devices`
3. Let the writer download or reuse the live installer assets and write the bootable USB stick
4. Boot the target hardware from the USB stick
5. Use the live setup menu to choose mode, credentials and networking
6. Install the thin-client runtime to the target disk
7. Reboot from the local disk

The repository still keeps `thin-client-assistant/installer/install.sh` for cases where an existing Linux system should be converted in place.

## Mode-specific notes

### SPICE

- requires `remote-viewer` from `virt-viewer`
- supports a direct SPICE URL / `.vv` file
- also supports Proxmox-backed SPICE ticket mode with stored Proxmox host, node, VMID and credentials

### NOVNC

- requires Chromium or a compatible browser
- launches the configured URL in kiosk mode
- can inject stored credentials or tokens into URL templates

### DCV

- requires the native `dcvviewer` client
- generates temporary `.dcv` connection files from the stored URL and credentials
- the live installer image now embeds the NICE DCV Viewer package automatically

## Example commands

Interactive install:

```bash
sudo ./thin-client-assistant/installer/install.sh
```

Install project assets on a Proxmox host for local operator distribution:

```bash
./scripts/install-proxmox-host.sh
```

Install the latest published release on any Proxmox host without cloning the repository:

```bash
tmpdir="$(mktemp -d)"
cd "$tmpdir"
curl -fsSLo pve-dcv.tar.gz \
  https://github.com/meinzeug/pve-dcv-integration/releases/latest/download/pve-dcv-thin-client-assistant-latest.tar.gz
tar -xzf pve-dcv.tar.gz
./scripts/install-proxmox-host.sh
```

If the Proxmox host should publish a DCV session with a valid certificate on `https://<host>:8443/`, either:

- set `PVE_DCV_PROXY_VMID=<vmid>` before running the installer, or
- set `PVE_DCV_PROXY_BACKEND_HOST=<ip-or-host>` and optionally `PVE_DCV_PROXY_BACKEND_PORT=<port>`

The host installer will then configure an `nginx` reverse proxy that reuses the Proxmox TLS certificate from `/etc/pve/local/pveproxy-ssl.pem`.
The same endpoint also publishes the locally built USB artifacts under `https://<host>:8443/pve-dcv-downloads/`.
It also publishes operational metadata under `https://<host>:8443/pve-dcv-downloads/pve-dcv-downloads-status.json`.

Non-interactive install:

```bash
sudo ./thin-client-assistant/installer/install.sh \
  --mode DCV \
  --runtime-user thinclient \
  --dcv-url dcv://dcv-gateway.internal/session/example
```

Prepare a USB installer stick:

```bash
./thin-client-assistant/usb/pve-thin-client-usb-installer.sh --device /dev/sdX
```

The preferred standalone entrypoint is the host-distributed `pve-thin-client-usb-installer-host-latest.sh`, which is preconfigured to fetch the matching payload from the same Proxmox host:

```text
https://<proxmox-host>:8443/pve-dcv-downloads/pve-thin-client-usb-installer-host-latest.sh
```

This avoids pushing the large payload through GitHub releases and keeps the writer aligned with the exact host-side build.

On installed hosts, a systemd timer refreshes these hosted artifacts periodically. You can also run the refresh manually:

```bash
sudo /opt/pve-dcv-integration/scripts/refresh-host-artifacts.sh
```

To verify that a host installation is fully healthy:

```bash
/opt/pve-dcv-integration/scripts/check-proxmox-host.sh
```

List available target devices:

```bash
./thin-client-assistant/usb/pve-thin-client-usb-installer.sh --list-devices
```

Build the live installer assets explicitly:

```bash
./scripts/build-thin-client-installer.sh
```

## Post-install verification

- inspect `/etc/pve-thin-client/thinclient.conf`
- inspect `/run/live/medium/pve-thin-client/state/*.env` on live/local-disk boots
- run `systemctl status pve-thin-client-prepare.service`
- inspect `/run/systemd/network/90-pve-thin-client.network` when booting the live/local runtime
- verify `remote-viewer`, `chromium` or `dcvviewer` is available depending on the mode
- log into the thin-client desktop session and verify the intended client autostarts
