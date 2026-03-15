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
rm -f "$DIST_DIR/$ZIP_NAME" "$DIST_DIR/$TARBALL_NAME" "$DIST_DIR/$TARBALL_LATEST_NAME" "$DIST_DIR/$USB_INSTALLER_NAME" "$DIST_DIR/$USB_INSTALLER_LATEST_NAME" "$DIST_DIR/$CHECKSUM_FILE"

(
  cd "$EXT_DIR"
  zip -qr "$DIST_DIR/$ZIP_NAME" .
)

(
  cd "$ROOT_DIR"
  tar -czf "$DIST_DIR/$TARBALL_NAME" extension proxmox-ui thin-client-assistant docs scripts README.md LICENSE CHANGELOG.md VERSION
)

install -m 0644 "$DIST_DIR/$TARBALL_NAME" "$DIST_DIR/$TARBALL_LATEST_NAME"

install -m 0755 "$ROOT_DIR/thin-client-assistant/usb/pve-thin-client-usb-installer.sh" "$DIST_DIR/$USB_INSTALLER_NAME"
install -m 0755 "$ROOT_DIR/thin-client-assistant/usb/pve-thin-client-usb-installer.sh" "$DIST_DIR/$USB_INSTALLER_LATEST_NAME"

(
  cd "$DIST_DIR"
  sha256sum "$ZIP_NAME" "$TARBALL_NAME" "$TARBALL_LATEST_NAME" "$USB_INSTALLER_NAME" "$USB_INSTALLER_LATEST_NAME" > "$CHECKSUM_FILE"
)

echo "Created: $DIST_DIR/$ZIP_NAME"
echo "Created: $DIST_DIR/$TARBALL_NAME"
echo "Created: $DIST_DIR/$TARBALL_LATEST_NAME"
echo "Created: $DIST_DIR/$USB_INSTALLER_NAME"
echo "Created: $DIST_DIR/$USB_INSTALLER_LATEST_NAME"
echo "Created: $DIST_DIR/$CHECKSUM_FILE"
