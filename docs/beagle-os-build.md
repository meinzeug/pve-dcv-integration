# Build Beagle OS (Own Kernel)

This project now includes a standalone OS build pipeline that creates a real Beagle OS disk image with:

- a custom self-built Linux kernel (`-beagle` localversion)
- a Debian-based root filesystem created via `debootstrap`
- UEFI boot via GRUB
- VM-ready artifacts (`.raw` and `.qcow2`)

## 1. Build the OS image

Run from the repository root:

```bash
./scripts/build-beagle-os.sh \
  --kernel-version 6.12.22 \
  --kernel-localversion -beagle \
  --hostname beagle-os
```

The first run installs required host packages and then compiles the kernel package. This can take a while.

Artifacts are written to:

- `dist/beagle-os/beagle-os-<release>-<arch>-k<kernel><localversion>.raw`
- `dist/beagle-os/beagle-os-<release>-<arch>-k<kernel><localversion>.qcow2`

## 2. Reuse an existing kernel package (faster rebuilds)

If you already built a kernel package once, you can skip kernel compilation:

```bash
./scripts/build-beagle-os.sh \
  --skip-kernel-build \
  --kernel-deb /absolute/path/to/linux-image-*-beagle*_amd64.deb
```

## 3. Import the image into Proxmox (example VM 101)

On the Proxmox host:

```bash
# Example: copy qcow2 to host
scp dist/beagle-os/*.qcow2 thinovernet:/tmp/beagle-os.qcow2

# Create VM 101 (UEFI)
ssh thinovernet 'sudo qm create 101 \
  --name beagle-os-101 \
  --memory 4096 \
  --cores 4 \
  --cpu host \
  --machine q35 \
  --bios ovmf \
  --net0 virtio,bridge=vmbr1 \
  --agent enabled=1'

# Import disk and wire boot
ssh thinovernet 'sudo qm importdisk 101 /tmp/beagle-os.qcow2 local'
ssh thinovernet 'sudo qm set 101 --scsihw virtio-scsi-single --scsi0 local:101/vm-101-disk-0.raw'
ssh thinovernet 'sudo qm set 101 --efidisk0 local:101/vm-101-disk-1.raw,efitype=4m,pre-enrolled-keys=1'
ssh thinovernet 'sudo qm set 101 --boot order=scsi0'
ssh thinovernet 'sudo qm start 101'
```

## Notes

- Current script targets `amd64` only.
- The generated image is UEFI-first (`OVMF` in Proxmox).
- Default runtime user inside the image is `thinclient` with initial password `thinclient`.
- Root account is locked by default.
