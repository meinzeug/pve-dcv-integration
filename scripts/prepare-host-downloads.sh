#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
VERSION="$(tr -d ' \n\r' < "$ROOT_DIR/VERSION")"
SERVER_NAME="${PVE_DCV_PROXY_SERVER_NAME:-$(hostname -f 2>/dev/null || hostname)}"
LISTEN_PORT="${PVE_DCV_PROXY_LISTEN_PORT:-8443}"
DOWNLOADS_PATH="${PVE_DCV_DOWNLOADS_PATH:-/beagle-downloads}"
BASE_URL="${PVE_DCV_DOWNLOADS_BASE_URL:-https://${SERVER_NAME}:${LISTEN_PORT}${DOWNLOADS_PATH}}"
HOST_INSTALLER_VERSIONED="$DIST_DIR/pve-thin-client-usb-installer-host-v${VERSION}.sh"
HOST_INSTALLER_LATEST="$DIST_DIR/pve-thin-client-usb-installer-host-latest.sh"
GENERIC_INSTALLER="$DIST_DIR/pve-thin-client-usb-installer-v${VERSION}.sh"
PAYLOAD_URL="${BASE_URL%/}/pve-thin-client-usb-payload-latest.tar.gz"
BOOTSTRAP_URL="${BASE_URL%/}/pve-thin-client-usb-bootstrap-latest.tar.gz"
INSTALLER_URL="${BASE_URL%/}/pve-thin-client-usb-installer-host-latest.sh"
VM_INSTALLER_URL_TEMPLATE="${BASE_URL%/}/pve-thin-client-usb-installer-vm-{vmid}.sh"
STATUS_URL="${BASE_URL%/}/beagle-downloads-status.json"
SHA256SUMS_URL="${BASE_URL%/}/SHA256SUMS"
STATUS_JSON_PATH="$DIST_DIR/beagle-downloads-status.json"
VM_INSTALLERS_METADATA_PATH="$DIST_DIR/beagle-vm-installers.json"
INSTALLER_SHA256=""
PAYLOAD_SHA256=""
BOOTSTRAP_SHA256=""
CREDENTIALS_ENV_FILE="${PVE_DCV_CREDENTIALS_ENV_FILE:-/etc/beagle/credentials.env}"
BEAGLE_MANAGER_ENV_FILE="${PVE_DCV_BEAGLE_MANAGER_ENV_FILE:-/etc/beagle/beagle-manager.env}"

if [[ -f "$CREDENTIALS_ENV_FILE" ]]; then
  # Optional operator-managed defaults for VM installer preset generation.
  # Expected keys: PVE_THIN_CLIENT_DEFAULT_PROXMOX_USERNAME / PASSWORD / TOKEN
  # shellcheck disable=SC1090
  source "$CREDENTIALS_ENV_FILE"
fi

if [[ -f "$BEAGLE_MANAGER_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$BEAGLE_MANAGER_ENV_FILE"
fi

DEFAULT_PROXMOX_USERNAME="${PVE_THIN_CLIENT_DEFAULT_PROXMOX_USERNAME:-${PVE_DCV_PROXMOX_USERNAME:-}}"
DEFAULT_PROXMOX_PASSWORD="${PVE_THIN_CLIENT_DEFAULT_PROXMOX_PASSWORD:-${PVE_DCV_PROXMOX_PASSWORD:-}}"
DEFAULT_PROXMOX_TOKEN="${PVE_THIN_CLIENT_DEFAULT_PROXMOX_TOKEN:-${PVE_DCV_PROXMOX_TOKEN:-}}"
BEAGLE_MANAGER_URL="${PVE_DCV_BEAGLE_MANAGER_URL:-https://${SERVER_NAME}:${LISTEN_PORT}/beagle-api}"
BEAGLE_ENDPOINT_TOKEN="${BEAGLE_ENDPOINT_SHARED_TOKEN:-}"

ensure_dist_permissions() {
  install -d -m 0755 "$DIST_DIR"
  find "$DIST_DIR" -type d -exec chmod 0755 {} +
  find "$DIST_DIR" -type f -exec chmod 0644 {} +
  find "$DIST_DIR" -type f -name '*.sh' -exec chmod 0755 {} +
}

[[ -f "$GENERIC_INSTALLER" ]] || {
  echo "Missing packaged USB installer: $GENERIC_INSTALLER" >&2
  exit 1
}

[[ -f "$DIST_DIR/pve-thin-client-usb-payload-latest.tar.gz" ]] || {
  echo "Missing packaged USB payload: $DIST_DIR/pve-thin-client-usb-payload-latest.tar.gz" >&2
  exit 1
}
[[ -f "$DIST_DIR/pve-thin-client-usb-bootstrap-latest.tar.gz" ]] || {
  echo "Missing packaged USB bootstrap: $DIST_DIR/pve-thin-client-usb-bootstrap-latest.tar.gz" >&2
  exit 1
}

rm -f "$DIST_DIR"/pve-thin-client-usb-installer-vm-*.sh "$VM_INSTALLERS_METADATA_PATH"
install -m 0755 "$GENERIC_INSTALLER" "$HOST_INSTALLER_VERSIONED"

python3 - "$HOST_INSTALLER_VERSIONED" "$BOOTSTRAP_URL" "$PAYLOAD_URL" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
bootstrap_url = sys.argv[2]
payload_url = sys.argv[3]
text = path.read_text()

replacements = {
    r'^RELEASE_BOOTSTRAP_URL="\$\{RELEASE_BOOTSTRAP_URL:-[^"]*}"$':
        f'RELEASE_BOOTSTRAP_URL="${{RELEASE_BOOTSTRAP_URL:-{bootstrap_url}}}"',
    r'^RELEASE_PAYLOAD_URL="\$\{RELEASE_PAYLOAD_URL:-[^"]*}"$':
        f'RELEASE_PAYLOAD_URL="${{RELEASE_PAYLOAD_URL:-{payload_url}}}"',
    r'^INSTALL_PAYLOAD_URL="\$\{INSTALL_PAYLOAD_URL:-[^"]*}"$':
        f'INSTALL_PAYLOAD_URL="${{INSTALL_PAYLOAD_URL:-{payload_url}}}"',
}
updated = text
for pattern, replacement in replacements.items():
    updated, count = re.subn(pattern, replacement, updated, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"failed to patch hosted installer default for pattern: {pattern}")
path.write_text(updated)
PY

install -m 0755 "$HOST_INSTALLER_VERSIONED" "$HOST_INSTALLER_LATEST"

python3 - "$HOST_INSTALLER_VERSIONED" "$DIST_DIR" "$VM_INSTALLERS_METADATA_PATH" "$SERVER_NAME" "$LISTEN_PORT" "$DOWNLOADS_PATH" "$VM_INSTALLER_URL_TEMPLATE" "$BOOTSTRAP_URL" "$PAYLOAD_URL" "$DEFAULT_PROXMOX_USERNAME" "$DEFAULT_PROXMOX_PASSWORD" "$DEFAULT_PROXMOX_TOKEN" "$BEAGLE_MANAGER_URL" "$BEAGLE_ENDPOINT_TOKEN" <<'PY'
import base64
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

template_path = Path(sys.argv[1])
dist_dir = Path(sys.argv[2])
metadata_path = Path(sys.argv[3])
server_name = sys.argv[4]
listen_port = int(sys.argv[5])
downloads_path = sys.argv[6]
installer_url_template = sys.argv[7]
bootstrap_url = sys.argv[8]
payload_url = sys.argv[9]
default_proxmox_username = sys.argv[10]
default_proxmox_password = sys.argv[11]
default_proxmox_token = sys.argv[12]
beagle_manager_url = sys.argv[13]
beagle_endpoint_token = sys.argv[14]
template = template_path.read_text()

resources_cmd = ["pvesh", "get", "/cluster/resources", "--type", "vm", "--output-format", "json"]


def run_json(command):
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None
    try:
        return json.loads(result.stdout or "null")
    except json.JSONDecodeError:
        return None


def parse_description_meta(description):
    meta = {}
    text = str(description or "").replace("\\r\\n", "\n").replace("\\n", "\n")
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip().lower()
        value = value.strip()
        if key and key not in meta:
            meta[key] = value
    return meta


def safe_hostname(name, vmid):
    cleaned = re.sub(r"[^a-z0-9-]+", "-", str(name or "").strip().lower()).strip("-")
    if not cleaned:
        cleaned = f"pve-tc-{vmid}"
    return cleaned[:63].strip("-") or f"pve-tc-{vmid}"


def shell_double_quoted(value):
    return str(value).replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")

def patch_installer_defaults(script_text, bootstrap, payload, preset_name, preset_b64):
    replacements = {
        r'^RELEASE_BOOTSTRAP_URL="\$\{RELEASE_BOOTSTRAP_URL:-[^"]*}"$':
            f'RELEASE_BOOTSTRAP_URL="${{RELEASE_BOOTSTRAP_URL:-{shell_double_quoted(bootstrap)}}}"',
        r'^RELEASE_PAYLOAD_URL="\$\{RELEASE_PAYLOAD_URL:-[^"]*}"$':
            f'RELEASE_PAYLOAD_URL="${{RELEASE_PAYLOAD_URL:-{shell_double_quoted(payload)}}}"',
        r'^INSTALL_PAYLOAD_URL="\$\{INSTALL_PAYLOAD_URL:-[^"]*}"$':
            f'INSTALL_PAYLOAD_URL="${{INSTALL_PAYLOAD_URL:-{shell_double_quoted(payload)}}}"',
        r'^PVE_THIN_CLIENT_PRESET_NAME="\$\{PVE_THIN_CLIENT_PRESET_NAME:-[^"]*}"$':
            f'PVE_THIN_CLIENT_PRESET_NAME="${{PVE_THIN_CLIENT_PRESET_NAME:-{shell_double_quoted(preset_name)}}}"',
        r'^PVE_THIN_CLIENT_PRESET_B64="\$\{PVE_THIN_CLIENT_PRESET_B64:-[^"]*}"$':
            f'PVE_THIN_CLIENT_PRESET_B64="${{PVE_THIN_CLIENT_PRESET_B64:-{shell_double_quoted(preset_b64)}}}"',
    }
    updated = script_text
    for pattern, replacement in replacements.items():
        updated, count = re.subn(pattern, replacement, updated, count=1, flags=re.MULTILINE)
        if count != 1:
            raise SystemExit(f"failed to patch installer default for pattern: {pattern}")
    return updated

def encode_preset(preset):
    lines = ["# Auto-generated VM preset for the thin-client USB installer"]
    for key in sorted(preset):
        value = str(preset.get(key, ""))
        lines.append(f"{key}={shlex.quote(value)}")
    payload = "\n".join(lines) + "\n"
    return base64.b64encode(payload.encode("utf-8")).decode("ascii")


def build_preset(vm, config):
    meta = parse_description_meta(config.get("description", ""))
    vmid = int(vm["vmid"])
    vm_name = config.get("name") or vm.get("name") or f"vm-{vmid}"
    proxmox_scheme = meta.get("proxmox-scheme", "https")
    proxmox_host = meta.get("proxmox-host", server_name)
    proxmox_port = meta.get("proxmox-port", "8006")
    proxmox_realm = meta.get("proxmox-realm", "pam")
    proxmox_verify_tls = meta.get("proxmox-verify-tls", "0")
    proxmox_username = meta.get("proxmox-user", default_proxmox_username)
    proxmox_password = meta.get("proxmox-password", default_proxmox_password)
    proxmox_token = meta.get("proxmox-token", default_proxmox_token)

    moonlight_host = meta.get("moonlight-host") or meta.get("sunshine-host") or meta.get("sunshine-ip") or ""
    sunshine_api_url = meta.get("sunshine-api-url") or (f"https://{moonlight_host}:47990" if moonlight_host else "")
    moonlight_default_mode = "MOONLIGHT" if moonlight_host else ""
    moonlight_resolution = (meta.get("moonlight-resolution") or "").strip()
    if not moonlight_resolution or moonlight_resolution in ("1080", "native", "auto"):
        moonlight_resolution = "auto"

    preset = {
        "PVE_THIN_CLIENT_PRESET_PROFILE_NAME": f"vm-{vmid}",
        "PVE_THIN_CLIENT_PRESET_VM_NAME": vm_name,
        "PVE_THIN_CLIENT_PRESET_HOSTNAME_VALUE": safe_hostname(vm_name, vmid),
        "PVE_THIN_CLIENT_PRESET_AUTOSTART": meta.get("thinclient-autostart", "1"),
        "PVE_THIN_CLIENT_PRESET_DEFAULT_MODE": moonlight_default_mode,
        "PVE_THIN_CLIENT_PRESET_NETWORK_MODE": meta.get("thinclient-network-mode", "dhcp"),
        "PVE_THIN_CLIENT_PRESET_NETWORK_INTERFACE": meta.get("thinclient-network-interface", "eth0"),
        "PVE_THIN_CLIENT_PRESET_PROXMOX_SCHEME": proxmox_scheme,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_HOST": proxmox_host,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_PORT": proxmox_port,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_NODE": vm.get("node", ""),
        "PVE_THIN_CLIENT_PRESET_PROXMOX_VMID": str(vmid),
        "PVE_THIN_CLIENT_PRESET_PROXMOX_REALM": proxmox_realm,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_VERIFY_TLS": proxmox_verify_tls,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_USERNAME": proxmox_username,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_PASSWORD": proxmox_password,
        "PVE_THIN_CLIENT_PRESET_PROXMOX_TOKEN": proxmox_token,
        "PVE_THIN_CLIENT_PRESET_BEAGLE_MANAGER_URL": beagle_manager_url,
        "PVE_THIN_CLIENT_PRESET_BEAGLE_MANAGER_TOKEN": beagle_endpoint_token,
        "PVE_THIN_CLIENT_PRESET_SPICE_METHOD": "",
        "PVE_THIN_CLIENT_PRESET_SPICE_URL": "",
        "PVE_THIN_CLIENT_PRESET_SPICE_USERNAME": "",
        "PVE_THIN_CLIENT_PRESET_SPICE_PASSWORD": "",
        "PVE_THIN_CLIENT_PRESET_SPICE_TOKEN": "",
        "PVE_THIN_CLIENT_PRESET_NOVNC_URL": "",
        "PVE_THIN_CLIENT_PRESET_NOVNC_USERNAME": "",
        "PVE_THIN_CLIENT_PRESET_NOVNC_PASSWORD": "",
        "PVE_THIN_CLIENT_PRESET_NOVNC_TOKEN": "",
        "PVE_THIN_CLIENT_PRESET_DCV_URL": "",
        "PVE_THIN_CLIENT_PRESET_DCV_USERNAME": "",
        "PVE_THIN_CLIENT_PRESET_DCV_PASSWORD": "",
        "PVE_THIN_CLIENT_PRESET_DCV_TOKEN": "",
        "PVE_THIN_CLIENT_PRESET_DCV_SESSION": "",
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_HOST": moonlight_host,
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_APP": meta.get("moonlight-app", meta.get("sunshine-app", "Desktop")),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_BIN": meta.get("moonlight-bin", "moonlight"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_RESOLUTION": moonlight_resolution,
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_FPS": meta.get("moonlight-fps", "60"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_BITRATE": meta.get("moonlight-bitrate", "20000"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_VIDEO_CODEC": meta.get("moonlight-video-codec", "H.264"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_VIDEO_DECODER": meta.get("moonlight-video-decoder", "auto"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_AUDIO_CONFIG": meta.get("moonlight-audio-config", "stereo"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_ABSOLUTE_MOUSE": meta.get("moonlight-absolute-mouse", "1"),
        "PVE_THIN_CLIENT_PRESET_MOONLIGHT_QUIT_AFTER": meta.get("moonlight-quit-after", "0"),
        "PVE_THIN_CLIENT_PRESET_SUNSHINE_API_URL": sunshine_api_url,
        "PVE_THIN_CLIENT_PRESET_SUNSHINE_USERNAME": meta.get("sunshine-user", ""),
        "PVE_THIN_CLIENT_PRESET_SUNSHINE_PASSWORD": meta.get("sunshine-password", ""),
        "PVE_THIN_CLIENT_PRESET_SUNSHINE_PIN": meta.get("sunshine-pin", f"{vmid % 10000:04d}"),
    }

    available_modes = ["MOONLIGHT"] if preset["PVE_THIN_CLIENT_PRESET_MOONLIGHT_HOST"] else []
    preset["PVE_THIN_CLIENT_PRESET_DEFAULT_MODE"] = "MOONLIGHT" if available_modes else ""

    return preset, available_modes


resources = run_json(resources_cmd)
vm_installers = []

if not resources:
    metadata_path.write_text("[]\n")
    raise SystemExit(0)

for vm in resources:
    if vm.get("type") != "qemu" or vm.get("vmid") is None or not vm.get("node"):
        continue

    config = run_json(
        [
            "pvesh",
            "get",
            f"/nodes/{vm['node']}/qemu/{vm['vmid']}/config",
            "--output-format",
            "json",
        ]
    ) or {}
    preset, available_modes = build_preset(vm, config)
    preset_name = preset.get("PVE_THIN_CLIENT_PRESET_PROFILE_NAME") or f"vm-{vm['vmid']}"
    preset_b64 = encode_preset(preset)
    installer_name = f"pve-thin-client-usb-installer-vm-{vm['vmid']}.sh"
    installer_path = dist_dir / installer_name
    installer_path.write_text(patch_installer_defaults(template, bootstrap_url, payload_url, preset_name, preset_b64))
    installer_path.chmod(0o755)
    vm_installers.append(
        {
            "vmid": int(vm["vmid"]),
            "node": vm["node"],
            "name": preset["PVE_THIN_CLIENT_PRESET_VM_NAME"],
            "preset_name": preset_name,
            "default_mode": preset.get("PVE_THIN_CLIENT_PRESET_DEFAULT_MODE", ""),
            "installer_filename": installer_name,
            "installer_url": installer_url_template.replace("{vmid}", str(vm["vmid"])),
            "available_modes": available_modes,
        }
    )

metadata_path.write_text(json.dumps(sorted(vm_installers, key=lambda item: item["vmid"]), indent=2) + "\n")
PY

ensure_dist_permissions

INSTALLER_SHA256="$(sha256sum "$HOST_INSTALLER_LATEST" | awk '{print $1}')"
PAYLOAD_SHA256="$(sha256sum "$DIST_DIR/pve-thin-client-usb-payload-latest.tar.gz" | awk '{print $1}')"
BOOTSTRAP_SHA256="$(sha256sum "$DIST_DIR/pve-thin-client-usb-bootstrap-latest.tar.gz" | awk '{print $1}')"

cat > "$DIST_DIR/beagle-downloads-index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Beagle OS Downloads</title>
  <style>
    body { font-family: sans-serif; margin: 2rem auto; max-width: 60rem; line-height: 1.5; padding: 0 1rem; }
    code { background: #f4f4f4; padding: 0.15rem 0.3rem; border-radius: 0.25rem; }
    table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
    th, td { border-bottom: 1px solid #ddd; padding: 0.55rem; text-align: left; vertical-align: top; }
    th { width: 18rem; }
  </style>
</head>
<body>
  <h1>Beagle OS Downloads</h1>
  <p>Host-local thin-client media downloads for this Proxmox server.</p>
  <ul>
    <li><a href="${DOWNLOADS_PATH%/}/pve-thin-client-usb-installer-host-latest.sh">Generic USB installer launcher (fallback)</a></li>
    <li><a href="${DOWNLOADS_PATH%/}/pve-thin-client-usb-bootstrap-latest.tar.gz">USB bootstrap bundle (used while creating installer media)</a></li>
    <li><a href="${DOWNLOADS_PATH%/}/pve-thin-client-usb-payload-latest.tar.gz">USB payload bundle</a></li>
    <li>VM-specific installer URLs now embed a full preset (host, vmid, node, credentials, stream defaults) so the thin client install can run without manual VM data entry.</li>
    <li>The generic installer remains available as fallback when no VM-specific preset should be embedded.</li>
    <li><a href="${DOWNLOADS_PATH%/}/beagle-downloads-status.json">Status JSON</a></li>
    <li><a href="${DOWNLOADS_PATH%/}/SHA256SUMS">SHA256SUMS</a></li>
  </ul>
  <p>The hosted USB installers download only a bootstrap bundle during USB creation. During target installation, the thin client fetches the latest payload directly from this Proxmox host. VM-specific installers ship with embedded presets so thin clients can be installed without manual profile input.</p>
  <table>
    <tr><th>Release version</th><td><code>${VERSION}</code></td></tr>
    <tr><th>Server</th><td><code>${SERVER_NAME}:${LISTEN_PORT}</code></td></tr>
    <tr><th>VM installer template</th><td><code>${VM_INSTALLER_URL_TEMPLATE}</code></td></tr>
    <tr><th>Status JSON</th><td><a href="${DOWNLOADS_PATH%/}/beagle-downloads-status.json">${STATUS_URL}</a></td></tr>
    <tr><th>SHA256SUMS</th><td><a href="${DOWNLOADS_PATH%/}/SHA256SUMS">${SHA256SUMS_URL}</a></td></tr>
    <tr><th>Hosted installer SHA256</th><td><code>${INSTALLER_SHA256}</code></td></tr>
    <tr><th>Bootstrap SHA256</th><td><code>${BOOTSTRAP_SHA256}</code></td></tr>
    <tr><th>Payload SHA256</th><td><code>${PAYLOAD_SHA256}</code></td></tr>
  </table>
</body>
</html>
EOF

python3 - "$STATUS_JSON_PATH" "$VERSION" "$SERVER_NAME" "$LISTEN_PORT" "$DOWNLOADS_PATH" "$INSTALLER_URL" "$BOOTSTRAP_URL" "$PAYLOAD_URL" "$STATUS_URL" "$SHA256SUMS_URL" "$HOST_INSTALLER_LATEST" "$DIST_DIR/pve-thin-client-usb-bootstrap-latest.tar.gz" "$DIST_DIR/pve-thin-client-usb-payload-latest.tar.gz" "$INSTALLER_SHA256" "$BOOTSTRAP_SHA256" "$PAYLOAD_SHA256" "$VM_INSTALLER_URL_TEMPLATE" "$VM_INSTALLERS_METADATA_PATH" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

status_path = Path(sys.argv[1])
version = sys.argv[2]
server_name = sys.argv[3]
listen_port = int(sys.argv[4])
downloads_path = sys.argv[5]
installer_url = sys.argv[6]
bootstrap_url = sys.argv[7]
payload_url = sys.argv[8]
status_url = sys.argv[9]
sha256sums_url = sys.argv[10]
installer_path = Path(sys.argv[11])
bootstrap_path = Path(sys.argv[12])
payload_path = Path(sys.argv[13])
installer_sha256 = sys.argv[14]
bootstrap_sha256 = sys.argv[15]
payload_sha256 = sys.argv[16]
vm_installer_url_template = sys.argv[17]
vm_installers_path = Path(sys.argv[18])
vm_installers = json.loads(vm_installers_path.read_text()) if vm_installers_path.exists() else []

payload = {
    "version": version,
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "server_name": server_name,
    "listen_port": listen_port,
    "downloads_path": downloads_path,
    "installer_url": installer_url,
    "bootstrap_url": bootstrap_url,
    "payload_url": payload_url,
    "status_url": status_url,
    "sha256sums_url": sha256sums_url,
    "installer_size": installer_path.stat().st_size,
    "bootstrap_size": bootstrap_path.stat().st_size,
    "payload_size": payload_path.stat().st_size,
    "installer_sha256": installer_sha256,
    "bootstrap_sha256": bootstrap_sha256,
    "payload_sha256": payload_sha256,
    "installer_filename": installer_path.name,
    "bootstrap_filename": bootstrap_path.name,
    "payload_filename": payload_path.name,
    "vm_installer_url_template": vm_installer_url_template,
    "vm_installer_count": len(vm_installers),
    "vm_installers": vm_installers,
}
status_path.write_text(json.dumps(payload, indent=2) + "\n")
PY

echo "Prepared host-local download artifacts under $DIST_DIR"
echo "Hosted USB installer URL: $INSTALLER_URL"
