# Thin-Client Installation

## Target scenario

Beagle OS is built for one endpoint model:

- `Sunshine` runs inside the streamed VM
- `Moonlight` runs on the endpoint
- `Proxmox` provides inventory, metadata and installer distribution

The repository ships both the Beagle endpoint runtime and the USB/local-disk installation path used to put that runtime onto real hardware or test VMs.

## Current assumptions

- Debian or Ubuntu style package management on the build/installer side
- the USB writer is executed on a Linux workstation with `sudo`
- the resulting endpoint is a dedicated Beagle device, not a general-purpose desktop
- the endpoint boots directly into a Moonlight session against a Proxmox-assigned Sunshine VM

## Installation flow

1. Install the Beagle integration on the Proxmox host.
2. Prepare the target VM with Sunshine.
3. Store the Beagle metadata on that VM in Proxmox.
4. Download the VM-specific Beagle installer from the Proxmox UI.
5. Write the installer to USB or install directly to a target disk.
6. Boot the endpoint and verify that Moonlight starts against the intended VM.

The preferred operator path is now VM-centric: the Proxmox host publishes one installer per VM, already seeded with the correct Beagle profile.

## Moonlight profile behavior

A Beagle profile contains:

- the Sunshine host / API URL
- the Moonlight app name, usually `Desktop`
- codec, decoder, bitrate, FPS and audio defaults
- optional Sunshine credentials and pairing PIN
- the bound Proxmox node and VMID

This means a Beagle endpoint does not need manual target entry during rollout.
The endpoint simply boots with the profile that belongs to the streamed VM.

## Example commands

Interactive install on an existing Linux system:

```bash
sudo ./thin-client-assistant/installer/install.sh
```

Install project assets on a Proxmox host for local operator distribution:

```bash
./scripts/install-proxmox-host.sh
```

Provision an Ubuntu guest for the preferred Sunshine path:

```bash
./scripts/configure-sunshine-guest.sh \
  --proxmox-host thinovernet \
  --vmid 100 \
  --guest-user dennis \
  --sunshine-user sunshine \
  --sunshine-password 'choose-a-strong-password'
```

Register a Beagle endpoint certificate on the Sunshine VM without interactive pairing:

```bash
./scripts/register-moonlight-client-on-sunshine.sh \
  --client-config Moonlight.conf \
  --sunshine-state /home/dennis/.config/sunshine/sunshine_state.json \
  --device-name beagle-os-101
```

Install the latest published release on a Proxmox host without cloning the repository:

```bash
tmpdir="$(mktemp -d)"
cd "$tmpdir"
curl -fsSLo beagle-os.tar.gz \
  https://github.com/meinzeug/beagle-os/releases/latest/download/beagle-os-latest.tar.gz
tar -xzf beagle-os.tar.gz
./scripts/install-proxmox-host.sh
```

## Hosted installer endpoints

The Beagle host publishes these operator-facing endpoints:

- VM-specific installer: `https://<proxmox-host>:8443/beagle-downloads/pve-thin-client-usb-installer-vm-<vmid>.sh`
- generic fallback installer: `https://<proxmox-host>:8443/beagle-downloads/pve-thin-client-usb-installer-host-latest.sh`
- hosted status JSON: `https://<proxmox-host>:8443/beagle-downloads/beagle-downloads-status.json`
- Beagle control-plane health: `https://<proxmox-host>:8443/beagle-api/api/v1/health`

## Build and validation commands

Prepare a USB installer stick:

```bash
./thin-client-assistant/usb/pve-thin-client-usb-installer.sh --device /dev/sdX
```

Build the live installer assets explicitly:

```bash
./scripts/build-thin-client-installer.sh
```

Build the Beagle OS image directly:

```bash
./scripts/build-beagle-os.sh
```

Refresh hosted artifacts on an installed Proxmox host:

```bash
sudo /opt/beagle/scripts/refresh-host-artifacts.sh
```

Verify that a host installation is healthy:

```bash
/opt/beagle/scripts/check-proxmox-host.sh
```

## Post-install verification

- inspect `/etc/pve-thin-client/thinclient.conf`
- inspect `/etc/beagle-os/endpoint.env` on Beagle OS images
- run `systemctl status pve-thin-client-prepare.service`
- verify `moonlight` is available on the endpoint
- verify `moonlight list <sunshine-host>` resolves the streamed target app
- verify the endpoint can actually start the Sunshine `Desktop` stream for the assigned VM
