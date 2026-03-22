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
LIST_JSON="0"
DRY_RUN="0"
REQUIRE_CHECKSUMS="0"
ALLOW_NON_USB_DEVICE="0"
ALLOW_SYSTEM_DISK="0"
RELEASE_PAYLOAD_URL="${RELEASE_PAYLOAD_URL:-}"
INSTALL_PAYLOAD_URL="${INSTALL_PAYLOAD_URL:-${RELEASE_PAYLOAD_URL:-}}"
RELEASE_BOOTSTRAP_URL="${RELEASE_BOOTSTRAP_URL:-${RELEASE_PAYLOAD_URL:-}}"
BOOTSTRAP_CACHE_DIR="${PVE_DCV_BOOTSTRAP_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pve-dcv-usb}"
BOOTSTRAP_DIR=""
BOOTSTRAPPED_STANDALONE="0"
MIN_DEVICE_BYTES="${MIN_DEVICE_BYTES:-4294967296}"
PVE_THIN_CLIENT_PRESET_NAME="${PVE_THIN_CLIENT_PRESET_NAME:-}"
PVE_THIN_CLIENT_PRESET_B64="${PVE_THIN_CLIENT_PRESET_B64:-}"
GRUB_BACKGROUND_SRC="$REPO_ROOT/thin-client-assistant/usb/assets/grub-background.jpg"

project_version_from_root() {
  if [[ -f "$REPO_ROOT/VERSION" ]]; then
    tr -d ' \n\r' < "$REPO_ROOT/VERSION"
    return 0
  fi

  printf 'dev\n'
}

PROJECT_VERSION="$(project_version_from_root)"

usage() {
  cat <<EOF
Usage: $0 [--device /dev/sdX] [--list-devices] [--yes] [--allow-non-usb] [--allow-system-disk]
       [--json] [--dry-run] [--label NAME] [--require-checksums]

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
  [[ "$LIST_JSON" == "1" ]] && sudo_args+=(--json)
  [[ "$ASSUME_YES" == "1" ]] && sudo_args+=(--yes)
  [[ "$DRY_RUN" == "1" ]] && sudo_args+=(--dry-run)
  [[ "$REQUIRE_CHECKSUMS" == "1" ]] && sudo_args+=(--require-checksums)
  [[ "$ALLOW_NON_USB_DEVICE" == "1" ]] && sudo_args+=(--allow-non-usb)
  [[ "$ALLOW_SYSTEM_DISK" == "1" ]] && sudo_args+=(--allow-system-disk)
  exec sudo \
    USB_LABEL="$USB_LABEL" \
    RELEASE_PAYLOAD_URL="$RELEASE_PAYLOAD_URL" \
    INSTALL_PAYLOAD_URL="$INSTALL_PAYLOAD_URL" \
    RELEASE_BOOTSTRAP_URL="$RELEASE_BOOTSTRAP_URL" \
    PVE_DCV_BOOTSTRAP_CACHE_DIR="$BOOTSTRAP_CACHE_DIR" \
    PVE_DCV_BOOTSTRAP_BASE="${PVE_DCV_BOOTSTRAP_BASE:-}" \
    MIN_DEVICE_BYTES="$MIN_DEVICE_BYTES" \
    PVE_THIN_CLIENT_PRESET_NAME="$PVE_THIN_CLIENT_PRESET_NAME" \
    PVE_THIN_CLIENT_PRESET_B64="$PVE_THIN_CLIENT_PRESET_B64" \
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
  local tarball extracted checksum_file payload_name checksum_url checksum_log bootstrap_url
  local cache_dir cached_tarball download_target used_cached checksum_entry_found checksum_ok
  if [[ -d "$REPO_ROOT/thin-client-assistant" && -x "$REPO_ROOT/scripts/build-thin-client-installer.sh" ]]; then
    return 0
  fi

  require_tool curl
  require_tool tar

  BOOTSTRAP_DIR="$(allocate_bootstrap_dir)"
  extracted="$BOOTSTRAP_DIR/extracted"
  mkdir -p "$extracted"
  chmod 0755 "$BOOTSTRAP_DIR" "$extracted"

  bootstrap_url="${RELEASE_BOOTSTRAP_URL:-${RELEASE_PAYLOAD_URL:-}}"
  [[ -n "$bootstrap_url" ]] || {
    echo "Standalone mode requires RELEASE_BOOTSTRAP_URL to point at a hosted thin-client USB bootstrap tarball." >&2
    echo "Use the host-provided installer from https://<proxmox-host>:8443/pve-dcv-downloads/ or export RELEASE_BOOTSTRAP_URL manually." >&2
    exit 1
  }

  payload_name="$(basename "$bootstrap_url")"
  tarball="$BOOTSTRAP_DIR/$payload_name"
  cache_dir="$BOOTSTRAP_CACHE_DIR"
  cached_tarball=""
  used_cached="0"
  checksum_entry_found="0"
  checksum_ok="0"

  if [[ -n "$cache_dir" ]]; then
    if mkdir -p "$cache_dir" 2>/dev/null; then
      cached_tarball="$cache_dir/$payload_name"
    fi
  fi

  checksum_file="$BOOTSTRAP_DIR/SHA256SUMS"
  checksum_url="${bootstrap_url%/*}/SHA256SUMS"
  checksum_log="$BOOTSTRAP_DIR/checksum-download.log"

  if [[ -n "$cached_tarball" && -f "$cached_tarball" ]]; then
    echo "Using cached bootstrap candidate: $cached_tarball"
    cp -f "$cached_tarball" "$tarball"
    used_cached="1"
  fi

  if curl --fail --silent --location --retry 2 --retry-delay 1 "$checksum_url" -o "$checksum_file" 2>"$checksum_log"; then
    if grep -F " ${payload_name}" "$checksum_file" >"$BOOTSTRAP_DIR/payload.sha256"; then
      checksum_entry_found="1"
      if [[ "$used_cached" == "1" ]]; then
        if (
          cd "$BOOTSTRAP_DIR"
          sha256sum -c payload.sha256 >/dev/null
        ); then
          checksum_ok="1"
        else
          checksum_ok="0"
        fi
      fi
    else
      if [[ "$REQUIRE_CHECKSUMS" == "1" ]]; then
        echo "Checksum verification is required but SHA256SUMS has no entry for $payload_name." >&2
        exit 1
      fi
      echo "Warning: no checksum entry found for $payload_name, continuing without SHA256 verification." >&2
    fi
  else
    if [[ "$REQUIRE_CHECKSUMS" == "1" ]]; then
      echo "Checksum verification is required but companion SHA256SUMS could not be downloaded from $checksum_url." >&2
      if [[ -s "$checksum_log" ]]; then
        cat "$checksum_log" >&2
      fi
      exit 1
    fi
    echo "Warning: unable to download companion SHA256SUMS, continuing without payload verification." >&2
  fi

  if [[ "$used_cached" == "1" ]]; then
    if [[ "$checksum_entry_found" == "1" && "$checksum_ok" == "1" ]]; then
      echo "Cached bootstrap verified successfully."
    elif [[ "$checksum_entry_found" == "1" ]]; then
      echo "Cached bootstrap checksum failed, re-downloading..." >&2
      used_cached="0"
    else
      echo "Proceeding with unverified cached bootstrap (no checksum entry)." >&2
    fi
  fi

  if [[ "$used_cached" != "1" ]]; then
    download_target="$tarball"
    if [[ -n "$cached_tarball" ]]; then
      download_target="$cached_tarball"
    fi
    echo "Downloading thin-client bootstrap bundle from $bootstrap_url ..."
    curl --fail --show-error --location --retry 3 --retry-delay 2 --continue-at - "$bootstrap_url" -o "$download_target"
    if [[ "$download_target" != "$tarball" ]]; then
      cp -f "$download_target" "$tarball"
    fi

    if [[ "$checksum_entry_found" == "1" ]]; then
      (
        cd "$BOOTSTRAP_DIR"
        sha256sum -c payload.sha256 >/dev/null
      )
    fi
  fi

  tar -xzf "$tarball" -C "$extracted"
  REPO_ROOT="$extracted"
  DIST_DIR="$REPO_ROOT/dist/pve-thin-client-installer"
  ASSET_DIR="$DIST_DIR/live"
  BOOTSTRAPPED_STANDALONE="1"
  PROJECT_VERSION="$(project_version_from_root)"
  GRUB_BACKGROUND_SRC="$REPO_ROOT/thin-client-assistant/usb/assets/grub-background.jpg"
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
      --json)
        LIST_JSON="1"
        shift
        ;;
      --yes|--force)
        ASSUME_YES="1"
        shift
        ;;
      --dry-run)
        DRY_RUN="1"
        shift
        ;;
      --require-checksums)
        REQUIRE_CHECKSUMS="1"
        shift
        ;;
      --label)
        USB_LABEL="$2"
        shift 2
        ;;
      --allow-non-usb)
        ALLOW_NON_USB_DEVICE="1"
        shift
        ;;
      --allow-system-disk)
        ALLOW_SYSTEM_DISK="1"
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

print_devices_json() {
  lsblk -J -d -o PATH,SIZE,MODEL,TYPE,RM,TRAN
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

have_graphical_dialog() {
  [[ -n "${DISPLAY:-}" ]] && command -v zenity >/dev/null 2>&1
}

detect_tty_path() {
  local tty_path="/dev/tty"

  if [[ -r "$tty_path" && -w "$tty_path" ]]; then
    printf '%s\n' "$tty_path"
  fi
}

have_tui_dialog() {
  local tty_path="${1:-}"
  [[ -n "$tty_path" ]] && command -v whiptail >/dev/null 2>&1
}

run_whiptail() {
  local tty_path="$1"
  shift

  whiptail "$@" --output-fd 3 \
    3>&1 \
    1>"$tty_path" \
    2>"$tty_path" \
    <"$tty_path"
}

zenity_env() {
  local zenity_config_dir="$1"

  env \
    HOME="$zenity_config_dir" \
    XDG_CONFIG_HOME="$zenity_config_dir" \
    XDG_CACHE_HOME="$zenity_config_dir/.cache" \
    XDG_DATA_HOME="$zenity_config_dir/.local/share" \
    XDG_RUNTIME_DIR="$zenity_config_dir/runtime" \
    XDG_CURRENT_DESKTOP="" \
    DESKTOP_SESSION="" \
    GSETTINGS_BACKEND=memory \
    GIO_USE_VFS=local \
    GTK_THEME="${PVE_DCV_ZENITY_THEME:-Adwaita}" \
    GTK_PATH="" \
    GTK_RC_FILES=/dev/null \
    GTK2_RC_FILES=/dev/null \
    GTK_USE_PORTAL=0 \
    NO_AT_BRIDGE=1
}

extract_block_device_from_text() {
  local text="$1"
  printf '%s\n' "$text" | grep -Eo '/dev/[[:alnum:]_.+:/-]+' | tail -n1
}

run_zenity() {
  local zenity_config_dir=""
  local zenity_stderr=""
  local output=""
  local status=0

  zenity_config_dir="$(mktemp -d "${TMPDIR:-/tmp}/pve-dcv-zenity.XXXXXX")"
  zenity_stderr="$zenity_config_dir/stderr.log"
  mkdir -p \
    "$zenity_config_dir/gtk-3.0" \
    "$zenity_config_dir/.cache" \
    "$zenity_config_dir/.local/share" \
    "$zenity_config_dir/runtime"
  chmod 0700 "$zenity_config_dir/runtime"

  output="$(zenity_env "$zenity_config_dir" zenity "$@" 2>"$zenity_stderr")" || status=$?

  if [[ "$status" -ne 0 && "$status" -ne 1 ]] && command -v dbus-run-session >/dev/null 2>&1; then
    status=0
    : >"$zenity_stderr"
    output="$(
      DBUS_SESSION_BUS_ADDRESS="" \
      zenity_env "$zenity_config_dir" \
      dbus-run-session -- \
      zenity "$@" 2>"$zenity_stderr"
    )" || status=$?
  fi

  if [[ -n "$output" ]]; then
    printf '%s\n' "$output"
  fi

  if [[ "$status" -ne 0 && "$status" -ne 1 && -s "$zenity_stderr" ]]; then
    cat "$zenity_stderr" >&2
  fi

  rm -rf "$zenity_config_dir"
  return "$status"
}

payload_has_live_assets() {
  [[ -f "$ASSET_DIR/filesystem.squashfs" && -f "$ASSET_DIR/vmlinuz" && -f "$ASSET_DIR/initrd.img" && -f "$ASSET_DIR/SHA256SUMS" ]]
}

choose_device() {
  local options=()
  local zenity_rows=()
  local device tty_path name size model type rm transport answer index zenity_status selected_device
  local menu_height=16

  tty_path="$(detect_tty_path || true)"

  while IFS= read -r line; do
    eval "$line"
    [[ "${TYPE:-}" == "disk" ]] || continue
    device="/dev/${NAME}"
    [[ "$device" == /dev/loop* || "$device" == /dev/sr* || "$device" == /dev/ram* || "$device" == /dev/zram* ]] && continue
    if [[ "$ALLOW_NON_USB_DEVICE" != "1" && "${RM:-0}" != "1" && "${TRAN:-}" != "usb" ]]; then
      continue
    fi
    options+=("$device" "${MODEL:-disk} ${SIZE:-unknown} usb=${TRAN:-}")
    zenity_rows+=("$device" "${SIZE:-unknown}" "${MODEL:-disk}" "${TRAN:-unknown}")
  done <<EOF
$(list_candidate_devices)
EOF

  if (( ${#options[@]} == 0 )); then
    if [[ "$ALLOW_NON_USB_DEVICE" != "1" ]]; then
      echo "No removable/USB target device found. Re-run with --allow-non-usb to show all disks." >&2
      exit 1
    fi
    echo "No writable block device found." >&2
    exit 1
  fi

  if have_tui_dialog "$tty_path"; then
    if (( ${#options[@]} / 2 < menu_height )); then
      menu_height=$(( ${#options[@]} / 2 + 6 ))
    fi
    answer="$(run_whiptail "$tty_path" \
      --title "PVE Thin Client USB Writer" \
      --backtitle "Bootable USB installer creation" \
      --menu "Select the USB target device. The selected drive will be erased completely." \
      22 100 "$menu_height" \
      "${options[@]}")" || return $?
    selected_device="$(extract_block_device_from_text "$answer")"
    [[ -n "$selected_device" && -b "$selected_device" ]] || {
      echo "Terminal device picker returned an invalid selection: ${answer:-<empty>}" >&2
      exit 1
    }
    printf '%s\n' "$selected_device"
    return 0
  fi

  if have_graphical_dialog; then
    if answer="$(run_zenity --list \
      --title="PVE Thin Client USB Writer" \
      --text="Choose the USB target device for the installer media." \
      --width=920 \
      --height=520 \
      --column="Device" \
      --column="Size" \
      --column="Model" \
      --column="Transport" \
      "${zenity_rows[@]}")"; then
      selected_device="$(extract_block_device_from_text "$answer")"
      if [[ -n "$selected_device" ]]; then
        printf '%s\n' "$selected_device"
        return 0
      fi
      echo "Graphical device picker returned an invalid selection, falling back to terminal selection." >&2
    fi
    zenity_status=$?
    if [[ "$zenity_status" -eq 1 ]]; then
      exit 1
    fi
    echo "Graphical device picker failed, falling back to terminal selection." >&2
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

device_is_usb_like() {
  local device="$1"
  local rm transport

  rm="$(lsblk -dn -o RM "$device" 2>/dev/null | head -n1 | tr -d ' ')"
  transport="$(lsblk -dn -o TRAN "$device" 2>/dev/null | head -n1 | tr -d ' ')"
  [[ "$rm" == "1" || "$transport" == "usb" ]]
}

root_backing_disk() {
  local source pkname
  source="$(findmnt -no SOURCE / 2>/dev/null || true)"
  [[ -n "$source" ]] || return 1
  pkname="$(lsblk -ndo PKNAME "$source" 2>/dev/null | head -n1)"
  [[ -n "$pkname" ]] || return 1
  printf '/dev/%s\n' "$pkname"
}

device_contains_path_source() {
  local path="$1"
  local source

  source="$(findmnt -no SOURCE "$path" 2>/dev/null || true)"
  [[ -n "$source" ]] || return 1
  lsblk -nrpo NAME "$TARGET_DEVICE" 2>/dev/null | grep -Fxq "$source"
}

ensure_target_is_safe() {
  local root_disk device_size

  if [[ "$ALLOW_NON_USB_DEVICE" != "1" ]] && ! device_is_usb_like "$TARGET_DEVICE"; then
    echo "Refusing to write non-USB/non-removable device $TARGET_DEVICE. Use --allow-non-usb to override." >&2
    exit 1
  fi

  root_disk="$(root_backing_disk || true)"
  if [[ "$ALLOW_SYSTEM_DISK" != "1" ]]; then
    if [[ -n "$root_disk" && "$TARGET_DEVICE" == "$root_disk" ]]; then
      echo "Refusing to overwrite the current system disk $TARGET_DEVICE. Use --allow-system-disk to override." >&2
      exit 1
    fi
    if device_contains_path_source / || device_contains_path_source /boot || device_contains_path_source /boot/efi; then
      echo "Refusing to overwrite a disk backing the running system. Use --allow-system-disk to override." >&2
      exit 1
    fi
  fi

  device_size="$(blockdev --getsize64 "$TARGET_DEVICE")"
  if (( device_size < MIN_DEVICE_BYTES )); then
    echo "Target device $TARGET_DEVICE is too small (${device_size} bytes). Need at least ${MIN_DEVICE_BYTES} bytes." >&2
    exit 1
  fi
}

confirm_device() {
  local answer zenity_status tty_path

  [[ -b "$TARGET_DEVICE" ]] || {
    echo "Block device not found: $TARGET_DEVICE" >&2
    print_devices >&2
    exit 1
  }

  ensure_target_is_safe

  lsblk "$TARGET_DEVICE"
  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  if [[ "$ASSUME_YES" == "1" ]]; then
    return 0
  fi

  tty_path="$(detect_tty_path || true)"
  if have_tui_dialog "$tty_path"; then
    run_whiptail "$tty_path" \
      --title "Write USB Installer" \
      --backtitle "PVE Thin Client USB Writer" \
      --yesno "The selected drive will be erased completely and turned into a bootable PVE Thin Client installer.\n\nTarget: ${TARGET_DEVICE}\nPreset: ${PVE_THIN_CLIENT_PRESET_NAME:-generic}" \
      16 84
    return $?
  fi

  if have_graphical_dialog; then
    if run_zenity --question \
      --title="Write USB Installer" \
      --width=760 \
      --text="The selected drive will be erased completely and turned into a bootable PVE Thin Client installer.\n\nTarget: ${TARGET_DEVICE}\nPreset: ${PVE_THIN_CLIENT_PRESET_NAME:-generic}" \
      --ok-label="Write USB" \
      --cancel-label="Cancel"; then
      return 0
    fi
    zenity_status=$?
    if [[ "$zenity_status" -eq 1 ]]; then
      return 1
    fi
    echo "Graphical confirmation dialog failed, falling back to terminal prompt." >&2
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
  if payload_has_live_assets; then
    return 0
  fi

  if [[ "$BOOTSTRAPPED_STANDALONE" == "1" ]]; then
    echo "Hosted payload bundle is incomplete: missing live installer assets under $ASSET_DIR" >&2
    echo "Refresh host artifacts on the Proxmox server and download a fresh installer." >&2
    exit 1
  fi

  "$REPO_ROOT/scripts/build-thin-client-installer.sh"
}

validate_live_assets() {
  if [[ ! -f "$ASSET_DIR/SHA256SUMS" ]]; then
    echo "Missing live asset checksum file: $ASSET_DIR/SHA256SUMS" >&2
    exit 1
  fi

  (
    cd "$ASSET_DIR"
    sha256sum -c SHA256SUMS
  )
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

write_usb_manifest() {
  local mount_dir="$1"
  local payload_source installer_sha payload_sha

  payload_source="${INSTALL_PAYLOAD_URL:-${RELEASE_PAYLOAD_URL:-$REPO_ROOT/dist/pve-thin-client-usb-payload-latest.tar.gz}}"
  installer_sha="$(sha256sum "$mount_dir/start-installer-menu.sh" | awk '{print $1}')"
  payload_sha="$(sha256sum "$mount_dir/pve-thin-client/live/filesystem.squashfs" | awk '{print $1}')"

  python3 - "$mount_dir/.pve-dcv-usb-manifest.json" "$PROJECT_VERSION" "$USB_LABEL" "$TARGET_DEVICE" "$payload_source" "$installer_sha" "$payload_sha" "${PVE_THIN_CLIENT_PRESET_NAME:-}" <<'PY'
import json
import socket
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

path = Path(sys.argv[1])
version = sys.argv[2]
label = sys.argv[3]
device = sys.argv[4]
payload_source = sys.argv[5]
installer_sha = sys.argv[6]
payload_sha = sys.argv[7]
preset_name = sys.argv[8]
parsed = urlparse(payload_source) if payload_source else None
proxmox_host = parsed.hostname if parsed and parsed.hostname else ""
proxmox_host_ip = ""
if proxmox_host:
    try:
        infos = socket.getaddrinfo(proxmox_host, None, family=socket.AF_INET, type=socket.SOCK_STREAM)
    except OSError:
        infos = []
    for info in infos:
        candidate = info[4][0]
        if candidate:
            proxmox_host_ip = candidate
            break

payload = {
    "project_version": version,
    "usb_label": label,
    "target_device": device,
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "payload_source": payload_source,
    "start_installer_menu_sha256": installer_sha,
    "filesystem_squashfs_sha256": payload_sha,
    "preset_name": preset_name,
    "proxmox_api_scheme": "https",
    "proxmox_api_host": proxmox_host,
    "proxmox_api_host_ip": proxmox_host_ip,
    "proxmox_api_port": "8006",
    "proxmox_api_verify_tls": "0",
}
path.write_text(json.dumps(payload, indent=2) + "\n")
PY

  install -m 0644 "$mount_dir/.pve-dcv-usb-manifest.json" "$mount_dir/pve-thin-client/live/.pve-dcv-usb-manifest.json"
}

write_usb_preset() {
  local mount_dir="$1"
  local preset_file

  [[ -n "$PVE_THIN_CLIENT_PRESET_B64" ]] || return 0

  preset_file="$mount_dir/pve-thin-client/preset.env"
  install -d -m 0755 "$mount_dir/pve-thin-client"
  python3 - "$preset_file" "$PVE_THIN_CLIENT_PRESET_B64" <<'PY'
import base64
import sys
from pathlib import Path

target = Path(sys.argv[1])
payload = sys.argv[2].strip()
if not payload:
    raise SystemExit(0)

decoded = base64.b64decode(payload.encode("ascii"), validate=True)
target.write_bytes(decoded)
target.chmod(0o600)
PY

  # The live installer UI probes presets before escalating privileges.
  # Keep preset readable inside the live medium to avoid false "no preset" states.
  install -m 0644 "$preset_file" "$mount_dir/pve-thin-client/live/preset.env"
}

build_preset_kernel_args() {
  [[ -n "$PVE_THIN_CLIENT_PRESET_B64" ]] || return 0

  python3 - "$PVE_THIN_CLIENT_PRESET_B64" <<'PY'
import base64
import gzip
import sys
import textwrap

payload = sys.argv[1].strip()
if not payload:
    raise SystemExit(0)

decoded = base64.b64decode(payload.encode("ascii"), validate=True)
encoded = base64.urlsafe_b64encode(gzip.compress(decoded, compresslevel=9)).decode("ascii").rstrip("=")

parts = ["pve_thin_client.preset_codec=gzip+base64url"]
for index, chunk in enumerate(textwrap.wrap(encoded, 180)):
    parts.append(f"pve_thin_client.preset_b64_{index:03d}={chunk}")

print(" ".join(parts))
PY
}

print_write_plan() {
  local bootstrap_source install_payload_source

  bootstrap_source="${RELEASE_BOOTSTRAP_URL:-${RELEASE_PAYLOAD_URL:-$REPO_ROOT/dist/pve-thin-client-usb-payload-latest.tar.gz}}"
  install_payload_source="${INSTALL_PAYLOAD_URL:-${RELEASE_PAYLOAD_URL:-$REPO_ROOT/dist/pve-thin-client-usb-payload-latest.tar.gz}}"
  cat <<EOF
Dry run only. No changes were written.
Target device: $TARGET_DEVICE
USB label: $USB_LABEL
Project version: $PROJECT_VERSION
Bootstrap source: ${bootstrap_source}
Install payload source: ${install_payload_source}
Preset profile: ${PVE_THIN_CLIENT_PRESET_NAME:-generic}
Planned partitions:
  1. BIOS boot partition (1 MiB - 3 MiB)
  2. FAT32 EFI/data partition (3 MiB - 100%)
Copied assets:
  - live kernel, initrd and squashfs
  - thin-client assistant sources
  - embedded VM preset profile
  - docs, README, LICENSE, CHANGELOG
  - generated USB manifest
EOF
}

write_usb() {
  local mount_dir bios_partition usb_partition usb_uuid preset_kernel_args

  if [[ "$DRY_RUN" == "1" ]]; then
    print_write_plan
    return 0
  fi

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
  for _ in $(seq 1 20); do
    [[ -b "$usb_partition" ]] && break
    sleep 1
    udevadm settle || true
  done
  [[ -b "$usb_partition" ]] || {
    echo "EFI/data partition was not created on $TARGET_DEVICE" >&2
    exit 1
  }
  mkfs.vfat -F 32 -n "$USB_LABEL" "$usb_partition"
  usb_uuid="$(blkid -s UUID -o value "$usb_partition" 2>/dev/null || true)"
  [[ -n "$usb_uuid" ]] || {
    echo "Unable to determine UUID for USB installer partition $usb_partition" >&2
    exit 1
  }
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
  if [[ -f "$GRUB_BACKGROUND_SRC" ]]; then
    install -m 0644 "$GRUB_BACKGROUND_SRC" "$mount_dir/boot/grub/background.jpg"
  fi
  write_usb_preset "$mount_dir"
  write_usb_manifest "$mount_dir"
  preset_kernel_args="$(build_preset_kernel_args || true)"

  cat > "$mount_dir/boot/grub/grub.cfg" <<EOF
insmod all_video
insmod gfxterm
insmod jpeg
terminal_output gfxterm
if background_image /boot/grub/background.jpg; then
  set color_normal=white/black
  set color_highlight=black/light-gray
fi
set default=0
set timeout=5
set preset_args="${preset_kernel_args}"

menuentry 'Thinclient Installer' {
  linux /pve-thin-client/live/vmlinuz boot=live components username=thinclient hostname=pve-thin-client live-media=/dev/disk/by-uuid/${usb_uuid} live-media-path=/pve-thin-client/live live-media-timeout=10 ip=dhcp quiet loglevel=3 systemd.show_status=0 vt.global_cursor_default=0 splash \${preset_args} pve_thin_client.mode=installer
  initrd /pve-thin-client/live/initrd.img
}

menuentry 'Thinclient Installer (compatibility mode)' {
  linux /pve-thin-client/live/vmlinuz boot=live components username=thinclient hostname=pve-thin-client live-media=/dev/disk/by-uuid/${usb_uuid} live-media-path=/pve-thin-client/live live-media-timeout=10 ip=dhcp quiet loglevel=3 systemd.show_status=0 vt.global_cursor_default=0 splash nomodeset irqpoll pci=nomsi noapic \${preset_args} pve_thin_client.mode=installer
  initrd /pve-thin-client/live/initrd.img
}

menuentry 'Thinclient Installer (legacy IRQ mode)' {
  linux /pve-thin-client/live/vmlinuz boot=live components username=thinclient hostname=pve-thin-client live-media=/dev/disk/by-uuid/${usb_uuid} live-media-path=/pve-thin-client/live live-media-timeout=10 ip=dhcp quiet loglevel=3 systemd.show_status=0 vt.global_cursor_default=0 splash nomodeset irqpoll noapic nolapic \${preset_args} pve_thin_client.mode=installer
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

  (
    cd "$mount_dir/pve-thin-client/live"
    sha256sum -c SHA256SUMS
  )

  sync
}

parse_args "$@"
if [[ "$LIST_DEVICES" == "1" ]]; then
  if [[ "$LIST_JSON" == "1" ]]; then
    print_devices_json
  else
    print_devices
  fi
  exit 0
fi
if [[ -z "$TARGET_DEVICE" ]]; then
  TARGET_DEVICE="$(choose_device)"
fi
rerun_as_root
require_tool lsblk
bootstrap_repo_root
install_dependencies
ensure_live_assets
validate_live_assets
confirm_device
write_usb
echo "USB installer media prepared on $TARGET_DEVICE"
