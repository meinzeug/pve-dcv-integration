#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
VERSION="$(tr -d ' \n\r' < "$ROOT_DIR/VERSION")"
SERVER_NAME="${PVE_DCV_PROXY_SERVER_NAME:-$(hostname -f 2>/dev/null || hostname)}"
LISTEN_PORT="${PVE_DCV_PROXY_LISTEN_PORT:-8443}"
DOWNLOADS_PATH="${PVE_DCV_DOWNLOADS_PATH:-/pve-dcv-downloads}"
BASE_URL="${PVE_DCV_DOWNLOADS_BASE_URL:-https://${SERVER_NAME}:${LISTEN_PORT}${DOWNLOADS_PATH}}"
HOST_INSTALLER_VERSIONED="$DIST_DIR/pve-thin-client-usb-installer-host-v${VERSION}.sh"
HOST_INSTALLER_LATEST="$DIST_DIR/pve-thin-client-usb-installer-host-latest.sh"
GENERIC_INSTALLER="$DIST_DIR/pve-thin-client-usb-installer-v${VERSION}.sh"
PAYLOAD_URL="${BASE_URL%/}/pve-thin-client-usb-payload-latest.tar.gz"

[[ -f "$GENERIC_INSTALLER" ]] || {
  echo "Missing packaged USB installer: $GENERIC_INSTALLER" >&2
  exit 1
}

[[ -f "$DIST_DIR/pve-thin-client-usb-payload-latest.tar.gz" ]] || {
  echo "Missing packaged USB payload: $DIST_DIR/pve-thin-client-usb-payload-latest.tar.gz" >&2
  exit 1
}

install -m 0755 "$GENERIC_INSTALLER" "$HOST_INSTALLER_VERSIONED"

python3 - "$HOST_INSTALLER_VERSIONED" "$PAYLOAD_URL" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload_url = sys.argv[2]
text = path.read_text()
pattern = r'^RELEASE_PAYLOAD_URL="\$\{RELEASE_PAYLOAD_URL:-[^"]*}"$'
replacement = f'RELEASE_PAYLOAD_URL="${{RELEASE_PAYLOAD_URL:-{payload_url}}}"'
updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
if count != 1:
    raise SystemExit("failed to patch RELEASE_PAYLOAD_URL in hosted installer")
path.write_text(updated)
PY

install -m 0755 "$HOST_INSTALLER_VERSIONED" "$HOST_INSTALLER_LATEST"

cat > "$DIST_DIR/pve-dcv-downloads-index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>PVE DCV Integration Downloads</title>
  <style>
    body { font-family: sans-serif; margin: 2rem auto; max-width: 52rem; line-height: 1.5; padding: 0 1rem; }
    code { background: #f4f4f4; padding: 0.15rem 0.3rem; border-radius: 0.25rem; }
  </style>
</head>
<body>
  <h1>PVE DCV Integration Downloads</h1>
  <p>Host-local thin-client media downloads for this Proxmox server.</p>
  <ul>
    <li><a href="${DOWNLOADS_PATH%/}/pve-thin-client-usb-installer-host-latest.sh">USB installer launcher</a></li>
    <li><a href="${DOWNLOADS_PATH%/}/pve-thin-client-usb-payload-latest.tar.gz">USB payload bundle</a></li>
    <li><a href="${DOWNLOADS_PATH%/}/SHA256SUMS">SHA256SUMS</a></li>
  </ul>
  <p>The hosted USB installer is preconfigured to download its large payload from this same Proxmox host instead of GitHub.</p>
</body>
</html>
EOF

echo "Prepared host-local download artifacts under $DIST_DIR"
echo "Hosted USB installer URL: ${BASE_URL%/}/pve-thin-client-usb-installer-host-latest.sh"
