#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/pve-dcv-integration}"
VERSION="$(tr -d ' \n\r' < "$ROOT_DIR/VERSION")"
SERVER_NAME="${PVE_DCV_PROXY_SERVER_NAME:-$(hostname -f 2>/dev/null || hostname)}"
LISTEN_PORT="${PVE_DCV_PROXY_LISTEN_PORT:-8443}"
DOWNLOADS_PATH="${PVE_DCV_DOWNLOADS_PATH:-/pve-dcv-downloads}"
DOWNLOADS_BASE_URL="${PVE_DCV_DOWNLOADS_BASE_URL:-https://${SERVER_NAME}:${LISTEN_PORT}${DOWNLOADS_PATH}}"
DEFAULT_USB_INSTALLER_URL="https://__HOST__:${LISTEN_PORT}${DOWNLOADS_PATH%/}/pve-thin-client-usb-installer-vm-__VMID__.sh"
DEFAULT_USB_INSTALLER_URL="${DEFAULT_USB_INSTALLER_URL/__HOST__/\{host\}}"
DEFAULT_USB_INSTALLER_URL="${DEFAULT_USB_INSTALLER_URL/__VMID__/\{vmid\}}"
USB_INSTALLER_URL="${PVE_DCV_USB_INSTALLER_URL:-$DEFAULT_USB_INSTALLER_URL}"
CONFIG_DIR="${PVE_DCV_CONFIG_DIR:-/etc/pve-dcv-integration}"
GITHUB_REPO="${GITHUB_REPO:-meinzeug/pve-dcv-integration}"

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
      PVE_DCV_CONFIG_DIR="$CONFIG_DIR" \
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

have_packaged_assets() {
  [[ -f "$INSTALL_DIR/dist/pve-thin-client-usb-installer-v${VERSION}.sh" ]] &&
    [[ -f "$INSTALL_DIR/dist/pve-thin-client-usb-installer-latest.sh" ]] &&
    [[ -f "$INSTALL_DIR/dist/pve-thin-client-usb-payload-v${VERSION}.tar.gz" ]] &&
    [[ -f "$INSTALL_DIR/dist/pve-thin-client-usb-payload-latest.tar.gz" ]]
}

download_release_assets() {
  local base_url="$1"
  local dist_dir="$INSTALL_DIR/dist"

  command -v curl >/dev/null 2>&1 || return 1

  install -d -m 0755 "$dist_dir"

  curl -fsSLo "$dist_dir/pve-thin-client-usb-installer-v${VERSION}.sh" \
    "$base_url/pve-thin-client-usb-installer-v${VERSION}.sh" &&
    install -m 0755 "$dist_dir/pve-thin-client-usb-installer-v${VERSION}.sh" "$dist_dir/pve-thin-client-usb-installer-latest.sh" &&
    curl -fsSLo "$dist_dir/pve-thin-client-usb-payload-v${VERSION}.tar.gz" \
      "$base_url/pve-thin-client-usb-payload-v${VERSION}.tar.gz" &&
    install -m 0644 "$dist_dir/pve-thin-client-usb-payload-v${VERSION}.tar.gz" "$dist_dir/pve-thin-client-usb-payload-latest.tar.gz" &&
    curl -fsSLo "$dist_dir/SHA256SUMS" "$base_url/SHA256SUMS"
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

write_host_env_file() {
  install -d -m 0755 "$CONFIG_DIR"
  cat > "$CONFIG_DIR/host.env" <<EOF
INSTALL_DIR="$INSTALL_DIR"
PVE_DCV_PROXY_SERVER_NAME="$SERVER_NAME"
PVE_DCV_PROXY_LISTEN_PORT="$LISTEN_PORT"
PVE_DCV_DOWNLOADS_PATH="$DOWNLOADS_PATH"
PVE_DCV_DOWNLOADS_BASE_URL="$DOWNLOADS_BASE_URL"
PVE_DCV_USB_INSTALLER_URL="$USB_INSTALLER_URL"
PVE_DCV_CONFIG_DIR="$CONFIG_DIR"
EOF
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
  "$ROOT_DIR/" "$INSTALL_DIR/"
chown -R root:root "$INSTALL_DIR"
find "$INSTALL_DIR" -type d -exec chmod 0755 {} +

if ! have_packaged_assets; then
  RELEASE_BASE_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}"
  download_release_assets "$RELEASE_BASE_URL" || "$INSTALL_DIR/scripts/package.sh"
fi
"$INSTALL_DIR/scripts/prepare-host-downloads.sh"
write_host_env_file
"$INSTALL_DIR/scripts/install-proxmox-host-services.sh"

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
