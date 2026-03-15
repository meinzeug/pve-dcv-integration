#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
USB_LABEL="${USB_LABEL:-PVE-THIN-CLIENT}"
TARGET_DEVICE=""
FORCE="0"

usage() {
  cat <<EOF
Usage: $0 --device /dev/sdX [--force]

This script prepares a USB installer stick containing the thin-client assistant,
documentation and a start menu for local installation on a target Linux system.
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script as root." >&2
    exit 1
  fi
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --device) TARGET_DEVICE="$2"; shift 2 ;;
      --force) FORCE="1"; shift ;;
      -h|--help) usage; exit 0 ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

confirm_device() {
  if [[ -z "$TARGET_DEVICE" || ! -b "$TARGET_DEVICE" ]]; then
    echo "Block device not found: $TARGET_DEVICE" >&2
    lsblk -d -o NAME,SIZE,MODEL,TRAN
    exit 1
  fi

  echo "Selected USB target: $TARGET_DEVICE"
  lsblk "$TARGET_DEVICE"
  if [[ "$FORCE" == "1" ]]; then
    return 0
  fi

  read -r -p "This will erase all data on $TARGET_DEVICE. Continue? [y/N]: " answer
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
}

prepare_partition() {
  local partition
  partition="${TARGET_DEVICE}1"

  wipefs -a "$TARGET_DEVICE"
  parted -s "$TARGET_DEVICE" mklabel gpt
  parted -s "$TARGET_DEVICE" mkpart primary ext4 1MiB 100%
  udevadm settle
  mkfs.ext4 -F -L "$USB_LABEL" "$partition"
  echo "$partition"
}

write_payload() {
  local partition="$1"
  local mount_dir
  mount_dir="$(mktemp -d)"
  mount "$partition" "$mount_dir"

  install -d "$mount_dir/pve-dcv-integration"
  cp -a \
    "$PAYLOAD_ROOT/thin-client-assistant" \
    "$PAYLOAD_ROOT/docs" \
    "$PAYLOAD_ROOT/README.md" \
    "$PAYLOAD_ROOT/LICENSE" \
    "$PAYLOAD_ROOT/CHANGELOG.md" \
    "$mount_dir/pve-dcv-integration/"

  cp "$PAYLOAD_ROOT/thin-client-assistant/usb/start-installer-menu.sh" "$mount_dir/start-installer-menu.sh"
  chmod 0755 "$mount_dir/start-installer-menu.sh"

  cat > "$mount_dir/README-USB.txt" <<EOF
PVE Thin Client USB Installer

1. Boot or log into a Linux system.
2. Mount this USB stick.
3. Run ./start-installer-menu.sh as root.
4. Follow the SPICE / NOVNC / DCV setup menu.
EOF

  sync
  umount "$mount_dir"
  rmdir "$mount_dir"
}

require_root
require_tool lsblk
require_tool parted
require_tool mkfs.ext4
require_tool wipefs
require_tool mount
require_tool umount
parse_args "$@"
confirm_device
partition="$(prepare_partition)"
write_payload "$partition"
echo "USB installer media prepared on $TARGET_DEVICE"
