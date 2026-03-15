#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/pve-dcv-integration}"

ensure_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    exec sudo INSTALL_DIR="$INSTALL_DIR" "$0" "$@"
  fi

  echo "This installer must run as root or use sudo." >&2
  exit 1
}

ensure_dependencies() {
  if command -v rsync >/dev/null 2>&1; then
    return 0
  fi

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y rsync
}

ensure_root "$@"
ensure_dependencies

case "$INSTALL_DIR/" in
  "$ROOT_DIR"/*)
    echo "INSTALL_DIR must not be inside the source tree: $INSTALL_DIR" >&2
    exit 1
    ;;
esac

install -d -m 0755 "$INSTALL_DIR"
rsync -a --delete \
  --exclude '.git' \
  --exclude 'dist' \
  "$ROOT_DIR/" "$INSTALL_DIR/"

"$INSTALL_DIR/scripts/package.sh"

if [[ -d /usr/share/pve-manager/js ]]; then
  "$INSTALL_DIR/scripts/install-proxmox-ui-integration.sh"
  "$INSTALL_DIR/scripts/install-proxmox-dcv-proxy.sh"
fi

echo "Installed project assets to $INSTALL_DIR"
