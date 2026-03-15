#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
EXT_DIR="$ROOT_DIR/extension"
THIN_CLIENT_DIR="$ROOT_DIR/thin-client-assistant"
VERSION="$(tr -d ' \n\r' < "$ROOT_DIR/VERSION")"
ZIP_NAME="pve-dcv-integration-extension-v${VERSION}.zip"
TARBALL_NAME="pve-dcv-thin-client-assistant-v${VERSION}.tar.gz"
TARBALL_LATEST_NAME="pve-dcv-thin-client-assistant-latest.tar.gz"
USB_PAYLOAD_NAME="pve-thin-client-usb-payload-v${VERSION}.tar.gz"
USB_PAYLOAD_LATEST_NAME="pve-thin-client-usb-payload-latest.tar.gz"
USB_INSTALLER_NAME="pve-thin-client-usb-installer-v${VERSION}.sh"
USB_INSTALLER_LATEST_NAME="pve-thin-client-usb-installer-latest.sh"
CHECKSUM_FILE="SHA256SUMS"

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

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR"/pve-thin-client-usb-installer-host-v*.sh
rm -f \
  "$DIST_DIR/$ZIP_NAME" \
  "$DIST_DIR/$TARBALL_NAME" \
  "$DIST_DIR/$TARBALL_LATEST_NAME" \
  "$DIST_DIR/$USB_PAYLOAD_NAME" \
  "$DIST_DIR/$USB_PAYLOAD_LATEST_NAME" \
  "$DIST_DIR/$USB_INSTALLER_NAME" \
  "$DIST_DIR/$USB_INSTALLER_LATEST_NAME" \
  "$DIST_DIR/pve-thin-client-usb-installer-host-latest.sh" \
  "$DIST_DIR/pve-dcv-downloads-index.html" \
  "$DIST_DIR/pve-dcv-downloads-status.json" \
  "$DIST_DIR/$CHECKSUM_FILE"

if [[ ! -f "$DIST_DIR/pve-thin-client-installer/live/filesystem.squashfs" || ! -f "$DIST_DIR/pve-thin-client-installer/live/initrd.img" || ! -f "$DIST_DIR/pve-thin-client-installer/live/vmlinuz" ]]; then
  "$ROOT_DIR/scripts/build-thin-client-installer.sh"
fi

(
  cd "$EXT_DIR"
  zip -qr "$DIST_DIR/$ZIP_NAME" .
)

(
  cd "$ROOT_DIR"
  tar -czf "$DIST_DIR/$TARBALL_NAME" extension proxmox-ui proxmox-host thin-client-assistant docs scripts README.md LICENSE CHANGELOG.md VERSION
)

install -m 0644 "$DIST_DIR/$TARBALL_NAME" "$DIST_DIR/$TARBALL_LATEST_NAME"

(
  cd "$ROOT_DIR"
  tar -czf "$DIST_DIR/$USB_PAYLOAD_NAME" thin-client-assistant docs scripts README.md LICENSE CHANGELOG.md VERSION dist/pve-thin-client-installer
)

install -m 0644 "$DIST_DIR/$USB_PAYLOAD_NAME" "$DIST_DIR/$USB_PAYLOAD_LATEST_NAME"

install -m 0755 "$ROOT_DIR/thin-client-assistant/usb/pve-thin-client-usb-installer.sh" "$DIST_DIR/$USB_INSTALLER_NAME"
install -m 0755 "$ROOT_DIR/thin-client-assistant/usb/pve-thin-client-usb-installer.sh" "$DIST_DIR/$USB_INSTALLER_LATEST_NAME"

(
  cd "$DIST_DIR"
  sha256sum "$ZIP_NAME" "$TARBALL_NAME" "$TARBALL_LATEST_NAME" "$USB_PAYLOAD_NAME" "$USB_PAYLOAD_LATEST_NAME" "$USB_INSTALLER_NAME" "$USB_INSTALLER_LATEST_NAME" > "$CHECKSUM_FILE"
)

echo "Created: $DIST_DIR/$ZIP_NAME"
echo "Created: $DIST_DIR/$TARBALL_NAME"
echo "Created: $DIST_DIR/$TARBALL_LATEST_NAME"
echo "Created: $DIST_DIR/$USB_PAYLOAD_NAME"
echo "Created: $DIST_DIR/$USB_PAYLOAD_LATEST_NAME"
echo "Created: $DIST_DIR/$USB_INSTALLER_NAME"
echo "Created: $DIST_DIR/$USB_INSTALLER_LATEST_NAME"
echo "Created: $DIST_DIR/$CHECKSUM_FILE"
