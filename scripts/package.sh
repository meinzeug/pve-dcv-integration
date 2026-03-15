#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
EXT_DIR="$ROOT_DIR/extension"
THIN_CLIENT_DIR="$ROOT_DIR/thin-client-assistant"
VERSION="$(tr -d ' \n\r' < "$ROOT_DIR/VERSION")"
ZIP_NAME="pve-dcv-integration-extension-v${VERSION}.zip"
TARBALL_NAME="pve-dcv-thin-client-assistant-v${VERSION}.tar.gz"
CHECKSUM_FILE="SHA256SUMS"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/$ZIP_NAME" "$DIST_DIR/$TARBALL_NAME" "$DIST_DIR/$CHECKSUM_FILE"

(
  cd "$EXT_DIR"
  zip -qr "$DIST_DIR/$ZIP_NAME" .
)

(
  cd "$ROOT_DIR"
  tar -czf "$DIST_DIR/$TARBALL_NAME" thin-client-assistant docs README.md LICENSE CHANGELOG.md VERSION
)

(
  cd "$DIST_DIR"
  sha256sum "$ZIP_NAME" "$TARBALL_NAME" > "$CHECKSUM_FILE"
)

echo "Created: $DIST_DIR/$ZIP_NAME"
echo "Created: $DIST_DIR/$TARBALL_NAME"
echo "Created: $DIST_DIR/$CHECKSUM_FILE"
