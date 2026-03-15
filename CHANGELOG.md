# Changelog

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
