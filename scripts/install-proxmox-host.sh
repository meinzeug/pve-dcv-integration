#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/pve-dcv-integration}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "This installer must run as root." >&2
  exit 1
fi

install -d -m 0755 "$INSTALL_DIR"
rsync -a --delete \
  --exclude '.git' \
  --exclude 'dist' \
  "$ROOT_DIR/" "$INSTALL_DIR/"

"$INSTALL_DIR/scripts/package.sh"

echo "Installed project assets to $INSTALL_DIR"
