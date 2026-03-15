#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist/pve-thin-client-installer"
ASSET_DIR="$DIST_DIR/live"
USB_LABEL="${USB_LABEL:-PVETHIN}"
TARGET_DEVICE="${TARGET_DEVICE:-}"
ASSUME_YES="0"
LIST_DEVICES="0"
RELEASE_PAYLOAD_URL="${RELEASE_PAYLOAD_URL:-https://github.com/meinzeug/pve-dcv-integration/releases/latest/download/pve-thin-client-usb-payload-latest.tar.gz}"
BOOTSTRAP_DIR=""

usage() {
  cat <<EOF
Usage: $0 [--device /dev/sdX] [--list-devices] [--yes]

Writes a bootable PVE Thin Client installer USB stick.
The script can be started as a normal user and escalates to sudo only for the write phase.
EOF
}

cleanup() {
  if [[ -n "$BOOTSTRAP_DIR" && -d "$BOOTSTRAP_DIR" ]]; then
    rm -rf "$BOOTSTRAP_DIR"
  fi
}
trap cleanup EXIT

rerun_as_root() {
  local sudo_args=()
  if [[ "${EUID}" -eq 0 ]]; then
    return 0
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required for USB write operations." >&2
    exit 1
  fi

  [[ -n "$TARGET_DEVICE" ]] && sudo_args+=(--device "$TARGET_DEVICE")
  [[ "$LIST_DEVICES" == "1" ]] && sudo_args+=(--list-devices)
  [[ "$ASSUME_YES" == "1" ]] && sudo_args+=(--yes)
  exec sudo \
    USB_LABEL="$USB_LABEL" \
    RELEASE_PAYLOAD_URL="$RELEASE_PAYLOAD_URL" \
    PVE_DCV_BOOTSTRAP_BASE="${PVE_DCV_BOOTSTRAP_BASE:-}" \
    "$0" "${sudo_args[@]}"
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
}

allocate_bootstrap_dir() {
  local bases=()
  local base=""
  local candidate=""

  [[ -n "${PVE_DCV_BOOTSTRAP_BASE:-}" ]] && bases+=("${PVE_DCV_BOOTSTRAP_BASE}")
  [[ -n "${TMPDIR:-}" ]] && bases+=("${TMPDIR}")
  bases+=("/var/tmp" "/tmp")

  for base in "${bases[@]}"; do
    [[ -d "$base" && -w "$base" ]] || continue
    candidate="$(mktemp -d "$base/pve-dcv-usb.XXXXXX" 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  mktemp -d
}

bootstrap_repo_root() {
  local tarball extracted
  if [[ -d "$REPO_ROOT/thin-client-assistant" && -x "$REPO_ROOT/scripts/build-thin-client-installer.sh" ]]; then
    return 0
  fi

  require_tool curl
  require_tool tar

  BOOTSTRAP_DIR="$(allocate_bootstrap_dir)"
  tarball="$BOOTSTRAP_DIR/payload.tar.gz"
  extracted="$BOOTSTRAP_DIR/extracted"
  mkdir -p "$extracted"
  chmod 0755 "$BOOTSTRAP_DIR" "$extracted"

  echo "Downloading thin-client payload bundle from GitHub release..."
  curl -fsSL "$RELEASE_PAYLOAD_URL" -o "$tarball"
  tar -xzf "$tarball" -C "$extracted"
  REPO_ROOT="$extracted"
  DIST_DIR="$REPO_ROOT/dist/pve-thin-client-installer"
  ASSET_DIR="$DIST_DIR/live"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --device)
        TARGET_DEVICE="$2"
        shift 2
        ;;
      --list-devices)
        LIST_DEVICES="1"
        shift
        ;;
      --yes|--force)
        ASSUME_YES="1"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

list_candidate_devices() {
  lsblk -dn -P -o NAME,SIZE,MODEL,TYPE,RM,TRAN
}

print_devices() {
  local name size model type rm transport

  printf '%-12s %-8s %-32s %-4s %-3s %s\n' "DEVICE" "SIZE" "MODEL" "RM" "USB" "TRANSPORT"
  while IFS= read -r line; do
    eval "$line"
    [[ "${TYPE:-}" == "disk" ]] || continue
    printf '%-12s %-8s %-32s %-4s %-3s %s\n' \
      "/dev/${NAME}" \
      "${SIZE:-unknown}" \
      "${MODEL:-disk}" \
      "${RM:-0}" \
      "$([[ "${TRAN:-}" == "usb" ]] && printf 'yes' || printf 'no')" \
      "${TRAN:-unknown}"
  done <<EOF
$(list_candidate_devices)
EOF
}

count_usb_candidates() {
  local count=0
  local name size model type rm transport

  while IFS= read -r line; do
    eval "$line"
    [[ "${TYPE:-}" == "disk" ]] || continue
    if [[ "${RM:-0}" == "1" || "${TRAN:-}" == "usb" ]]; then
      count=$((count + 1))
    fi
  done <<EOF
$(list_candidate_devices)
EOF
  printf '%s\n' "$count"
}

choose_device() {
  local options=()
  local device tty_path usb_candidates name size model type rm transport answer index

  tty_path="/dev/tty"
  if [[ ! -r "$tty_path" || ! -w "$tty_path" ]]; then
    tty_path=""
  fi

  while IFS= read -r line; do
    eval "$line"
    [[ "${TYPE:-}" == "disk" ]] || continue
    device="/dev/${NAME}"
    [[ "$device" == /dev/loop* || "$device" == /dev/sr* || "$device" == /dev/ram* || "$device" == /dev/zram* ]] && continue
    options+=("$device" "${MODEL:-disk} ${SIZE:-unknown} usb=${TRAN:-}")
  done <<EOF
$(list_candidate_devices)
EOF

  if (( ${#options[@]} == 0 )); then
    echo "No writable block device found." >&2
    exit 1
  fi

  usb_candidates="$(count_usb_candidates)"
  if [[ "$usb_candidates" == "1" ]]; then
    while IFS= read -r line; do
      eval "$line"
      [[ "${TYPE:-}" == "disk" ]] || continue
      device="/dev/${NAME}"
      [[ "$device" == /dev/loop* || "$device" == /dev/sr* || "$device" == /dev/ram* || "$device" == /dev/zram* ]] && continue
      if [[ "${RM:-0}" == "1" || "${TRAN:-}" == "usb" ]]; then
        printf '%s\n' "$device"
        return 0
      fi
    done <<EOF
$(list_candidate_devices)
EOF
  fi

  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "PVE Thin Client USB Writer" --menu \
      "Select the USB target device" 20 90 10 \
      "${options[@]}" 3>&1 1>&2 2>&3
    return 0
  fi

  if [[ -z "$tty_path" ]]; then
    echo "Interactive device selection requires a TTY. Re-run with --device /dev/sdX." >&2
    exit 1
  fi

  {
    echo "Available target devices:"
    print_devices
    echo
  } >"$tty_path"

  index=1
  while (( index <= ${#options[@]} / 2 )); do
    printf '%s) %s %s\n' "$index" "${options[$(( (index - 1) * 2 ))]}" "${options[$(( (index - 1) * 2 + 1 ))]}" >"$tty_path"
    index=$((index + 1))
  done
  printf 'Choice: ' >"$tty_path"
  read -r answer <"$tty_path"
  [[ "$answer" =~ ^[0-9]+$ ]] || {
    echo "Invalid selection: $answer" >&2
    exit 1
  }
  (( answer >= 1 && answer <= ${#options[@]} / 2 )) || {
    echo "Selection out of range: $answer" >&2
    exit 1
  }
  printf '%s\n' "${options[$(( (answer - 1) * 2 ))]}"
}

partition_suffix() {
  local device="$1"
  local number="$2"
  if [[ "$device" =~ [0-9]$ ]]; then
    printf '%sp%s\n' "$device" "$number"
  else
    printf '%s%s\n' "$device" "$number"
  fi
}

confirm_device() {
  [[ -b "$TARGET_DEVICE" ]] || {
    echo "Block device not found: $TARGET_DEVICE" >&2
    print_devices >&2
    exit 1
  }

  lsblk "$TARGET_DEVICE"
  if [[ "$ASSUME_YES" == "1" ]]; then
    return 0
  fi

  read -r -p "Erase and re-create $TARGET_DEVICE as PVE Thin Client USB? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

release_target_device() {
  local mountpoint=""
  local part=""
  local parts=()

  mapfile -t parts < <(lsblk -nrpo NAME "$TARGET_DEVICE" | tail -n +2)
  for part in "${parts[@]}"; do
    while IFS= read -r mountpoint; do
      [[ -n "$mountpoint" ]] || continue
      umount "$mountpoint"
    done < <(findmnt -rn -S "$part" -o TARGET 2>/dev/null || true)
  done

  partprobe "$TARGET_DEVICE" || true
  udevadm settle || true
}

ensure_live_assets() {
  if [[ -f "$ASSET_DIR/filesystem.squashfs" && -f "$ASSET_DIR/vmlinuz" && -f "$ASSET_DIR/initrd.img" ]]; then
    return 0
  fi

  "$REPO_ROOT/scripts/build-thin-client-installer.sh"
}

install_dependencies() {
  local missing=()
  local tool

  for tool in wipefs parted mkfs.vfat grub-install rsync partprobe udevadm; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if (( ${#missing[@]} == 0 )); then
    return 0
  fi

  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    dosfstools \
    e2fsprogs \
    parted \
    grub-pc-bin \
    grub-efi-amd64-bin \
    efibootmgr \
    rsync
}

write_usb() {
  local mount_dir bios_partition usb_partition
  mount_dir="$(mktemp -d)"
  trap 'umount "$mount_dir" >/dev/null 2>&1 || true; rmdir "$mount_dir" >/dev/null 2>&1 || true' RETURN

  release_target_device
  wipefs -a "$TARGET_DEVICE"
  parted -s "$TARGET_DEVICE" mklabel gpt
  parted -s "$TARGET_DEVICE" mkpart BIOSBOOT 1MiB 3MiB
  parted -s "$TARGET_DEVICE" set 1 bios_grub on
  parted -s "$TARGET_DEVICE" mkpart ESP fat32 3MiB 100%
  parted -s "$TARGET_DEVICE" set 2 esp on
  parted -s "$TARGET_DEVICE" set 2 boot on
  partprobe "$TARGET_DEVICE"
  udevadm settle

  bios_partition="$(partition_suffix "$TARGET_DEVICE" 1)"
  usb_partition="$(partition_suffix "$TARGET_DEVICE" 2)"
  [[ -b "$bios_partition" ]] || {
    echo "BIOS boot partition was not created on $TARGET_DEVICE" >&2
    exit 1
  }
  mkfs.vfat -F 32 -n "$USB_LABEL" "$usb_partition"
  mount "$usb_partition" "$mount_dir"

  install -d -m 0755 \
    "$mount_dir/boot/grub" \
    "$mount_dir/pve-thin-client/live" \
    "$mount_dir/pve-dcv-integration"

  install -m 0644 "$ASSET_DIR/vmlinuz" "$mount_dir/pve-thin-client/live/vmlinuz"
  install -m 0644 "$ASSET_DIR/initrd.img" "$mount_dir/pve-thin-client/live/initrd.img"
  install -m 0644 "$ASSET_DIR/filesystem.squashfs" "$mount_dir/pve-thin-client/live/filesystem.squashfs"
  install -m 0644 "$ASSET_DIR/SHA256SUMS" "$mount_dir/pve-thin-client/live/SHA256SUMS"

  rsync -rlt --delete \
    --no-owner \
    --no-group \
    --no-perms \
    --exclude 'live-build' \
    "$REPO_ROOT/thin-client-assistant/" "$mount_dir/pve-dcv-integration/thin-client-assistant/"
  rsync -rlt \
    --no-owner \
    --no-group \
    --no-perms \
    "$REPO_ROOT/docs/" "$mount_dir/pve-dcv-integration/docs/"
  install -m 0644 "$REPO_ROOT/README.md" "$mount_dir/pve-dcv-integration/README.md"
  install -m 0644 "$REPO_ROOT/LICENSE" "$mount_dir/pve-dcv-integration/LICENSE"
  install -m 0644 "$REPO_ROOT/CHANGELOG.md" "$mount_dir/pve-dcv-integration/CHANGELOG.md"
  install -m 0755 "$REPO_ROOT/thin-client-assistant/usb/start-installer-menu.sh" "$mount_dir/start-installer-menu.sh"

  cat > "$mount_dir/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=5

menuentry 'PVE Thin Client Installer' {
  linux /pve-thin-client/live/vmlinuz boot=live components username=thinclient hostname=pve-thin-client live-media-path=/pve-thin-client/live ip=dhcp quiet loglevel=3 systemd.show_status=0 vt.global_cursor_default=0 splash pve_thin_client.mode=installer
  initrd /pve-thin-client/live/initrd.img
}

menuentry 'PVE Thin Client Installer (compatibility mode)' {
  linux /pve-thin-client/live/vmlinuz boot=live components username=thinclient hostname=pve-thin-client live-media-path=/pve-thin-client/live ip=dhcp quiet loglevel=3 systemd.show_status=0 vt.global_cursor_default=0 splash nomodeset pve_thin_client.mode=installer
  initrd /pve-thin-client/live/initrd.img
}

menuentry 'Boot from local disk' {
  exit
}
EOF

  grub-install --target=i386-pc --boot-directory="$mount_dir/boot" "$TARGET_DEVICE"
  grub-install \
    --target=x86_64-efi \
    --efi-directory="$mount_dir" \
    --boot-directory="$mount_dir/boot" \
    --removable \
    --no-nvram

  sync
}

parse_args "$@"
if [[ "$LIST_DEVICES" == "1" ]]; then
  print_devices
  exit 0
fi
if [[ -z "$TARGET_DEVICE" ]]; then
  TARGET_DEVICE="$(choose_device)"
fi
rerun_as_root
require_tool lsblk
confirm_device
bootstrap_repo_root
install_dependencies
ensure_live_assets
write_usb
echo "USB installer media prepared on $TARGET_DEVICE"
