# Security Assumptions

## Scope

This repository does not provide a full identity, access-control or secret-management layer. It assumes Proxmox authentication, DCV authentication and endpoint hardening are handled by the surrounding environment.

## Browser extension assumptions

- The extension only talks to the Proxmox origin the user is already authenticated against.
- API requests use the existing browser session and same-origin cookies.
- No API tokens or passwords are stored in the repository.
- The extension trusts Proxmox API responses and VM description metadata from administrators.

Operational implications:

- treat VM description metadata as admin-controlled input
- do not expose untrusted users to extension-managed launch templates without review
- prefer HTTPS-based DCV URLs

## Thin-client assistant assumptions

- The thin client is a controlled endpoint with local admin access during installation.
- The endpoint is intended for dedicated operational use, not general-purpose browsing.
- The setup stores operational configuration locally on disk.
- The DCV client binary may need to be installed from NICE-provided packages outside this repository.

Recommended hardening:

- use a dedicated local user for the thin-client session
- enable OS auto-login only on physically controlled devices
- restrict shell access for the thin-client account
- place devices in a network segment that can reach Proxmox/DCV but not unnecessary destinations
- pin browser policy or kiosk flags for noVNC deployments
- manage package updates through your standard OS patching process

## Known non-goals in this baseline

- Secure boot provisioning
- Full disk encryption automation
- Central fleet enrollment
- Secret rotation
- Automatic DCV client redistribution
