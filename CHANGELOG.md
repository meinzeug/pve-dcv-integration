# Changelog

## v0.4.4 - 2026-03-15

- Fixed the standalone USB writer bootstrap path by moving large release extraction out of space-constrained `/tmp` defaults and into a more suitable temporary location.
- Fixed USB media rewriting on already mounted sticks by unmounting target partitions before calling `wipefs`.
- Added a dedicated release USB payload tarball with prebuilt live installer assets so `pve-thin-client-usb-installer-latest.sh` no longer depends on a local `live-build` run in the normal path.
- Hardened the live-build helper to populate its build tree through `sudo` consistently, preventing permission issues during debootstrap/chroot setup.

## v0.4.3 - 2026-03-15

- Added DCV metadata support for `dcv-user`, `dcv-password`, `dcv-auth-token`, `dcv-session` and `dcv-auto-submit`.
- Added browser-side and proxied-page DCV auto-login helpers so VM-specific credentials can be prefilled and submitted automatically when opening DCV from Proxmox.
- Added host-side DCV proxy injection of `pve-dcv-autologin.js` so the server-installed Proxmox integration can auto-fill the DCV web login page without a browser extension.

## v0.4.2 - 2026-03-15

- Added a Proxmox-host DCV TLS proxy installer that can publish a backend DCV service on `https://<proxmox-host>:8443/` with the already valid Proxmox certificate.
- Integrated DCV proxy deployment into the standard Proxmox host installer so UI deployment can also fix invalid/self-signed DCV web certificates.
- Added backend auto-detection from VM metadata and guest-agent IPs, plus explicit `PVE_DCV_PROXY_VMID` and `PVE_DCV_PROXY_BACKEND_HOST` installation controls.
- Added cleanup of legacy host-side `iptables` DNAT rules on the DCV port so the local TLS proxy can bind cleanly.

## v0.4.1 - 2026-03-15

- Added a documented GitHub-release installation path for deploying the project onto arbitrary Proxmox hosts without a git checkout.
- Updated the Proxmox host installers to self-escalate through `sudo` instead of requiring an explicit root invocation from the user.
- Added automatic `rsync` dependency installation for the host deployment script so extracted release tarballs are directly installable on fresh hosts.
- Fixed the release tarball contents so host deployments from GitHub releases include the Proxmox UI asset and extension sources needed for repackaging.

## v0.4.0 - 2026-03-15

- Rebuilt the USB installer flow around a bootable live installer architecture inspired by the existing ThinOverNet approach.
- Replaced the old root-only USB writer with a sudo-escalating writer that selects target devices interactively and can bootstrap the release payload automatically.
- Added a live-build based thin-client installer environment, a live setup menu and a local disk installer that copies a bootable thin-client runtime to the target disk.
- Expanded the thin-client configuration model with network, credentials, Proxmox SPICE ticket mode and generated DCV connection files.
- Added runtime helpers for Proxmox-backed SPICE auto-connect and direct DCV connection-file generation.
- Fixed BIOS+UEFI USB and local-disk partition layouts by adding explicit `bios_grub` partitions for GRUB-on-GPT boot paths.
- Added runtime hostname/network application through generated `systemd-networkd` config and enabled the live image to run that preparation path before launching the kiosk session.
- Added NICE DCV Viewer installation to the live-build image so the DCV runtime path is usable from the generated installer media.

## v0.3.0 - 2026-03-15

- Reworked the extension to inject `DCV` into the existing Proxmox console dropdown instead of using only a floating page button.
- Added a `USB Installer` toolbar button that downloads the thin-client USB writer script.
- Added a first USB writer script and starter payload for building a deployable thin-client installer stick.

## v0.2.1 - 2026-03-15

- Added explicit packaging dependency checks for `zip`, `tar` and `sha256sum`.
- Hardened the Proxmox host deployment path after validating installation on a live Proxmox VE 8.4 host.

## v0.2.0 - 2026-03-15

- Added a production-oriented repository layout for the browser extension, thin-client assistant, docs and release scripts.
- Expanded the Proxmox browser extension with stronger VM context detection, metadata fallbacks and configurable launch behavior.
- Added a first functional Linux thin-client assistant with installer, setup menu, runtime launchers, config templates and autostart assets.
- Added architecture, security and installation documentation.
- Added release packaging for extension and thin-client assistant artifacts with checksums.

## v0.1.0 - 2026-03-15

- Initial third-party Proxmox web extension.
- Adds `DCV` action button on VM pages.
- Resolves VM IP via guest-agent API.
- Supports URL-template and fallback parsing from VM description.
- Release packaging script.
