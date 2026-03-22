#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
EXT_DIR="$ROOT_DIR/extension"
THIN_CLIENT_DIR="$ROOT_DIR/thin-client-assistant"
BEAGLE_OS_DIST_DIR="${BEAGLE_OS_DIST_DIR:-$DIST_DIR/beagle-os}"
VERSION="$(tr -d ' \n\r' < "$ROOT_DIR/VERSION")"
ZIP_NAME="beagle-extension-v${VERSION}.zip"
TARBALL_NAME="beagle-os-v${VERSION}.tar.gz"
TARBALL_LATEST_NAME="beagle-os-latest.tar.gz"
USB_PAYLOAD_NAME="pve-thin-client-usb-payload-v${VERSION}.tar.gz"
USB_PAYLOAD_LATEST_NAME="pve-thin-client-usb-payload-latest.tar.gz"
USB_BOOTSTRAP_NAME="pve-thin-client-usb-bootstrap-v${VERSION}.tar.gz"
USB_BOOTSTRAP_LATEST_NAME="pve-thin-client-usb-bootstrap-latest.tar.gz"
USB_INSTALLER_NAME="pve-thin-client-usb-installer-v${VERSION}.sh"
USB_INSTALLER_LATEST_NAME="pve-thin-client-usb-installer-latest.sh"
CHECKSUM_FILE="SHA256SUMS"
BUILD_BEAGLE_OS="${BUILD_BEAGLE_OS:-0}"

collect_beagle_os_assets() {
  local path
  [[ -d "$BEAGLE_OS_DIST_DIR" ]] || return 0

  while IFS= read -r path; do
    BEAGLE_OS_ASSETS+=("${path#$DIST_DIR/}")
  done < <(
    find "$BEAGLE_OS_DIST_DIR" -maxdepth 1 -type f \
      \( -name '*.qcow2' -o -name '*.raw' -o -name '*.deb' -o -name '*.txt' \) \
      | sort
  )
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
}

require_tool zip
require_tool tar
require_tool sha256sum
require_tool python3

mkdir -p "$DIST_DIR"
BEAGLE_OS_ASSETS=()
rm -f "$DIST_DIR"/pve-thin-client-usb-installer-host-v*.sh
rm -f "$DIST_DIR"/pve-thin-client-usb-installer-vm-*.sh
rm -f \
  "$DIST_DIR/$ZIP_NAME" \
  "$DIST_DIR/$TARBALL_NAME" \
  "$DIST_DIR/$TARBALL_LATEST_NAME" \
  "$DIST_DIR/$USB_PAYLOAD_NAME" \
  "$DIST_DIR/$USB_PAYLOAD_LATEST_NAME" \
  "$DIST_DIR/$USB_BOOTSTRAP_NAME" \
  "$DIST_DIR/$USB_BOOTSTRAP_LATEST_NAME" \
  "$DIST_DIR/$USB_INSTALLER_NAME" \
  "$DIST_DIR/$USB_INSTALLER_LATEST_NAME" \
  "$DIST_DIR/pve-thin-client-usb-installer-host-latest.sh" \
  "$DIST_DIR/beagle-vm-installers.json" \
  "$DIST_DIR/beagle-downloads-index.html" \
  "$DIST_DIR/beagle-downloads-status.json" \
  "$DIST_DIR/$CHECKSUM_FILE"

if [[ ! -f "$DIST_DIR/pve-thin-client-installer/live/filesystem.squashfs" || ! -f "$DIST_DIR/pve-thin-client-installer/live/initrd.img" || ! -f "$DIST_DIR/pve-thin-client-installer/live/vmlinuz" ]]; then
  "$ROOT_DIR/scripts/build-thin-client-installer.sh"
fi

if [[ "$BUILD_BEAGLE_OS" == "1" ]]; then
  "$ROOT_DIR/scripts/build-beagle-os.sh"
fi

collect_beagle_os_assets

EXT_BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$EXT_BUILD_DIR"' EXIT
cp -a "$EXT_DIR/." "$EXT_BUILD_DIR/"
python3 - "$EXT_BUILD_DIR/manifest.json" "$VERSION" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
version = sys.argv[2]
data = json.loads(path.read_text())
data["version"] = version
path.write_text(json.dumps(data, indent=2) + "\n")
PY
(
  cd "$EXT_BUILD_DIR"
  zip -qr "$DIST_DIR/$ZIP_NAME" .
)

(
  cd "$ROOT_DIR"
  tar -czf "$DIST_DIR/$TARBALL_NAME" extension proxmox-ui proxmox-host thin-client-assistant docs scripts README.md LICENSE CHANGELOG.md VERSION
)

install -m 0644 "$DIST_DIR/$TARBALL_NAME" "$DIST_DIR/$TARBALL_LATEST_NAME"

(
  cd "$ROOT_DIR"
  tar -czf "$DIST_DIR/$USB_PAYLOAD_NAME" \
    thin-client-assistant \
    docs \
    scripts \
    README.md \
    LICENSE \
    CHANGELOG.md \
    VERSION \
    dist/pve-thin-client-installer/live
)

install -m 0644 "$DIST_DIR/$USB_PAYLOAD_NAME" "$DIST_DIR/$USB_PAYLOAD_LATEST_NAME"
install -m 0644 "$DIST_DIR/$USB_PAYLOAD_NAME" "$DIST_DIR/$USB_BOOTSTRAP_NAME"
install -m 0644 "$DIST_DIR/$USB_PAYLOAD_NAME" "$DIST_DIR/$USB_BOOTSTRAP_LATEST_NAME"

install -m 0755 "$ROOT_DIR/thin-client-assistant/usb/pve-thin-client-usb-installer.sh" "$DIST_DIR/$USB_INSTALLER_NAME"
install -m 0755 "$ROOT_DIR/thin-client-assistant/usb/pve-thin-client-usb-installer.sh" "$DIST_DIR/$USB_INSTALLER_LATEST_NAME"

(
  cd "$DIST_DIR"
  sha256sum \
    "$ZIP_NAME" \
    "$TARBALL_NAME" \
    "$TARBALL_LATEST_NAME" \
    "$USB_PAYLOAD_NAME" \
    "$USB_PAYLOAD_LATEST_NAME" \
    "$USB_BOOTSTRAP_NAME" \
    "$USB_BOOTSTRAP_LATEST_NAME" \
    "$USB_INSTALLER_NAME" \
    "$USB_INSTALLER_LATEST_NAME" \
    "${BEAGLE_OS_ASSETS[@]}" > "$CHECKSUM_FILE"
)

echo "Created: $DIST_DIR/$ZIP_NAME"
echo "Created: $DIST_DIR/$TARBALL_NAME"
echo "Created: $DIST_DIR/$TARBALL_LATEST_NAME"
echo "Created: $DIST_DIR/$USB_PAYLOAD_NAME"
echo "Created: $DIST_DIR/$USB_PAYLOAD_LATEST_NAME"
echo "Created: $DIST_DIR/$USB_BOOTSTRAP_NAME"
echo "Created: $DIST_DIR/$USB_BOOTSTRAP_LATEST_NAME"
echo "Created: $DIST_DIR/$USB_INSTALLER_NAME"
echo "Created: $DIST_DIR/$USB_INSTALLER_LATEST_NAME"
echo "Created: $DIST_DIR/$CHECKSUM_FILE"
for asset in "${BEAGLE_OS_ASSETS[@]}"; do
  echo "Included: $DIST_DIR/$asset"
done
