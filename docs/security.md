# Security Assumptions

## Scope

This repository does not provide a complete identity, secret-rotation or fleet-enrollment layer.
It assumes Proxmox access, Sunshine access and endpoint hardening are managed by the surrounding environment.

## Proxmox operator surface

- The browser extension only talks to the Proxmox origin the user is already authenticated against.
- The host-installed UI integration resolves Beagle profile data from Proxmox API state and VM metadata.
- VM description metadata is treated as administrator-controlled configuration.
- Beagle profile exports can contain Sunshine credentials when the operator stores them in VM metadata.

Operational implications:

- treat VM description metadata as sensitive administrative input
- limit who may edit or inspect Beagle-enabled VM descriptions
- prefer dedicated Proxmox roles for operators who manage Beagle endpoints

## Thin-client endpoint assumptions

- The endpoint is a controlled device with dedicated operational purpose.
- Local autologin is acceptable only on physically controlled hardware.
- Beagle stores runtime configuration locally on disk.
- Sunshine credentials and pairing data may be present on the endpoint if the deployment model requires unattended startup.

Recommended hardening:

- use a dedicated runtime user for the Beagle session
- restrict shell access for the endpoint account
- place endpoints in a network segment that can reach Proxmox and Sunshine, but not unnecessary destinations
- manage OS and package updates through standard patching workflows
- protect exported `endpoint.env` files and support bundles as operational secrets

## Control plane assumptions

- The Beagle control plane is intended to run behind the Proxmox host boundary.
- Public health data may be exposed through the bundled `8443` endpoint.
- Inventory endpoints should be treated as management APIs, not end-user APIs.

## Known non-goals in this baseline

- secure boot provisioning
- full disk encryption automation
- central secret rotation
- tenant-isolated multitenancy
- zero-touch hardware enrollment
