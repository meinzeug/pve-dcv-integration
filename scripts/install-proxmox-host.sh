#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/pve-dcv-integration}"
SERVER_NAME="${PVE_DCV_PROXY_SERVER_NAME:-$(hostname -f 2>/dev/null || hostname)}"
LISTEN_PORT="${PVE_DCV_PROXY_LISTEN_PORT:-8443}"
DOWNLOADS_PATH="${PVE_DCV_DOWNLOADS_PATH:-/pve-dcv-downloads}"
DOWNLOADS_BASE_URL="${PVE_DCV_DOWNLOADS_BASE_URL:-https://${SERVER_NAME}:${LISTEN_PORT}${DOWNLOADS_PATH}}"
USB_INSTALLER_URL="${PVE_DCV_USB_INSTALLER_URL:-${DOWNLOADS_BASE_URL%/}/pve-thin-client-usb-installer-host-latest.sh}"

ensure_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    exec sudo \
      INSTALL_DIR="$INSTALL_DIR" \
      PVE_DCV_PROXY_SERVER_NAME="$SERVER_NAME" \
      PVE_DCV_PROXY_LISTEN_PORT="$LISTEN_PORT" \
      PVE_DCV_DOWNLOADS_PATH="$DOWNLOADS_PATH" \
      PVE_DCV_DOWNLOADS_BASE_URL="$DOWNLOADS_BASE_URL" \
      PVE_DCV_USB_INSTALLER_URL="$USB_INSTALLER_URL" \
      "$0" "$@"
  fi

  echo "This installer must run as root or use sudo." >&2
  exit 1
}

ensure_dependencies() {
  if command -v rsync >/dev/null 2>&1; then
    return 0
  fi

  apt_update_with_proxmox_fallback
  DEBIAN_FRONTEND=noninteractive apt-get install -y rsync
}

disable_proxmox_enterprise_repo() {
  local found=0
  local file

  while IFS= read -r file; do
    grep -q 'enterprise.proxmox.com' "$file" || continue
    cp "$file" "$file.pve-dcv-backup"
    awk '!/enterprise\.proxmox\.com/' "$file.pve-dcv-backup" > "$file"
    found=1
  done < <(find /etc/apt -maxdepth 2 -type f \( -name '*.list' -o -name '*.sources' \) 2>/dev/null)

  return $(( ! found ))
}

restore_proxmox_enterprise_repo() {
  local backup original

  while IFS= read -r backup; do
    original="${backup%.pve-dcv-backup}"
    mv "$backup" "$original"
  done < <(find /etc/apt -maxdepth 2 -type f -name '*.pve-dcv-backup' 2>/dev/null)
}

apt_update_with_proxmox_fallback() {
  if apt-get update; then
    return 0
  fi

  if ! disable_proxmox_enterprise_repo; then
    echo "apt-get update failed and no Proxmox enterprise repository fallback was available." >&2
    exit 1
  fi

  if ! apt-get update; then
    restore_proxmox_enterprise_repo
    exit 1
  fi
  restore_proxmox_enterprise_repo
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
  --exclude '.build' \
  --exclude 'dist' \
  "$ROOT_DIR/" "$INSTALL_DIR/"

"$INSTALL_DIR/scripts/package.sh"
"$INSTALL_DIR/scripts/prepare-host-downloads.sh"

if [[ -d /usr/share/pve-manager/js ]]; then
  PVE_DCV_PROXY_SERVER_NAME="$SERVER_NAME" \
  PVE_DCV_PROXY_LISTEN_PORT="$LISTEN_PORT" \
  PVE_DCV_DOWNLOADS_PATH="$DOWNLOADS_PATH" \
  PVE_DCV_USB_INSTALLER_URL="$USB_INSTALLER_URL" \
  "$INSTALL_DIR/scripts/install-proxmox-ui-integration.sh"

  PVE_DCV_PROXY_SERVER_NAME="$SERVER_NAME" \
  PVE_DCV_PROXY_LISTEN_PORT="$LISTEN_PORT" \
  PVE_DCV_DOWNLOADS_PATH="$DOWNLOADS_PATH" \
  PVE_DCV_DOWNLOADS_BASE_URL="$DOWNLOADS_BASE_URL" \
  "$INSTALL_DIR/scripts/install-proxmox-dcv-proxy.sh"
fi

echo "Installed project assets to $INSTALL_DIR"
