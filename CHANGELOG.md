# Changelog

## v3.4.0 - 2026-03-22

- Added a first-class Beagle VM profile dialog to both the host-installed Proxmox UI and the browser extension, so operators can inspect a fully resolved Moonlight/Sunshine endpoint profile per VM and export it directly from the Proxmox workflow.
- Added installer, profile-export and control-plane health actions to the Beagle UI path, turning the Proxmox integration into an operator surface instead of a single download trigger.
- Added a host-side `beagle-control-plane` service that publishes Beagle health and VM inventory data for installed Proxmox hosts.
- Narrowed Beagle preset generation to Moonlight/Sunshine-only profiles so new per-VM installers no longer publish legacy SPICE, noVNC or DCV fallbacks in Beagle profiles.
- Updated the main architecture, installation and security documentation to describe Beagle as a Proxmox-native Moonlight/Sunshine endpoint and management stack.

## v3.3.1 - 2026-03-17

- Fixed the Sunshine guest provisioning path so LightDM is forced in as the actual `display-manager.service`, replacing the stale `gdm3` default that kept the Xfce autologin desktop from coming up after the first reboot.
- Locked Sunshine guest defaults to H.264-only software streaming by explicitly disabling HEVC and AV1 in the generated `sunshine.conf`, matching the low-latency CPU-only target profile for this host.
- Tightened the Xfce autostart path so Sunshine starts only inside the intended Xfce session rather than relying on generic desktop autostart semantics.
- Added a lightweight Xfce window-manager profile for provisioned guests that disables compositor overhead by default, leaving more CPU budget available for software capture and encoding.
- Updated the Proxmox host installer to reuse packaged GitHub release assets for the USB installer and payload when they are available, so release-tarball installs no longer have to rebuild the live image locally on every host.

## v3.3.0 - 2026-03-17

- Added a first-class `MOONLIGHT` runtime mode that auto-pairs against Sunshine through its authenticated `/api/pin` endpoint and then starts a preseeded Moonlight desktop stream without asking the operator for any extra runtime details.
- Extended the thin-client configuration model with Moonlight host/app, codec, decoder, bitrate, resolution, FPS and Sunshine API credentials so the installed target keeps all Sunshine-specific state outside the old SPICE/noVNC/DCV-only path.
- Added a live-build hook that bundles Moonlight from the official upstream AppImage into the installer image as a local wrapper binary, removing any dependency on distro packaging for the client itself.
- Expanded VM preset generation so host-served per-VM USB installers can embed Sunshine/Moonlight defaults including auto-pairing PIN, Sunshine API URL, default mode and a low-latency H.264 1080p60 profile.
- Upgraded the graphical USB installer dashboard and local installer preset flow to understand `MOONLIGHT`, prefer preset-defined default modes and surface Sunshine target metadata directly in the on-stick UI.
- Kept the old SPICE, noVNC and DCV paths intact as secondary modes, so mixed environments can publish Moonlight first while still exposing the legacy fallbacks per VM.

## v3.2.1 - 2026-03-16

- Fixed the host installer so `/opt/pve-dcv-integration` is always normalized to `root:root` with world-executable directory permissions after deployment, preventing `nginx` from returning `403 Forbidden` on hosted USB download artifacts.

## v3.2.0 - 2026-03-16

- Replaced the old text-only installer boot path with a local Chromium app front end that serves a richer USB installer dashboard from the live medium itself.
- Added bundled Unsplash-backed JPEG artwork for the boot medium and installer UI so the USB experience has a graphical hero background and mode cards without relying on live internet access.
- Added graphical installer actions for install, preset inspection, shell, reboot and poweroff while keeping the existing shell-based installer as a fallback underneath.
- Extended the local installer with JSON/state endpoints and noninteractive flags so the graphical front end can drive mode selection and disk targeting without re-asking the user in text dialogs.
- Upgraded the USB writer on graphical Linux desktops to prefer `zenity`-based target selection and confirmation instead of falling straight back to `whiptail`.
- Styled GRUB on both the USB stick and installed thin-client target with a bundled JPEG background so the media looks intentional from first boot onward.

## v3.1.0 - 2026-03-16

- Reworked the USB deployment flow around backend-generated per-VM installer launchers named `pve-thin-client-usb-installer-vm-<vmid>.sh`, so the Proxmox toolbar can hand each VM its own preseeded thin-client installer download.
- Embedded VM-specific connection presets directly into the hosted USB installer and wrote them onto the USB medium as `pve-thin-client/preset.env`, preserving those presets across the writer's `sudo` escalation boundary.
- Simplified the USB local-install path so bundled media now asks only for the streaming mode and the target disk; the previous full questionnaire remains only as a fallback for non-preseeded media.
- Added preset-aware mode validation for `SPICE`, `NOVNC` and `DCV`, including automatic single-mode selection when only one streaming target is configured for the chosen VM.
- Updated the Proxmox host UI and browser extension so the `USB Installer` action resolves a VM-specific download URL template with `{host}`, `{node}` and `{vmid}` placeholders instead of always pointing to a generic host-wide launcher.
- Expanded hosted download metadata with a VM installer URL template and machine-readable VM installer inventory under `dist/pve-dcv-vm-installers.json` and the published downloads status JSON.
- Added persistent Proxmox UI reapply units so package updates or replaced `/usr/share/pve-manager` assets automatically reinstall the integration on the next file change and again on subsequent boots.

## v3.0.2 - 2026-03-16

- Fixed hosted USB payload checksum verification in standalone mode by downloading the payload under its original release filename, so `SHA256SUMS` can be checked successfully before extraction.

## v3.0.1 - 2026-03-16

- Fixed the standalone USB installer launcher so it no longer tries to read `VERSION` from a non-repository path before the hosted payload bundle has been downloaded and extracted.

## v3.0.0 - 2026-03-15

- Expanded the Proxmox host UI from a single `DCV` action into a small operator toolset with dedicated toolbar buttons for `DCV`, `Copy DCV URL`, `DCV Info`, `USB Installer` and `Downloads Status`.
- Added matching Proxmox console-menu actions for `Copy DCV URL`, `DCV Info` and `DCV Downloads` in the host-installed UI integration.
- Added resolved-launch introspection in the host UI so operators can see whether a DCV launch came from `dcv-url`, metadata fallbacks, guest-agent IP discovery or the configured fallback URL.
- Added clipboard integration in the host UI for copying fully resolved DCV URLs without launching the session immediately.
- Added a host-side `DCV Info` dialog that exposes VM, source, session, token presence, auto-submit state and the hosted download-status endpoint.
- Expanded the browser extension toolbar with direct `DCV`, `Copy DCV URL`, `DCV Info`, `USB Installer` and `Downloads Status` buttons on VM views.
- Added matching browser-extension console-menu actions for `Copy DCV URL`, `DCV Info` and `Downloads Status`.
- Added extension-side resolved-launch inspection so operators can inspect the computed target and metadata source even when they are not using the host-installed UI integration.
- Added extension-side clipboard copying for the resolved DCV URL, reducing trial launches during admin work.
- Added extension-side direct access to the host-local download status JSON so frontend operators can jump from a VM view straight to the published thin-client artifact status.

## v2.0.0 - 2026-03-15

- Promoted the project to a major operational release with stricter host-side health validation, richer hosted download metadata and persistent refresh run-state tracking.
- Expanded `/pve-dcv-downloads/pve-dcv-downloads-status.json` to include server identity, published paths, artifact filenames, sizes and SHA256 checksums for both the hosted installer and payload bundle.
- Upgraded the hosted download index page so operators can inspect release version, host endpoint and checksums directly from the browser without opening raw JSON.
- Added persistent refresh result logging under `/var/lib/pve-dcv-integration/refresh.status.json` so automated artifact rebuilds leave a machine-readable success/failure record behind.
- Hardened `check-proxmox-host.sh` to verify service activity, hosted URL binding, status JSON consistency and on-disk SHA256 parity instead of only checking for file presence.
- Carried forward the previous USB and DCV runtime hardening as the stable baseline for the 2.0 line.

## v0.5.1 - 2026-03-15

- Hardened the USB writer so it refuses non-removable or system disks by default, enforces a minimum device size and waits for freshly created partitions before formatting them.
- Added SHA256 verification for hosted USB payload downloads when `SHA256SUMS` is available and now validates live installer assets both before and after they are copied to the target media.
- Hardened the DCV thin-client launch path by enforcing safer `.dcv` file permissions, validating token/session combinations and supporting browser fallback when `dcvviewer` is unavailable but a proxied HTTPS DCV endpoint exists.
- Restored the Proxmox host UI asset in the working tree so host deployments remain reproducible after the local interrupted edit sequence.

## v0.5.0 - 2026-03-15

- Added production-oriented host operations tooling: a hosted-artifact refresh script, an installable systemd service/timer and a host healthcheck command.
- Added release automation and project validation scripts so future GitHub releases can be built and published reproducibly without re-uploading the large USB payload artifact.
- Added host-side download status metadata and a dedicated status JSON under `/pve-dcv-downloads/`.
- Updated packaging and host deployment to include Proxmox host service templates and to install the recurring host artifact refresh timer.

## v0.4.7 - 2026-03-15

- Fixed the host-side `nginx` download location so `/pve-dcv-downloads/<file>` is served as a real prefix path instead of falling through to the DCV backend.
- Revalidated the Proxmox-hosted USB installer endpoint on `srv.thinover.net` after the hosted download routing fix.

## v0.4.6 - 2026-03-15

- Reworked the USB distribution path so the large thin-client payload is served by each installed Proxmox host under `/pve-dcv-downloads/` instead of being expected from GitHub releases.
- Added host-local download preparation that generates a Proxmox-hosted USB installer script with the correct local payload URL baked in.
- Extended the Proxmox-side `nginx` setup to always publish hosted download artifacts on `https://<proxmox-host>:8443/pve-dcv-downloads/`, even when no DCV backend proxy is configured.
- Added a Proxmox UI runtime config asset so the `USB Installer` toolbar button opens the host-local installer endpoint by default.

## v0.4.5 - 2026-03-15

- Fixed DCV launch URL generation so `dcv-url` in VM metadata always overrides the internal guest IP template path.
- Fixed metadata parsing for VM descriptions that contain literal `\\n` separators, preventing `dcv-user` and `dcv-password` from being merged into one query value.
- Revalidated the server-installed Proxmox UI integration on `srv.thinover.net` with the public DCV proxy URL `https://srv.thinover.net:8443/`.

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
