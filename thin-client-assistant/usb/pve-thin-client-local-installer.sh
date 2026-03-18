#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIVE_MEDIUM="${LIVE_MEDIUM:-/run/live/medium}"
TARGET_MOUNT="/mnt/pve-thin-client-target"
EFI_MOUNT="$TARGET_MOUNT/boot/efi"
LIVE_ASSET_DIR="${LIVE_MEDIUM}/pve-thin-client/live"
STATE_DIR="$TARGET_MOUNT/pve-thin-client/state"
PRESET_FILE="${LIVE_MEDIUM}/pve-thin-client/preset.env"
PRESET_ACTIVE="0"
GRUB_BACKGROUND_SRC="$ROOT_DIR/usb/assets/grub-background.jpg"
TARGET_DISK_OVERRIDE=""
ASSUME_YES="0"
PRINT_TARGETS_JSON="0"
PRINT_PRESET_JSON="0"
PRINT_PRESET_SUMMARY="0"

MODE=""
CONNECTION_METHOD=""
PROFILE_NAME="default"
RUNTIME_USER="thinclient"
HOSTNAME_VALUE="pve-thin-client"
AUTOSTART="1"
NETWORK_MODE="dhcp"
NETWORK_INTERFACE="eth0"
NETWORK_STATIC_ADDRESS=""
NETWORK_STATIC_PREFIX="24"
NETWORK_GATEWAY=""
NETWORK_DNS_SERVERS="1.1.1.1 8.8.8.8"
SPICE_URL=""
NOVNC_URL=""
DCV_URL=""
MOONLIGHT_HOST=""
MOONLIGHT_APP="Desktop"
REMOTE_VIEWER_BIN="remote-viewer"
BROWSER_BIN="chromium"
BROWSER_FLAGS="--kiosk --incognito --no-first-run --disable-session-crashed-bubble"
DCV_VIEWER_BIN="dcvviewer"
MOONLIGHT_BIN="moonlight"
MOONLIGHT_RESOLUTION="1080"
MOONLIGHT_FPS="60"
MOONLIGHT_BITRATE="20000"
MOONLIGHT_VIDEO_CODEC="H.264"
MOONLIGHT_VIDEO_DECODER="auto"
MOONLIGHT_AUDIO_CONFIG="stereo"
MOONLIGHT_ABSOLUTE_MOUSE="1"
MOONLIGHT_QUIT_AFTER="0"
SUNSHINE_API_URL=""
PROXMOX_SCHEME="https"
PROXMOX_HOST=""
PROXMOX_PORT="8006"
PROXMOX_NODE=""
PROXMOX_VMID=""
PROXMOX_REALM="pam"
PROXMOX_VERIFY_TLS="0"
CONNECTION_USERNAME=""
CONNECTION_PASSWORD=""
CONNECTION_TOKEN=""
SUNSHINE_USERNAME=""
SUNSHINE_PASSWORD=""
SUNSHINE_PIN=""

cleanup() {
  umount "$EFI_MOUNT" >/dev/null 2>&1 || true
  umount "$TARGET_MOUNT" >/dev/null 2>&1 || true
  rmdir "$EFI_MOUNT" >/dev/null 2>&1 || true
  rmdir "$TARGET_MOUNT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo "$0" "$@"
    fi
    echo "This installer must run as root." >&2
    exit 1
  fi
}

require_tools() {
  local missing=()
  local tool
  for tool in grub-install mkfs.vfat mkfs.ext4 parted lsblk blkid findmnt python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      dosfstools \
      e2fsprogs \
      parted \
      grub-pc-bin \
      grub-efi-amd64-bin \
      efibootmgr \
      python3
  fi
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

current_live_disk() {
  local medium_source parent_name
  medium_source="$(findmnt -n -o SOURCE "$LIVE_MEDIUM" 2>/dev/null || true)"
  if [[ -n "$medium_source" ]]; then
    parent_name="$(lsblk -ndo PKNAME "$medium_source" 2>/dev/null || true)"
    if [[ -n "$parent_name" ]]; then
      printf '/dev/%s\n' "$parent_name"
      return 0
    fi
  fi
  return 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        MODE="$2"
        shift 2
        ;;
      --target-disk)
        TARGET_DISK_OVERRIDE="$2"
        shift 2
        ;;
      --yes|--force)
        ASSUME_YES="1"
        shift
        ;;
      --list-targets-json)
        PRINT_TARGETS_JSON="1"
        shift
        ;;
      --print-preset-json)
        PRINT_PRESET_JSON="1"
        shift
        ;;
      --print-preset-summary)
        PRINT_PRESET_SUMMARY="1"
        shift
        ;;
      *)
        echo "Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done
}

print_target_disks_json() {
  local live_disk
  live_disk="$(current_live_disk 2>/dev/null || true)"

  python3 - "$live_disk" <<'PY'
import json
import shlex
import subprocess
import sys

live_disk = sys.argv[1]
result = []
output = subprocess.check_output(
    ["lsblk", "-dn", "-P", "-o", "NAME,SIZE,MODEL,TYPE,RM,TRAN"], text=True
)

for line in output.splitlines():
    entry = {}
    for token in shlex.split(line):
      key, value = token.split("=", 1)
      entry[key] = value
    if entry.get("TYPE") != "disk":
        continue
    device = f"/dev/{entry['NAME']}"
    if device == live_disk:
        continue
    if any(device.startswith(prefix) for prefix in ("/dev/loop", "/dev/sr", "/dev/ram", "/dev/zram")):
        continue
    result.append(
        {
            "device": device,
            "size": entry.get("SIZE", "unknown"),
            "model": entry.get("MODEL", "disk"),
            "removable": entry.get("RM", "0"),
            "transport": entry.get("TRAN", ""),
        }
    )

print(json.dumps(result, indent=2))
PY
}

choose_target_disk() {
  local live_disk menu_items device label name size model type rm transport answer tty_path
  if [[ -n "$TARGET_DISK_OVERRIDE" ]]; then
    printf '%s\n' "$TARGET_DISK_OVERRIDE"
    return 0
  fi

  live_disk="$(current_live_disk 2>/dev/null || true)"
  menu_items=()
  tty_path="/dev/tty"

  if [[ ! -r "$tty_path" || ! -w "$tty_path" ]]; then
    tty_path=""
  fi

  while IFS= read -r line; do
    eval "$line"
    [[ "${TYPE:-}" == "disk" ]] || continue
    device="/dev/${NAME}"
    [[ "$device" == "$live_disk" ]] && continue
    [[ "$device" == /dev/loop* || "$device" == /dev/sr* || "$device" == /dev/ram* || "$device" == /dev/zram* ]] && continue
    label="${MODEL:-disk} ${SIZE:-unknown} rm=${RM:-0} ${TRAN:-}"
    menu_items+=("$device" "$label")
  done <<EOF
$(lsblk -dn -P -o NAME,SIZE,MODEL,TYPE,RM,TRAN)
EOF

  if (( ${#menu_items[@]} == 0 )); then
    echo "No writable target disk found." >&2
    exit 1
  fi

  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "PVE Thin Client Installation" --menu \
      "Choose the target disk. It will be erased completely." 22 96 10 \
      "${menu_items[@]}" 3>&1 1>&2 2>&3
    return 0
  fi

  if [[ -z "$tty_path" ]]; then
    echo "Interactive disk selection requires a TTY." >&2
    exit 1
  fi

  local index=1
  printf 'Available installation targets:\n' >"$tty_path"
  while (( index <= ${#menu_items[@]} / 2 )); do
    printf '%s) %s %s\n' "$index" "${menu_items[$(( (index - 1) * 2 ))]}" "${menu_items[$(( (index - 1) * 2 + 1 ))]}" >"$tty_path"
    index=$((index + 1))
  done

  printf 'Choice: ' >"$tty_path"
  read -r answer <"$tty_path"
  [[ "$answer" =~ ^[0-9]+$ ]] || {
    echo "Invalid selection: $answer" >&2
    exit 1
  }
  (( answer >= 1 && answer <= ${#menu_items[@]} / 2 )) || {
    echo "Selection out of range: $answer" >&2
    exit 1
  }
  printf '%s\n' "${menu_items[$(( (answer - 1) * 2 ))]}"
}

confirm_wipe() {
  local target_disk="$1"
  if [[ "$ASSUME_YES" == "1" ]]; then
    return 0
  fi

  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "PVE Thin Client Installation" --yesno \
      "The disk ${target_disk} will be fully erased and turned into a local thin-client boot disk." 14 88
    return $?
  fi

  read -r -p "Erase ${target_disk} completely? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

load_profile() {
  local output
  output="$(
    MODE="$MODE" \
    CONNECTION_METHOD="$CONNECTION_METHOD" \
    PROFILE_NAME="$PROFILE_NAME" \
    RUNTIME_USER="$RUNTIME_USER" \
    HOSTNAME_VALUE="$HOSTNAME_VALUE" \
    AUTOSTART="$AUTOSTART" \
    NETWORK_MODE="$NETWORK_MODE" \
    NETWORK_INTERFACE="$NETWORK_INTERFACE" \
    NETWORK_STATIC_ADDRESS="$NETWORK_STATIC_ADDRESS" \
    NETWORK_STATIC_PREFIX="$NETWORK_STATIC_PREFIX" \
    NETWORK_GATEWAY="$NETWORK_GATEWAY" \
    NETWORK_DNS_SERVERS="$NETWORK_DNS_SERVERS" \
    SPICE_URL="$SPICE_URL" \
    NOVNC_URL="$NOVNC_URL" \
    DCV_URL="$DCV_URL" \
    MOONLIGHT_HOST="$MOONLIGHT_HOST" \
    MOONLIGHT_APP="$MOONLIGHT_APP" \
    REMOTE_VIEWER_BIN="$REMOTE_VIEWER_BIN" \
    BROWSER_BIN="$BROWSER_BIN" \
    BROWSER_FLAGS="$BROWSER_FLAGS" \
    DCV_VIEWER_BIN="$DCV_VIEWER_BIN" \
    MOONLIGHT_BIN="$MOONLIGHT_BIN" \
    MOONLIGHT_RESOLUTION="$MOONLIGHT_RESOLUTION" \
    MOONLIGHT_FPS="$MOONLIGHT_FPS" \
    MOONLIGHT_BITRATE="$MOONLIGHT_BITRATE" \
    MOONLIGHT_VIDEO_CODEC="$MOONLIGHT_VIDEO_CODEC" \
    MOONLIGHT_VIDEO_DECODER="$MOONLIGHT_VIDEO_DECODER" \
    MOONLIGHT_AUDIO_CONFIG="$MOONLIGHT_AUDIO_CONFIG" \
    MOONLIGHT_ABSOLUTE_MOUSE="$MOONLIGHT_ABSOLUTE_MOUSE" \
    MOONLIGHT_QUIT_AFTER="$MOONLIGHT_QUIT_AFTER" \
    SUNSHINE_API_URL="$SUNSHINE_API_URL" \
    PROXMOX_SCHEME="$PROXMOX_SCHEME" \
    PROXMOX_HOST="$PROXMOX_HOST" \
    PROXMOX_PORT="$PROXMOX_PORT" \
    PROXMOX_NODE="$PROXMOX_NODE" \
    PROXMOX_VMID="$PROXMOX_VMID" \
    PROXMOX_REALM="$PROXMOX_REALM" \
    PROXMOX_VERIFY_TLS="$PROXMOX_VERIFY_TLS" \
    CONNECTION_USERNAME="$CONNECTION_USERNAME" \
    CONNECTION_PASSWORD="$CONNECTION_PASSWORD" \
    CONNECTION_TOKEN="$CONNECTION_TOKEN" \
    SUNSHINE_USERNAME="$SUNSHINE_USERNAME" \
    SUNSHINE_PASSWORD="$SUNSHINE_PASSWORD" \
    SUNSHINE_PIN="$SUNSHINE_PIN" \
    "$ROOT_DIR/installer/setup-menu.sh"
  )"
  eval "$output"
}

load_embedded_preset() {
  if [[ -f "$PRESET_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$PRESET_FILE"
    PRESET_ACTIVE="1"
  fi
}

mode_is_available() {
  local mode="$1"

  case "$mode" in
    SPICE)
      [[ -n "${PVE_THIN_CLIENT_PRESET_SPICE_URL:-}" ]] || {
        [[ -n "${PVE_THIN_CLIENT_PRESET_PROXMOX_HOST:-}" ]] && \
        [[ -n "${PVE_THIN_CLIENT_PRESET_PROXMOX_NODE:-}" ]] && \
        [[ -n "${PVE_THIN_CLIENT_PRESET_PROXMOX_VMID:-}" ]] && \
        [[ -n "${PVE_THIN_CLIENT_PRESET_SPICE_USERNAME:-${PVE_THIN_CLIENT_PRESET_PROXMOX_USERNAME:-}}" ]] && \
        [[ -n "${PVE_THIN_CLIENT_PRESET_SPICE_PASSWORD:-${PVE_THIN_CLIENT_PRESET_PROXMOX_PASSWORD:-}}" ]]
      }
      ;;
    NOVNC)
      [[ -n "${PVE_THIN_CLIENT_PRESET_NOVNC_URL:-}" ]]
      ;;
    DCV)
      [[ -n "${PVE_THIN_CLIENT_PRESET_DCV_URL:-}" ]]
      ;;
    MOONLIGHT)
      [[ -n "${PVE_THIN_CLIENT_PRESET_MOONLIGHT_HOST:-}" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

mode_label() {
  local mode="$1"
  case "$mode" in
    SPICE)
      if [[ -n "${PVE_THIN_CLIENT_PRESET_SPICE_URL:-}" ]]; then
        printf 'SPICE direct launcher\n'
      else
        printf 'SPICE via Proxmox ticket\n'
      fi
      ;;
    NOVNC)
      printf 'noVNC browser session\n'
      ;;
    DCV)
      printf 'Amazon DCV session\n'
      ;;
    MOONLIGHT)
      printf 'Moonlight + Sunshine low-latency stream\n'
      ;;
    *)
      printf '%s\n' "$mode"
      ;;
  esac
}

print_preset_summary() {
  if [[ "$PRESET_ACTIVE" != "1" ]]; then
    echo "No bundled VM preset was found on this USB stick."
    return 0
  fi

  local available=()
  local mode
  for mode in MOONLIGHT SPICE NOVNC DCV; do
    if mode_is_available "$mode"; then
      available+=("$mode")
    fi
  done

  printf 'Bundled VM preset: %s\n' "${PVE_THIN_CLIENT_PRESET_VM_NAME:-${PVE_THIN_CLIENT_PRESET_PROFILE_NAME:-unnamed}}"
  printf 'VMID/Node: %s / %s\n' "${PVE_THIN_CLIENT_PRESET_PROXMOX_VMID:-n/a}" "${PVE_THIN_CLIENT_PRESET_PROXMOX_NODE:-n/a}"
  printf 'Proxmox host: %s\n' "${PVE_THIN_CLIENT_PRESET_PROXMOX_HOST:-n/a}"
  if (( ${#available[@]} > 0 )); then
    printf 'Configured streaming modes: %s\n' "${available[*]}"
  else
    printf 'Configured streaming modes: none\n'
  fi
}

print_preset_json() {
  python3 - "$PRESET_ACTIVE" "${PVE_THIN_CLIENT_PRESET_VM_NAME:-}" "${PVE_THIN_CLIENT_PRESET_PROFILE_NAME:-}" "${PVE_THIN_CLIENT_PRESET_PROXMOX_HOST:-}" "${PVE_THIN_CLIENT_PRESET_PROXMOX_NODE:-}" "${PVE_THIN_CLIENT_PRESET_PROXMOX_VMID:-}" "${PVE_THIN_CLIENT_PRESET_SPICE_URL:-}" "${PVE_THIN_CLIENT_PRESET_PROXMOX_USERNAME:-}" "${PVE_THIN_CLIENT_PRESET_PROXMOX_PASSWORD:-}" "${PVE_THIN_CLIENT_PRESET_SPICE_USERNAME:-}" "${PVE_THIN_CLIENT_PRESET_SPICE_PASSWORD:-}" "${PVE_THIN_CLIENT_PRESET_NOVNC_URL:-}" "${PVE_THIN_CLIENT_PRESET_DCV_URL:-}" "${PVE_THIN_CLIENT_PRESET_MOONLIGHT_HOST:-}" "${PVE_THIN_CLIENT_PRESET_DEFAULT_MODE:-}" "${PVE_THIN_CLIENT_PRESET_MOONLIGHT_APP:-Desktop}" <<'PY'
import json
import sys

(
    preset_active,
    vm_name,
    profile_name,
    proxmox_host,
    proxmox_node,
    proxmox_vmid,
    spice_url,
    proxmox_username,
    proxmox_password,
    spice_username,
    spice_password,
    novnc_url,
    dcv_url,
    moonlight_host,
    default_mode,
    moonlight_app,
) = sys.argv[1:17]

def mode_available(name: str) -> bool:
    if name == "MOONLIGHT":
        return bool(moonlight_host)
    if name == "SPICE":
        return bool(spice_url) or (
            bool(proxmox_host)
            and bool(proxmox_node)
            and bool(proxmox_vmid)
            and bool(spice_username or proxmox_username)
            and bool(spice_password or proxmox_password)
        )
    if name == "NOVNC":
        return bool(novnc_url)
    if name == "DCV":
        return bool(dcv_url)
    return False

payload = {
    "preset_active": preset_active == "1",
    "vm_name": vm_name,
    "profile_name": profile_name,
    "proxmox_host": proxmox_host,
    "proxmox_node": proxmox_node,
    "proxmox_vmid": proxmox_vmid,
    "moonlight_host": moonlight_host,
    "moonlight_app": moonlight_app,
    "default_mode": default_mode,
    "available_modes": [name for name in ("MOONLIGHT", "SPICE", "NOVNC", "DCV") if mode_available(name)],
}
print(json.dumps(payload, indent=2))
PY
}

choose_streaming_mode_from_preset() {
  local modes=()
  local menu_items=()
  local tty_path="/dev/tty"
  local mode answer index

  for mode in MOONLIGHT SPICE NOVNC DCV; do
    if mode_is_available "$mode"; then
      modes+=("$mode")
      menu_items+=("$mode" "$(mode_label "$mode")")
    fi
  done

  if (( ${#modes[@]} == 0 )); then
    echo "The bundled VM preset does not contain a usable Moonlight, SPICE, noVNC or DCV target." >&2
    exit 1
  fi

  if (( ${#modes[@]} == 1 )); then
    printf '%s\n' "${modes[0]}"
    return 0
  fi

  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "PVE Thin Client Installation" --menu \
      "Choose the streaming mode for ${PVE_THIN_CLIENT_PRESET_VM_NAME:-this VM}." 20 88 8 \
      "${menu_items[@]}" 3>&1 1>&2 2>&3
    return 0
  fi

  if [[ ! -r "$tty_path" || ! -w "$tty_path" ]]; then
    echo "Interactive mode selection requires a TTY." >&2
    exit 1
  fi

  printf 'Available streaming modes for %s:\n' "${PVE_THIN_CLIENT_PRESET_VM_NAME:-this VM}" >"$tty_path"
  index=1
  while (( index <= ${#menu_items[@]} / 2 )); do
    printf '%s) %s %s\n' "$index" "${menu_items[$(( (index - 1) * 2 ))]}" "${menu_items[$(( (index - 1) * 2 + 1 ))]}" >"$tty_path"
    index=$((index + 1))
  done
  printf 'Choice: ' >"$tty_path"
  read -r answer <"$tty_path"
  [[ "$answer" =~ ^[0-9]+$ ]] || {
    echo "Invalid selection: $answer" >&2
    exit 1
  }
  (( answer >= 1 && answer <= ${#menu_items[@]} / 2 )) || {
    echo "Selection out of range: $answer" >&2
    exit 1
  }
  printf '%s\n' "${menu_items[$(( (answer - 1) * 2 ))]}"
}

apply_preset_defaults() {
  PROFILE_NAME="${PVE_THIN_CLIENT_PRESET_PROFILE_NAME:-default}"
  HOSTNAME_VALUE="${PVE_THIN_CLIENT_PRESET_HOSTNAME_VALUE:-pve-thin-client}"
  AUTOSTART="${PVE_THIN_CLIENT_PRESET_AUTOSTART:-1}"
  NETWORK_MODE="${PVE_THIN_CLIENT_PRESET_NETWORK_MODE:-dhcp}"
  NETWORK_INTERFACE="${PVE_THIN_CLIENT_PRESET_NETWORK_INTERFACE:-eth0}"
  NETWORK_STATIC_ADDRESS="${PVE_THIN_CLIENT_PRESET_NETWORK_STATIC_ADDRESS:-}"
  NETWORK_STATIC_PREFIX="${PVE_THIN_CLIENT_PRESET_NETWORK_STATIC_PREFIX:-24}"
  NETWORK_GATEWAY="${PVE_THIN_CLIENT_PRESET_NETWORK_GATEWAY:-}"
  NETWORK_DNS_SERVERS="${PVE_THIN_CLIENT_PRESET_NETWORK_DNS_SERVERS:-1.1.1.1 8.8.8.8}"
  PROXMOX_SCHEME="${PVE_THIN_CLIENT_PRESET_PROXMOX_SCHEME:-https}"
  PROXMOX_HOST="${PVE_THIN_CLIENT_PRESET_PROXMOX_HOST:-}"
  PROXMOX_PORT="${PVE_THIN_CLIENT_PRESET_PROXMOX_PORT:-8006}"
  PROXMOX_NODE="${PVE_THIN_CLIENT_PRESET_PROXMOX_NODE:-}"
  PROXMOX_VMID="${PVE_THIN_CLIENT_PRESET_PROXMOX_VMID:-}"
  PROXMOX_REALM="${PVE_THIN_CLIENT_PRESET_PROXMOX_REALM:-pam}"
  PROXMOX_VERIFY_TLS="${PVE_THIN_CLIENT_PRESET_PROXMOX_VERIFY_TLS:-0}"
  MOONLIGHT_BIN="${PVE_THIN_CLIENT_PRESET_MOONLIGHT_BIN:-moonlight}"
  MOONLIGHT_RESOLUTION="${PVE_THIN_CLIENT_PRESET_MOONLIGHT_RESOLUTION:-1080}"
  MOONLIGHT_FPS="${PVE_THIN_CLIENT_PRESET_MOONLIGHT_FPS:-60}"
  MOONLIGHT_BITRATE="${PVE_THIN_CLIENT_PRESET_MOONLIGHT_BITRATE:-20000}"
  MOONLIGHT_VIDEO_CODEC="${PVE_THIN_CLIENT_PRESET_MOONLIGHT_VIDEO_CODEC:-H.264}"
  MOONLIGHT_VIDEO_DECODER="${PVE_THIN_CLIENT_PRESET_MOONLIGHT_VIDEO_DECODER:-auto}"
  MOONLIGHT_AUDIO_CONFIG="${PVE_THIN_CLIENT_PRESET_MOONLIGHT_AUDIO_CONFIG:-stereo}"
  MOONLIGHT_ABSOLUTE_MOUSE="${PVE_THIN_CLIENT_PRESET_MOONLIGHT_ABSOLUTE_MOUSE:-1}"
  MOONLIGHT_QUIT_AFTER="${PVE_THIN_CLIENT_PRESET_MOONLIGHT_QUIT_AFTER:-0}"
  SUNSHINE_API_URL="${PVE_THIN_CLIENT_PRESET_SUNSHINE_API_URL:-}"
}

apply_preset_mode() {
  local selected_mode="$1"

  apply_preset_defaults
  MODE="$selected_mode"
  CONNECTION_METHOD="direct"
  SPICE_URL=""
  NOVNC_URL=""
  DCV_URL=""
  MOONLIGHT_HOST=""
  MOONLIGHT_APP="Desktop"
  CONNECTION_USERNAME=""
  CONNECTION_PASSWORD=""
  CONNECTION_TOKEN=""
  SUNSHINE_USERNAME=""
  SUNSHINE_PASSWORD=""
  SUNSHINE_PIN=""

  case "$selected_mode" in
    MOONLIGHT)
      MOONLIGHT_HOST="${PVE_THIN_CLIENT_PRESET_MOONLIGHT_HOST:-}"
      MOONLIGHT_APP="${PVE_THIN_CLIENT_PRESET_MOONLIGHT_APP:-Desktop}"
      SUNSHINE_API_URL="${PVE_THIN_CLIENT_PRESET_SUNSHINE_API_URL:-}"
      SUNSHINE_USERNAME="${PVE_THIN_CLIENT_PRESET_SUNSHINE_USERNAME:-}"
      SUNSHINE_PASSWORD="${PVE_THIN_CLIENT_PRESET_SUNSHINE_PASSWORD:-}"
      SUNSHINE_PIN="${PVE_THIN_CLIENT_PRESET_SUNSHINE_PIN:-}"
      ;;
    SPICE)
      CONNECTION_USERNAME="${PVE_THIN_CLIENT_PRESET_SPICE_USERNAME:-${PVE_THIN_CLIENT_PRESET_PROXMOX_USERNAME:-}}"
      CONNECTION_PASSWORD="${PVE_THIN_CLIENT_PRESET_SPICE_PASSWORD:-${PVE_THIN_CLIENT_PRESET_PROXMOX_PASSWORD:-}}"
      CONNECTION_TOKEN="${PVE_THIN_CLIENT_PRESET_SPICE_TOKEN:-${PVE_THIN_CLIENT_PRESET_PROXMOX_TOKEN:-}}"
      if [[ -n "${PVE_THIN_CLIENT_PRESET_SPICE_URL:-}" ]]; then
        CONNECTION_METHOD="${PVE_THIN_CLIENT_PRESET_SPICE_METHOD:-direct}"
        SPICE_URL="${PVE_THIN_CLIENT_PRESET_SPICE_URL}"
      else
        CONNECTION_METHOD="proxmox-ticket"
      fi
      ;;
    NOVNC)
      NOVNC_URL="${PVE_THIN_CLIENT_PRESET_NOVNC_URL:-}"
      CONNECTION_USERNAME="${PVE_THIN_CLIENT_PRESET_NOVNC_USERNAME:-${PVE_THIN_CLIENT_PRESET_PROXMOX_USERNAME:-}}"
      CONNECTION_PASSWORD="${PVE_THIN_CLIENT_PRESET_NOVNC_PASSWORD:-${PVE_THIN_CLIENT_PRESET_PROXMOX_PASSWORD:-}}"
      CONNECTION_TOKEN="${PVE_THIN_CLIENT_PRESET_NOVNC_TOKEN:-${PVE_THIN_CLIENT_PRESET_PROXMOX_TOKEN:-}}"
      ;;
    DCV)
      DCV_URL="${PVE_THIN_CLIENT_PRESET_DCV_URL:-}"
      CONNECTION_USERNAME="${PVE_THIN_CLIENT_PRESET_DCV_USERNAME:-}"
      CONNECTION_PASSWORD="${PVE_THIN_CLIENT_PRESET_DCV_PASSWORD:-}"
      CONNECTION_TOKEN="${PVE_THIN_CLIENT_PRESET_DCV_TOKEN:-}"
      ;;
    *)
      echo "Unsupported preset mode: $selected_mode" >&2
      exit 1
      ;;
  esac
}

load_install_profile() {
  if [[ "$PRESET_ACTIVE" == "1" ]]; then
    if [[ -n "$MODE" ]]; then
      mode_is_available "$MODE" || {
        echo "Requested mode '$MODE' is not available in the bundled preset." >&2
        exit 1
      }
    else
      MODE="${PVE_THIN_CLIENT_PRESET_DEFAULT_MODE:-}"
      if [[ -n "$MODE" ]]; then
        mode_is_available "$MODE" || MODE=""
      fi
      if [[ -z "$MODE" ]]; then
        MODE="$(choose_streaming_mode_from_preset)"
      fi
    fi
    apply_preset_mode "$MODE"
    return 0
  fi

  load_profile
}

prefix_to_netmask() {
  python3 - "$1" <<'PY'
import ipaddress
import sys

prefix = int(sys.argv[1])
network = ipaddress.ip_network(f"0.0.0.0/{prefix}")
print(network.netmask)
PY
}

boot_ip_arg() {
  if [[ "$NETWORK_MODE" == "dhcp" ]]; then
    printf 'ip=dhcp'
    return 0
  fi

  local netmask
  netmask="$(prefix_to_netmask "$NETWORK_STATIC_PREFIX")"
  printf 'ip=%s::%s:%s:%s:%s:none' \
    "$NETWORK_STATIC_ADDRESS" \
    "$NETWORK_GATEWAY" \
    "$netmask" \
    "$HOSTNAME_VALUE" \
    "$NETWORK_INTERFACE"
}

write_grub_cfg() {
  local root_uuid="$1"
  local ip_arg
  ip_arg="$(boot_ip_arg)"

  cat > "$TARGET_MOUNT/boot/grub/grub.cfg" <<EOF
insmod all_video
insmod gfxterm
insmod jpeg
terminal_output gfxterm
if background_image /boot/grub/background.jpg; then
  set color_normal=white/black
  set color_highlight=black/light-gray
fi
set default=0
set timeout=4

menuentry 'PVE Thin Client' {
  search --no-floppy --fs-uuid --set=root $root_uuid
  linux /live/vmlinuz boot=live components username=thinclient hostname=$HOSTNAME_VALUE live-media=/dev/disk/by-uuid/$root_uuid quiet loglevel=3 systemd.show_status=0 vt.global_cursor_default=0 splash $ip_arg pve_thin_client.mode=runtime
  initrd /live/initrd.img
}
EOF
}

copy_assets() {
  install -d -m 0755 "$TARGET_MOUNT/live" "$TARGET_MOUNT/pve-thin-client" "$STATE_DIR"
  install -m 0644 "$LIVE_ASSET_DIR/vmlinuz" "$TARGET_MOUNT/live/vmlinuz"
  install -m 0644 "$LIVE_ASSET_DIR/initrd.img" "$TARGET_MOUNT/live/initrd.img"
  install -m 0644 "$LIVE_ASSET_DIR/filesystem.squashfs" "$TARGET_MOUNT/live/filesystem.squashfs"
  ln -sfn ../live "$TARGET_MOUNT/pve-thin-client/live"
  if [[ -f "$GRUB_BACKGROUND_SRC" ]]; then
    install -D -m 0644 "$GRUB_BACKGROUND_SRC" "$TARGET_MOUNT/boot/grub/background.jpg"
  fi
  MODE="$MODE" \
  CONNECTION_METHOD="$CONNECTION_METHOD" \
  PROFILE_NAME="$PROFILE_NAME" \
  RUNTIME_USER="$RUNTIME_USER" \
  HOSTNAME_VALUE="$HOSTNAME_VALUE" \
  AUTOSTART="$AUTOSTART" \
  NETWORK_MODE="$NETWORK_MODE" \
  NETWORK_INTERFACE="$NETWORK_INTERFACE" \
  NETWORK_STATIC_ADDRESS="$NETWORK_STATIC_ADDRESS" \
  NETWORK_STATIC_PREFIX="$NETWORK_STATIC_PREFIX" \
  NETWORK_GATEWAY="$NETWORK_GATEWAY" \
  NETWORK_DNS_SERVERS="$NETWORK_DNS_SERVERS" \
  SPICE_URL="$SPICE_URL" \
  NOVNC_URL="$NOVNC_URL" \
  DCV_URL="$DCV_URL" \
  MOONLIGHT_HOST="$MOONLIGHT_HOST" \
  MOONLIGHT_APP="$MOONLIGHT_APP" \
  REMOTE_VIEWER_BIN="$REMOTE_VIEWER_BIN" \
  BROWSER_BIN="$BROWSER_BIN" \
  BROWSER_FLAGS="$BROWSER_FLAGS" \
  DCV_VIEWER_BIN="$DCV_VIEWER_BIN" \
  MOONLIGHT_BIN="$MOONLIGHT_BIN" \
  MOONLIGHT_RESOLUTION="$MOONLIGHT_RESOLUTION" \
  MOONLIGHT_FPS="$MOONLIGHT_FPS" \
  MOONLIGHT_BITRATE="$MOONLIGHT_BITRATE" \
  MOONLIGHT_VIDEO_CODEC="$MOONLIGHT_VIDEO_CODEC" \
  MOONLIGHT_VIDEO_DECODER="$MOONLIGHT_VIDEO_DECODER" \
  MOONLIGHT_AUDIO_CONFIG="$MOONLIGHT_AUDIO_CONFIG" \
  MOONLIGHT_ABSOLUTE_MOUSE="$MOONLIGHT_ABSOLUTE_MOUSE" \
  MOONLIGHT_QUIT_AFTER="$MOONLIGHT_QUIT_AFTER" \
  SUNSHINE_API_URL="$SUNSHINE_API_URL" \
  PROXMOX_SCHEME="$PROXMOX_SCHEME" \
  PROXMOX_HOST="$PROXMOX_HOST" \
  PROXMOX_PORT="$PROXMOX_PORT" \
  PROXMOX_NODE="$PROXMOX_NODE" \
  PROXMOX_VMID="$PROXMOX_VMID" \
  PROXMOX_REALM="$PROXMOX_REALM" \
  PROXMOX_VERIFY_TLS="$PROXMOX_VERIFY_TLS" \
  CONNECTION_USERNAME="$CONNECTION_USERNAME" \
  CONNECTION_PASSWORD="$CONNECTION_PASSWORD" \
  CONNECTION_TOKEN="$CONNECTION_TOKEN" \
  SUNSHINE_USERNAME="$SUNSHINE_USERNAME" \
  SUNSHINE_PASSWORD="$SUNSHINE_PASSWORD" \
  SUNSHINE_PIN="$SUNSHINE_PIN" \
  "$ROOT_DIR/installer/write-config.sh" "$STATE_DIR"
}

install_bootloader() {
  local target_disk="$1"
  grub-install --target=i386-pc --boot-directory="$TARGET_MOUNT/boot" "$target_disk"
  grub-install \
    --target=x86_64-efi \
    --efi-directory="$EFI_MOUNT" \
    --boot-directory="$TARGET_MOUNT/boot" \
    --removable \
    --no-nvram
}

main() {
  local target_disk bios_part boot_part root_part root_uuid

  parse_args "$@"
  load_embedded_preset
  if [[ "$PRINT_TARGETS_JSON" == "1" ]]; then
    print_target_disks_json
    return 0
  fi
  if [[ "$PRINT_PRESET_JSON" == "1" ]]; then
    print_preset_json
    return 0
  fi
  if [[ "$PRINT_PRESET_SUMMARY" == "1" ]]; then
    print_preset_summary
    return 0
  fi

  require_root "$@"
  require_tools

  if [[ ! -f "$LIVE_ASSET_DIR/filesystem.squashfs" ]]; then
    echo "Live installer assets were not found under $LIVE_ASSET_DIR" >&2
    exit 1
  fi

  load_install_profile
  target_disk="$(choose_target_disk)"
  [[ -n "$target_disk" ]] || exit 0
  confirm_wipe "$target_disk" || exit 0

  bios_part="$(partition_suffix "$target_disk" 1)"
  boot_part="$(partition_suffix "$target_disk" 2)"
  root_part="$(partition_suffix "$target_disk" 3)"

  wipefs -a "$target_disk"
  parted -s "$target_disk" mklabel gpt
  parted -s "$target_disk" mkpart BIOSBOOT 1MiB 3MiB
  parted -s "$target_disk" set 1 bios_grub on
  parted -s "$target_disk" mkpart ESP fat32 3MiB 515MiB
  parted -s "$target_disk" set 2 esp on
  parted -s "$target_disk" set 2 boot on
  parted -s "$target_disk" mkpart primary ext4 515MiB 100%
  partprobe "$target_disk"
  udevadm settle

  [[ -b "$bios_part" ]] || {
    echo "BIOS boot partition could not be created on $target_disk" >&2
    exit 1
  }

  mkfs.vfat -F 32 -n PVETHINBOOT "$boot_part"
  mkfs.ext4 -F -L PVETHINROOT "$root_part"

  install -d -m 0755 "$TARGET_MOUNT" "$EFI_MOUNT"
  mount "$root_part" "$TARGET_MOUNT"
  install -d -m 0755 "$EFI_MOUNT" "$TARGET_MOUNT/boot/grub"
  mount "$boot_part" "$EFI_MOUNT"

  copy_assets
  root_uuid="$(blkid -s UUID -o value "$root_part")"
  write_grub_cfg "$root_uuid"
  install_bootloader "$target_disk"
  sync

  if command -v whiptail >/dev/null 2>&1; then
    whiptail --title "PVE Thin Client Installation" --msgbox \
      "Installation complete. Remove the USB stick and boot from the target disk." 12 72
  else
    echo "Installation complete. Remove the USB stick and boot from the target disk."
  fi
}

main "$@"
