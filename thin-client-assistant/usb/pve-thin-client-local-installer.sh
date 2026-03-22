#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIVE_MEDIUM_DEFAULT="${LIVE_MEDIUM:-/run/live/medium}"
LIVE_MEDIUM=""
TEMP_LIVE_MEDIUM_MOUNT=""
TEMP_LOG_PERSIST_MOUNT=""
REMOTE_PAYLOAD_TMP_DIR=""
TARGET_MOUNT="/mnt/pve-thin-client-target"
EFI_MOUNT="$TARGET_MOUNT/boot/efi"
LIVE_ASSET_DIR=""
INSTALL_LIVE_ASSET_DIR=""
INSTALL_ROOT_DIR="$ROOT_DIR"
STATE_DIR="$TARGET_MOUNT/pve-thin-client/state"
PRESET_FILE=""
PRESET_ACTIVE="0"
LOG_DIR="${PVE_THIN_CLIENT_LOG_DIR:-/tmp/pve-thin-client-logs}"
LOG_FILE="$LOG_DIR/local-installer.log"
RUNTIME_SNAPSHOT_LOG="$LOG_DIR/runtime-snapshot.log"
LOG_PERSIST_DIR=""
LOG_SESSION_ID="${PVE_THIN_CLIENT_LOG_SESSION_ID:-}"
CACHED_STATE_DIR="/run/pve-thin-client"
CACHED_PRESET_FILE="$CACHED_STATE_DIR/bundled-preset.env"
CACHED_MANIFEST_FILE="$CACHED_STATE_DIR/usb-manifest.json"
CACHED_PRESET_SOURCE_FILE="$CACHED_STATE_DIR/bundled-preset.source"
PRESET_SOURCE="unresolved"
GRUB_BACKGROUND_SRC="$ROOT_DIR/usb/assets/grub-background.jpg"
TARGET_DISK_OVERRIDE=""
ASSUME_YES="0"
AUTO_INSTALL="0"
PRINT_TARGETS_JSON="0"
PRINT_PRESET_JSON="0"
PRINT_PRESET_SUMMARY="0"
PRINT_DEBUG_JSON="0"
CACHE_PRESET_ONLY="0"
LIST_PROXMOX_VMS_JSON="0"
CACHE_PROXMOX_VM_PRESET="0"
CLEAR_CACHED_PRESET="0"
PROXMOX_API_HOST=""
PROXMOX_API_SCHEME="https"
PROXMOX_API_PORT="8006"
PROXMOX_API_VERIFY_TLS="0"
PROXMOX_API_USERNAME=""
PROXMOX_API_PASSWORD=""
PROXMOX_API_NODE=""
PROXMOX_API_VMID=""

MODE="${MODE:-MOONLIGHT}"
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
MOONLIGHT_RESOLUTION="auto"
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
PROXMOX_API_HELPER="$SCRIPT_DIR/pve-thin-client-proxmox-api.py"

cleanup() {
  persist_logs_to_medium
  if [[ -n "$REMOTE_PAYLOAD_TMP_DIR" && -d "$REMOTE_PAYLOAD_TMP_DIR" ]]; then
    rm -rf "$REMOTE_PAYLOAD_TMP_DIR" >/dev/null 2>&1 || true
  fi
  if [[ -n "$TEMP_LOG_PERSIST_MOUNT" ]]; then
    privileged_run umount "$TEMP_LOG_PERSIST_MOUNT" >/dev/null 2>&1 || true
    rmdir "$TEMP_LOG_PERSIST_MOUNT" >/dev/null 2>&1 || true
  fi
  if [[ -n "$TEMP_LIVE_MEDIUM_MOUNT" ]]; then
    privileged_run umount "$TEMP_LIVE_MEDIUM_MOUNT" >/dev/null 2>&1 || true
    rmdir "$TEMP_LIVE_MEDIUM_MOUNT" >/dev/null 2>&1 || true
  fi
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
  for tool in grub-install mkfs.vfat mkfs.ext4 parted lsblk blkid findmnt python3 curl tar; do
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
      python3 \
      curl \
      ca-certificates \
      tar
  fi
}

setup_logging() {
  mkdir -p "$LOG_DIR"
  if [[ -z "$LOG_SESSION_ID" ]]; then
    LOG_SESSION_ID="$(basename "$LOG_DIR")"
  fi
  touch "$LOG_FILE"
  chmod 0644 "$LOG_FILE" >/dev/null 2>&1 || true
}

log_msg() {
  setup_logging
  printf '[%s] %s\n' "$(date -Is 2>/dev/null || date)" "$*" >>"$LOG_FILE"
}

log_runtime_snapshot() {
  setup_logging
  {
    echo "=== date ==="
    date -Is 2>/dev/null || date
    echo
    echo "=== /proc/cmdline ==="
    cat /proc/cmdline 2>/dev/null || true
    echo
    echo "=== findmnt ==="
    findmnt -rn -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || true
    echo
    echo "=== lsblk ==="
    lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,UUID,RM,TRAN,MOUNTPOINTS 2>/dev/null || true
    echo
    echo "=== blkid ==="
    blkid 2>/dev/null || true
  } >>"$RUNTIME_SNAPSHOT_LOG" 2>&1 || true
}

persist_logs_to_medium() {
  local persist_root=""
  local session_dir=""
  local marker_file=""
  local persist_parent=""

  setup_logging
  LOG_PERSIST_DIR=""

  if ! running_from_live_environment; then
    log_msg "persist_logs_to_medium: skipping because current session is not a live boot"
    return 0
  fi

  if [[ -z "$LIVE_MEDIUM" ]]; then
    LIVE_MEDIUM="$(resolve_live_medium || true)"
  fi

  if [[ -n "$LIVE_MEDIUM" ]] && [[ -d "$LIVE_MEDIUM/pve-thin-client" ]] && [[ -w "$LIVE_MEDIUM/pve-thin-client" ]]; then
    persist_root="$LIVE_MEDIUM"
  fi

  if [[ -z "$persist_root" ]]; then
    persist_root="$(mount_writable_live_medium_for_logs || true)"
  fi

  if [[ -n "$persist_root" ]]; then
    session_dir="$(sanitize_log_session_id)"
    persist_parent="$persist_root/pve-thin-client/logs"
    if mkdir -p "$persist_parent/$session_dir" >/dev/null 2>&1 && [[ -w "$persist_parent/$session_dir" ]]; then
      LOG_PERSIST_DIR="$persist_parent/$session_dir"
    else
      log_msg "persist_logs_to_medium: unable to prepare writable log directory under $persist_root"
    fi
  fi

  if [[ -n "$LOG_PERSIST_DIR" ]]; then
    cp -a "$LOG_DIR/." "$LOG_PERSIST_DIR/" 2>/dev/null || true
    printf '%s\n' "$session_dir" >"$persist_parent/LATEST.txt" 2>/dev/null || true
    marker_file="$LOG_PERSIST_DIR/session.env"
    {
      printf 'LOG_SESSION_ID=%s\n' "$session_dir"
      printf 'LOG_DIR=%s\n' "$LOG_DIR"
      printf 'LIVE_MEDIUM=%s\n' "$LIVE_MEDIUM"
      printf 'PRESET_FILE=%s\n' "$PRESET_FILE"
      printf 'PRESET_SOURCE=%s\n' "$PRESET_SOURCE"
      printf 'DATE=%s\n' "$(date -Is 2>/dev/null || date)"
    } >"$marker_file" 2>/dev/null || true
    return 0
  fi

  log_msg "persist_logs_to_medium: live medium for log persistence is still unavailable"
  return 0
}

have_passwordless_sudo() {
  command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1
}

privileged_run() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
    return
  fi

  if have_passwordless_sudo; then
    sudo -n "$@"
    return
  fi

  return 1
}

running_from_live_environment() {
  if [[ -d /run/live/medium || -d /lib/live/mount/medium ]]; then
    return 0
  fi

  if [[ -r /proc/cmdline ]]; then
    grep -Eq '(^| )boot=live( |$)|(^| )pve_thin_client\.mode=installer( |$)' /proc/cmdline 2>/dev/null
    return $?
  fi

  return 1
}

sanitize_log_session_id() {
  local raw="${LOG_SESSION_ID:-$(basename "$LOG_DIR")}"
  raw="${raw:-session}"
  printf '%s\n' "$raw" | tr -cs 'A-Za-z0-9._-' '-'
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

candidate_live_mounts() {
  local target
  local -a candidates=("$LIVE_MEDIUM_DEFAULT" "/run/live/medium" "/lib/live/mount/medium")

  if command -v findmnt >/dev/null 2>&1; then
    while IFS= read -r target; do
      [[ -n "$target" ]] || continue
      candidates+=("$target")
    done < <(findmnt -rn -o TARGET 2>/dev/null || true)
  fi

  for target in "${candidates[@]}"; do
    [[ -d "$target" ]] || continue
    log_msg "candidate live mount: $target"
    printf '%s\n' "$target"
  done
}

candidate_live_asset_dir() {
  local target="$1"

  if [[ -f "$target/pve-thin-client/live/filesystem.squashfs" && -f "$target/pve-thin-client/live/vmlinuz" && -f "$target/pve-thin-client/live/initrd.img" ]]; then
    printf '%s\n' "$target/pve-thin-client/live"
    return 0
  fi

  if [[ -f "$target/filesystem.squashfs" && -f "$target/vmlinuz" && -f "$target/initrd.img" ]]; then
    printf '%s\n' "$target"
    return 0
  fi

  return 1
}

candidate_preset_path() {
  local target="$1"

  if [[ -f "$target/pve-thin-client/preset.env" ]]; then
    printf '%s\n' "$target/pve-thin-client/preset.env"
    return 0
  fi

  if candidate_live_asset_dir "$target" >/dev/null 2>&1 && [[ -f "$target/preset.env" ]]; then
    printf '%s\n' "$target/preset.env"
    return 0
  fi

  return 1
}

candidate_manifest_path() {
  local target="$1"

  if [[ -f "$target/.pve-dcv-usb-manifest.json" ]]; then
    printf '%s\n' "$target/.pve-dcv-usb-manifest.json"
    return 0
  fi

  if candidate_live_asset_dir "$target" >/dev/null 2>&1 && [[ -f "$target/.pve-dcv-usb-manifest.json" ]]; then
    printf '%s\n' "$target/.pve-dcv-usb-manifest.json"
    return 0
  fi

  return 1
}

resolve_payload_url_from_manifest() {
  local manifest_file=""

  if [[ -n "$LIVE_MEDIUM" ]]; then
    manifest_file="$(candidate_manifest_path "$LIVE_MEDIUM" 2>/dev/null || true)"
  fi
  if [[ -z "$manifest_file" && -f "$CACHED_MANIFEST_FILE" ]]; then
    manifest_file="$CACHED_MANIFEST_FILE"
  fi
  [[ -n "$manifest_file" && -f "$manifest_file" ]] || return 1

  python3 - "$manifest_file" <<'PY'
import json
import sys
from urllib.parse import urlparse

manifest_file = sys.argv[1]
try:
    payload = json.load(open(manifest_file, "r", encoding="utf-8"))
except Exception:
    raise SystemExit(1)

source = str(payload.get("payload_source", "")).strip()
if not source:
    raise SystemExit(1)

parsed = urlparse(source)
if parsed.scheme not in ("http", "https"):
    raise SystemExit(1)

print(source)
PY
}

download_install_payload_from_server() {
  local payload_url=""
  local payload_name=""
  local tmp_dir=""
  local tarball=""
  local checksum_url=""
  local checksum_file=""
  local asset_dir=""
  local remote_root_dir=""

  payload_url="${PVE_THIN_CLIENT_INSTALL_PAYLOAD_URL:-}"
  if [[ -z "$payload_url" ]]; then
    payload_url="$(resolve_payload_url_from_manifest 2>/dev/null || true)"
  fi
  if [[ -z "$payload_url" ]]; then
    log_msg "download_install_payload_from_server: no http(s) payload URL available in manifest; using bundled USB payload"
    return 1
  fi

  payload_name="$(basename "$payload_url")"
  [[ -n "$payload_name" ]] || {
    log_msg "download_install_payload_from_server: invalid payload URL basename: $payload_url"
    return 1
  }

  tmp_dir="$(mktemp -d /tmp/pve-thin-client-install-payload.XXXXXX)"
  tarball="$tmp_dir/$payload_name"
  log_msg "download_install_payload_from_server: downloading $payload_url"
  if ! curl --fail --show-error --location --retry 3 --retry-delay 2 "$payload_url" -o "$tarball"; then
    log_msg "download_install_payload_from_server: payload download failed from $payload_url"
    rm -rf "$tmp_dir" >/dev/null 2>&1 || true
    return 1
  fi

  checksum_url="${payload_url%/*}/SHA256SUMS"
  checksum_file="$tmp_dir/SHA256SUMS"
  if curl --fail --silent --location --retry 2 --retry-delay 1 "$checksum_url" -o "$checksum_file"; then
    if grep -F " ${payload_name}" "$checksum_file" >"$tmp_dir/payload.sha256"; then
      if ! ( cd "$tmp_dir" && sha256sum -c payload.sha256 >/dev/null ); then
        log_msg "download_install_payload_from_server: payload checksum mismatch for $payload_name"
        rm -rf "$tmp_dir" >/dev/null 2>&1 || true
        return 1
      fi
    fi
  else
    log_msg "download_install_payload_from_server: unable to download companion SHA256SUMS from $checksum_url (continuing)"
  fi

  if ! tar -xzf "$tarball" -C "$tmp_dir"; then
    log_msg "download_install_payload_from_server: failed to extract $tarball"
    rm -rf "$tmp_dir" >/dev/null 2>&1 || true
    return 1
  fi

  asset_dir="$tmp_dir/dist/pve-thin-client-installer/live"
  remote_root_dir="$tmp_dir/thin-client-assistant"
  if [[ ! -f "$asset_dir/vmlinuz" || ! -f "$asset_dir/initrd.img" || ! -f "$asset_dir/filesystem.squashfs" ]]; then
    log_msg "download_install_payload_from_server: extracted payload missing live assets in $asset_dir"
    rm -rf "$tmp_dir" >/dev/null 2>&1 || true
    return 1
  fi

  if [[ -f "$asset_dir/SHA256SUMS" ]]; then
    if ! ( cd "$asset_dir" && sha256sum -c SHA256SUMS >/dev/null ); then
      log_msg "download_install_payload_from_server: live asset checksum validation failed for extracted payload"
      rm -rf "$tmp_dir" >/dev/null 2>&1 || true
      return 1
    fi
  fi

  REMOTE_PAYLOAD_TMP_DIR="$tmp_dir"
  INSTALL_LIVE_ASSET_DIR="$asset_dir"
  if [[ -x "$remote_root_dir/installer/write-config.sh" ]]; then
    INSTALL_ROOT_DIR="$remote_root_dir"
  else
    INSTALL_ROOT_DIR="$ROOT_DIR"
  fi
  log_msg "download_install_payload_from_server: using remote payload assets from $INSTALL_LIVE_ASSET_DIR"
  return 0
}

prepare_install_assets() {
  INSTALL_LIVE_ASSET_DIR="$LIVE_ASSET_DIR"
  INSTALL_ROOT_DIR="$ROOT_DIR"

  if download_install_payload_from_server; then
    return 0
  fi

  log_msg "prepare_install_assets: falling back to bundled USB payload assets under $LIVE_ASSET_DIR"
  return 0
}

cached_preset_source() {
  if [[ -f "$CACHED_PRESET_SOURCE_FILE" ]]; then
    head -n 1 "$CACHED_PRESET_SOURCE_FILE" 2>/dev/null || printf 'cache\n'
    return 0
  fi

  printf 'cache\n'
}

restore_preset_from_cmdline() {
  mkdir -p "$CACHED_STATE_DIR"

  if python3 - "$CACHED_PRESET_FILE" "$CACHED_PRESET_SOURCE_FILE" <<'PY'
import base64
import gzip
import re
import sys
from pathlib import Path

target = Path(sys.argv[1])
source = Path(sys.argv[2])
cmdline = Path("/proc/cmdline").read_text(encoding="utf-8").strip()

codec = ""
chunks = {}

for token in cmdline.split():
    if token.startswith("pve_thin_client.preset_codec="):
        codec = token.split("=", 1)[1]
        continue

    match = re.match(r"pve_thin_client\.preset_b64_(\d+)=([A-Za-z0-9_-]+)$", token)
    if match:
        chunks[int(match.group(1))] = match.group(2)
        continue

    if token.startswith("pve_thin_client.preset_b64="):
        chunks[0] = token.split("=", 1)[1]

if not chunks:
    raise SystemExit(1)

payload = "".join(chunks[index] for index in sorted(chunks))
payload += "=" * (-len(payload) % 4)
data = base64.urlsafe_b64decode(payload.encode("ascii"))

if codec in ("", "base64url"):
    decoded = data
elif codec in ("gzip+base64url", "gz+base64url", "gzip"):
    decoded = gzip.decompress(data)
else:
    raise SystemExit(f"unsupported preset codec: {codec}")

target.write_bytes(decoded)
target.chmod(0o644)
source.write_text("cmdline\n", encoding="utf-8")
PY
  then
    PRESET_SOURCE="cmdline"
    log_msg "restored bundled preset from kernel cmdline to $CACHED_PRESET_FILE"
    return 0
  fi

  return 1
}

candidate_live_devices() {
  local token value

  if [[ -r /proc/cmdline ]]; then
    for token in $(< /proc/cmdline); do
      case "$token" in
        live-media=*)
          value="${token#live-media=}"
          case "$value" in
            /dev/*)
              log_msg "candidate live device from cmdline: $value"
              printf '%s\n' "$value"
              ;;
            UUID=*)
              blkid -U "${value#UUID=}" 2>/dev/null || true
              ;;
            LABEL=*)
              blkid -L "${value#LABEL=}" 2>/dev/null || true
              ;;
          esac
          ;;
      esac
    done
  fi

  blkid -L PVETHIN 2>/dev/null || true
  lsblk -lnpo PATH,TYPE,FSTYPE,LABEL,RM,TRAN 2>/dev/null | awk '
    $2 == "part" {
      if ($4 == "PVETHIN" || $3 == "vfat" || $5 == "1" || $6 == "usb") {
        print $1
      }
    }
  '
}

mount_discovered_live_medium() {
  local device mount_dir

  privileged_run true >/dev/null 2>&1 || return 1

  while IFS= read -r device; do
    [[ -n "$device" ]] || continue
    [[ -b "$device" ]] || continue
    log_msg "probing live medium device: $device"
    mount_dir="$(mktemp -d /tmp/pve-live-medium.XXXXXX)"
    if privileged_run mount -o ro "$device" "$mount_dir" >/dev/null 2>&1; then
      if candidate_preset_path "$mount_dir" >/dev/null 2>&1 || candidate_live_asset_dir "$mount_dir" >/dev/null 2>&1; then
        TEMP_LIVE_MEDIUM_MOUNT="$mount_dir"
        log_msg "mounted live medium at $mount_dir from $device"
        printf '%s\n' "$mount_dir"
        return 0
      fi
      log_msg "mounted $device at $mount_dir but no preset/live payload found"
      privileged_run umount "$mount_dir" >/dev/null 2>&1 || true
    else
      log_msg "failed to mount candidate live medium: $device"
    fi
    rmdir "$mount_dir" >/dev/null 2>&1 || true
  done < <(candidate_live_devices | awk 'NF && !seen[$0]++')

  return 1
}

mount_writable_live_medium_for_logs() {
  local device mount_dir

  privileged_run true >/dev/null 2>&1 || return 1

  while IFS= read -r device; do
    [[ -n "$device" ]] || continue
    [[ -b "$device" ]] || continue
    mount_dir="$(mktemp -d /tmp/pve-live-logs.XXXXXX)"
    if privileged_run mount -o rw "$device" "$mount_dir" >/dev/null 2>&1; then
      if [[ -d "$mount_dir/pve-thin-client" ]]; then
        TEMP_LOG_PERSIST_MOUNT="$mount_dir"
        log_msg "mounted writable live medium for log persistence: $device -> $mount_dir"
        printf '%s\n' "$mount_dir"
        return 0
      fi
      privileged_run umount "$mount_dir" >/dev/null 2>&1 || true
    fi
    rmdir "$mount_dir" >/dev/null 2>&1 || true
  done < <(candidate_live_devices | awk 'NF && !seen[$0]++')

  log_msg "mount_writable_live_medium_for_logs: no writable live medium available"
  return 1
}

resolve_live_medium() {
  local target

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    if candidate_preset_path "$target" >/dev/null 2>&1 || candidate_live_asset_dir "$target" >/dev/null 2>&1; then
      log_msg "resolved live medium via existing mount: $target"
      printf '%s\n' "$target"
      return 0
    fi
  done < <(candidate_live_mounts | awk 'NF && !seen[$0]++')

  if mount_discovered_live_medium >/dev/null; then
    printf '%s\n' "$TEMP_LIVE_MEDIUM_MOUNT"
    return 0
  fi

  log_msg "unable to resolve live medium"
  return 1
}

resolve_preset_file() {
  local target

  restore_preset_from_cmdline || true

  if [[ -f "$CACHED_PRESET_FILE" ]]; then
    log_msg "resolved preset file via cached runtime state: $CACHED_PRESET_FILE"
    printf '%s\n' "$CACHED_PRESET_FILE"
    return 0
  fi

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    if target="$(candidate_preset_path "$target" 2>/dev/null || true)" && [[ -n "$target" ]]; then
      log_msg "resolved preset file via existing mount: $target"
      printf '%s\n' "$target"
      return 0
    fi
  done < <(candidate_live_mounts | awk 'NF && !seen[$0]++')

  if target="$(mount_discovered_live_medium 2>/dev/null || true)" && [[ -n "$target" ]]; then
    if target="$(candidate_preset_path "$target" 2>/dev/null || true)" && [[ -n "$target" ]]; then
      log_msg "resolved preset file via mounted device: $target"
      printf '%s\n' "$target"
      return 0
    fi
  fi

  log_msg "unable to resolve preset file"
  return 1
}

initialize_live_medium() {
  local live_asset_dir=""

  PRESET_FILE="$(resolve_preset_file || true)"
  if [[ -n "$PRESET_FILE" ]]; then
    if [[ "$PRESET_FILE" == "$CACHED_PRESET_FILE" ]]; then
      PRESET_SOURCE="$(cached_preset_source)"
      if [[ -n "$LIVE_MEDIUM" ]]; then
        live_asset_dir="$(candidate_live_asset_dir "$LIVE_MEDIUM" 2>/dev/null || true)"
      fi
    elif [[ "$PRESET_FILE" == */pve-thin-client/preset.env ]]; then
      LIVE_MEDIUM="$(dirname "$(dirname "$PRESET_FILE")")"
      live_asset_dir="$(candidate_live_asset_dir "$LIVE_MEDIUM" 2>/dev/null || true)"
    else
      PRESET_SOURCE="medium"
      live_asset_dir="$(dirname "$PRESET_FILE")"
      LIVE_MEDIUM="$live_asset_dir"
    fi
  fi

  if [[ -z "$LIVE_MEDIUM" ]]; then
    LIVE_MEDIUM="$(resolve_live_medium || true)"
  fi
  if [[ -z "$LIVE_MEDIUM" ]]; then
    LIVE_MEDIUM="$LIVE_MEDIUM_DEFAULT"
  fi

  if [[ -z "$live_asset_dir" ]]; then
    live_asset_dir="$(candidate_live_asset_dir "$LIVE_MEDIUM" 2>/dev/null || true)"
  fi
  if [[ -n "$live_asset_dir" ]]; then
    LIVE_ASSET_DIR="$live_asset_dir"
  else
    LIVE_ASSET_DIR="$LIVE_MEDIUM/pve-thin-client/live"
  fi
  if [[ -z "$PRESET_FILE" ]]; then
    PRESET_FILE="$(candidate_preset_path "$LIVE_MEDIUM" 2>/dev/null || true)"
  fi
  if [[ -z "$PRESET_FILE" && -f "$LIVE_MEDIUM/pve-thin-client/preset.env" ]]; then
    PRESET_FILE="$LIVE_MEDIUM/pve-thin-client/preset.env"
  fi
  if [[ -z "$PRESET_FILE" && -f "$LIVE_ASSET_DIR/preset.env" ]]; then
    PRESET_FILE="$LIVE_ASSET_DIR/preset.env"
  fi

  if [[ "$PRESET_SOURCE" == "unresolved" && -f "$PRESET_FILE" ]]; then
    PRESET_SOURCE="medium"
  fi

  log_msg "initialize_live_medium: LIVE_MEDIUM=$LIVE_MEDIUM"
  log_msg "initialize_live_medium: LIVE_ASSET_DIR=$LIVE_ASSET_DIR"
  log_msg "initialize_live_medium: PRESET_FILE=$PRESET_FILE"
  log_msg "initialize_live_medium: PRESET_SOURCE=$PRESET_SOURCE"
  persist_logs_to_medium
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
      --auto-install)
        AUTO_INSTALL="1"
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
      --print-debug-json)
        PRINT_DEBUG_JSON="1"
        shift
        ;;
      --cache-bundled-preset)
        CACHE_PRESET_ONLY="1"
        shift
        ;;
      --list-proxmox-vms-json)
        LIST_PROXMOX_VMS_JSON="1"
        shift
        ;;
      --cache-proxmox-vm-preset)
        CACHE_PROXMOX_VM_PRESET="1"
        shift
        ;;
      --clear-cached-preset)
        CLEAR_CACHED_PRESET="1"
        shift
        ;;
      --proxmox-api-host)
        PROXMOX_API_HOST="$2"
        shift 2
        ;;
      --proxmox-api-scheme)
        PROXMOX_API_SCHEME="$2"
        shift 2
        ;;
      --proxmox-api-port)
        PROXMOX_API_PORT="$2"
        shift 2
        ;;
      --proxmox-api-verify-tls)
        PROXMOX_API_VERIFY_TLS="$2"
        shift 2
        ;;
      --proxmox-api-username)
        PROXMOX_API_USERNAME="$2"
        shift 2
        ;;
      --proxmox-api-password)
        PROXMOX_API_PASSWORD="$2"
        shift 2
        ;;
      --proxmox-api-node)
        PROXMOX_API_NODE="$2"
        shift 2
        ;;
      --proxmox-api-vmid)
        PROXMOX_API_VMID="$2"
        shift 2
        ;;
      *)
        echo "Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done
}

require_proxmox_api_helper() {
  if [[ ! -x "$PROXMOX_API_HELPER" ]]; then
    echo "Missing Proxmox API helper: $PROXMOX_API_HELPER" >&2
    exit 1
  fi
}

validate_proxmox_api_args() {
  [[ -n "$PROXMOX_API_HOST" ]] || {
    echo "Missing --proxmox-api-host" >&2
    exit 1
  }
  [[ -n "$PROXMOX_API_USERNAME" ]] || {
    echo "Missing --proxmox-api-username" >&2
    exit 1
  }
  [[ -n "$PROXMOX_API_PASSWORD" ]] || {
    echo "Missing --proxmox-api-password" >&2
    exit 1
  }
}

clear_cached_preset() {
  rm -f "$CACHED_PRESET_FILE" "$CACHED_PRESET_SOURCE_FILE"
  log_msg "cleared cached preset state"
}

list_proxmox_vms_json() {
  require_proxmox_api_helper
  validate_proxmox_api_args

  "$PROXMOX_API_HELPER" \
    --host "$PROXMOX_API_HOST" \
    --scheme "$PROXMOX_API_SCHEME" \
    --port "$PROXMOX_API_PORT" \
    --verify-tls "$PROXMOX_API_VERIFY_TLS" \
    --username "$PROXMOX_API_USERNAME" \
    --password "$PROXMOX_API_PASSWORD" \
    list-vms-json
}

cache_proxmox_vm_preset() {
  local tmp_preset=""
  local helper_args=()

  require_proxmox_api_helper
  validate_proxmox_api_args
  [[ -n "$PROXMOX_API_VMID" ]] || {
    echo "Missing --proxmox-api-vmid" >&2
    exit 1
  }

  mkdir -p "$CACHED_STATE_DIR"
  tmp_preset="$(mktemp "$CACHED_STATE_DIR/proxmox-preset.XXXXXX")"
  helper_args=(
    --host "$PROXMOX_API_HOST"
    --scheme "$PROXMOX_API_SCHEME"
    --port "$PROXMOX_API_PORT"
    --verify-tls "$PROXMOX_API_VERIFY_TLS"
    --username "$PROXMOX_API_USERNAME"
    --password "$PROXMOX_API_PASSWORD"
    build-preset-env
    --vmid "$PROXMOX_API_VMID"
  )
  if [[ -n "$PROXMOX_API_NODE" ]]; then
    helper_args+=(--node "$PROXMOX_API_NODE")
  fi
  "$PROXMOX_API_HELPER" \
    "${helper_args[@]}" >"$tmp_preset"

  install -m 0644 "$tmp_preset" "$CACHED_PRESET_FILE"
  printf 'proxmox-api\n' >"$CACHED_PRESET_SOURCE_FILE"
  rm -f "$tmp_preset"
  PRESET_FILE="$CACHED_PRESET_FILE"
  PRESET_SOURCE="proxmox-api"
  PRESET_ACTIVE="0"
  load_embedded_preset || true
  log_msg "cached proxmox preset for vmid=$PROXMOX_API_VMID host=$PROXMOX_API_HOST source=$PRESET_SOURCE"
  persist_logs_to_medium
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

  if [[ "$AUTO_INSTALL" == "1" ]]; then
    live_disk="$(current_live_disk 2>/dev/null || true)"
    python3 - "$live_disk" <<'PY'
import shlex
import subprocess
import sys

live_disk = sys.argv[1]
candidates = []

for line in subprocess.check_output(
    ["lsblk", "-bn", "-P", "-o", "NAME,SIZE,TYPE,RM,TRAN"], text=True
).splitlines():
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
    candidates.append(
        {
            "device": device,
            "size": int(entry.get("SIZE", "0") or 0),
            "rm": entry.get("RM", "0"),
            "tran": (entry.get("TRAN", "") or "").lower(),
        }
    )

internal = [item for item in candidates if item["rm"] == "0" and item["tran"] != "usb"]
selection_pool = internal or candidates

if len(selection_pool) == 1:
    print(selection_pool[0]["device"])
    raise SystemExit(0)

if len(selection_pool) > 1:
    # Deterministic auto-pick: largest disk first, then lexical device order.
    by_priority = sorted(selection_pool, key=lambda item: (-item["size"], item["device"]))
    print(by_priority[0]["device"])
    raise SystemExit(0)

raise SystemExit(1)
PY
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
    whiptail --title "Thinclient Installation" --menu \
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
    whiptail --title "Thinclient Installation" --yesno \
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
  local attempt=1

  while (( attempt <= 6 )); do
    if [[ -f "$PRESET_FILE" ]]; then
      log_msg "loading bundled preset from $PRESET_FILE (attempt $attempt)"
      # shellcheck disable=SC1090
      source "$PRESET_FILE"
      PRESET_ACTIVE="1"
      log_msg "preset active: profile=${PVE_THIN_CLIENT_PRESET_PROFILE_NAME:-} vmid=${PVE_THIN_CLIENT_PRESET_PROXMOX_VMID:-} host=${PVE_THIN_CLIENT_PRESET_PROXMOX_HOST:-}"
      persist_logs_to_medium
      return 0
    fi

    log_msg "preset file missing on attempt $attempt: $PRESET_FILE"
    if (( attempt < 6 )); then
      sleep 1
      PRESET_FILE=""
      LIVE_MEDIUM=""
      initialize_live_medium
    fi
    attempt=$((attempt + 1))
  done

  log_msg "no bundled preset found after retries"
  return 1
}

cache_bundled_preset() {
  local manifest_file=""

  load_embedded_preset || true

  if [[ ! -f "$PRESET_FILE" ]]; then
    log_msg "cache_bundled_preset: no preset file available to cache"
    persist_logs_to_medium
    return 1
  fi

  if [[ "$PRESET_FILE" == "$CACHED_PRESET_FILE" ]]; then
    log_msg "cache_bundled_preset: preset is already cached at $CACHED_PRESET_FILE"
  else
    mkdir -p "$CACHED_STATE_DIR"
    install -m 0644 "$PRESET_FILE" "$CACHED_PRESET_FILE"
    printf 'medium\n' >"$CACHED_PRESET_SOURCE_FILE"
    log_msg "cache_bundled_preset: cached preset to $CACHED_PRESET_FILE from $PRESET_FILE"
  fi

  mkdir -p "$CACHED_STATE_DIR"

  if [[ -n "$LIVE_MEDIUM" ]]; then
    manifest_file="$(candidate_manifest_path "$LIVE_MEDIUM" 2>/dev/null || true)"
  fi
  if [[ -z "$manifest_file" && -f "$CACHED_MANIFEST_FILE" ]]; then
    manifest_file="$CACHED_MANIFEST_FILE"
  fi

  if [[ -n "$manifest_file" ]] && [[ -f "$manifest_file" ]]; then
    install -m 0644 "$manifest_file" "$CACHED_MANIFEST_FILE"
    log_msg "cache_bundled_preset: cached manifest to $CACHED_MANIFEST_FILE from $manifest_file"
  fi

  persist_logs_to_medium
  return 0
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
    echo "No VM preset is currently cached or bundled."
    return 0
  fi

  local available=()
  local mode
  for mode in MOONLIGHT SPICE NOVNC DCV; do
    if mode_is_available "$mode"; then
      available+=("$mode")
    fi
  done

  printf 'Active VM preset: %s\n' "${PVE_THIN_CLIENT_PRESET_VM_NAME:-${PVE_THIN_CLIENT_PRESET_PROFILE_NAME:-unnamed}}"
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

print_debug_json() {
  python3 - "$PRESET_ACTIVE" "$LIVE_MEDIUM_DEFAULT" "$LIVE_MEDIUM" "$LIVE_ASSET_DIR" "$PRESET_FILE" "$LOG_FILE" "$LOG_DIR" "$PRESET_SOURCE" "$CACHED_PRESET_FILE" "$(cached_preset_source)" "$(current_live_disk 2>/dev/null || true)" "$LOG_SESSION_ID" <<'PY'
import json
import os
import sys

(
    preset_active,
    live_medium_default,
    live_medium,
    live_asset_dir,
    preset_file,
    log_file,
    log_dir,
    preset_source,
    cached_preset_file,
    cached_preset_source,
    live_disk,
    log_session_id,
) = sys.argv[1:13]

payload = {
    "preset_active": preset_active == "1",
    "live_medium_default": live_medium_default,
    "live_medium": live_medium,
    "live_asset_dir": live_asset_dir,
    "preset_file": preset_file,
    "preset_exists": bool(preset_file and os.path.isfile(preset_file)),
    "log_file": log_file,
    "log_exists": bool(log_file and os.path.isfile(log_file)),
    "log_dir": log_dir,
    "log_dir_exists": bool(log_dir and os.path.isdir(log_dir)),
    "preset_source": preset_source,
    "cached_preset_file": cached_preset_file,
    "cached_preset_exists": bool(cached_preset_file and os.path.isfile(cached_preset_file)),
    "cached_preset_source": cached_preset_source,
    "live_disk": live_disk,
    "log_session_id": log_session_id,
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
    whiptail --title "Thinclient Installation" --menu \
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

available_mode_count() {
  local count=0
  local mode

  for mode in MOONLIGHT SPICE NOVNC DCV; do
    if mode_is_available "$mode"; then
      count=$((count + 1))
    fi
  done

  printf '%s\n' "$count"
}

first_available_mode() {
  local mode

  for mode in MOONLIGHT SPICE NOVNC DCV; do
    if mode_is_available "$mode"; then
      printf '%s\n' "$mode"
      return 0
    fi
  done

  return 1
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
  BEAGLE_MANAGER_URL="${PVE_THIN_CLIENT_PRESET_BEAGLE_MANAGER_URL:-}"
  BEAGLE_MANAGER_TOKEN="${PVE_THIN_CLIENT_PRESET_BEAGLE_MANAGER_TOKEN:-}"
  MOONLIGHT_BIN="${PVE_THIN_CLIENT_PRESET_MOONLIGHT_BIN:-moonlight}"
  MOONLIGHT_RESOLUTION="${PVE_THIN_CLIENT_PRESET_MOONLIGHT_RESOLUTION:-auto}"
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
        if [[ "$AUTO_INSTALL" == "1" ]]; then
          MODE="$(first_available_mode || true)"
          [[ -n "$MODE" ]] || {
            echo "No usable streaming mode is available in the bundled preset." >&2
            exit 1
          }
        else
          MODE="$(choose_streaming_mode_from_preset)"
        fi
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
  local irq_args_default=""
  local irq_args_safe="nomodeset irqpoll pci=nomsi noapic"
  local irq_args_legacy="nomodeset irqpoll noapic nolapic"
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

menuentry 'Thinclient' {
  search --no-floppy --fs-uuid --set=root $root_uuid
  linux /live/vmlinuz boot=live components username=thinclient hostname=$HOSTNAME_VALUE live-media=/dev/disk/by-uuid/$root_uuid live-media-path=/live live-media-timeout=10 ignore_uuid quiet loglevel=3 systemd.show_status=0 vt.global_cursor_default=0 splash $irq_args_default $ip_arg pve_thin_client.mode=runtime
  initrd /live/initrd.img
}

menuentry 'Thinclient (safe mode)' {
  search --no-floppy --fs-uuid --set=root $root_uuid
  linux /live/vmlinuz boot=live components username=thinclient hostname=$HOSTNAME_VALUE live-media=/dev/disk/by-uuid/$root_uuid live-media-path=/live live-media-timeout=10 ignore_uuid quiet loglevel=3 systemd.show_status=0 vt.global_cursor_default=0 splash $irq_args_safe $ip_arg pve_thin_client.mode=runtime
  initrd /live/initrd.img
}

menuentry 'Thinclient (legacy IRQ mode)' {
  search --no-floppy --fs-uuid --set=root $root_uuid
  linux /live/vmlinuz boot=live components username=thinclient hostname=$HOSTNAME_VALUE live-media=/dev/disk/by-uuid/$root_uuid live-media-path=/live live-media-timeout=10 ignore_uuid quiet loglevel=3 systemd.show_status=0 vt.global_cursor_default=0 splash $irq_args_legacy $ip_arg pve_thin_client.mode=runtime
  initrd /live/initrd.img
}
EOF
}

copy_assets() {
  install -d -m 0755 "$TARGET_MOUNT/live" "$TARGET_MOUNT/pve-thin-client" "$STATE_DIR"
  install -m 0644 "$INSTALL_LIVE_ASSET_DIR/vmlinuz" "$TARGET_MOUNT/live/vmlinuz"
  install -m 0644 "$INSTALL_LIVE_ASSET_DIR/initrd.img" "$TARGET_MOUNT/live/initrd.img"
  install -m 0644 "$INSTALL_LIVE_ASSET_DIR/filesystem.squashfs" "$TARGET_MOUNT/live/filesystem.squashfs"
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
  BEAGLE_MANAGER_URL="$BEAGLE_MANAGER_URL" \
  CONNECTION_USERNAME="$CONNECTION_USERNAME" \
  CONNECTION_PASSWORD="$CONNECTION_PASSWORD" \
  CONNECTION_TOKEN="$CONNECTION_TOKEN" \
  BEAGLE_MANAGER_TOKEN="$BEAGLE_MANAGER_TOKEN" \
  SUNSHINE_USERNAME="$SUNSHINE_USERNAME" \
  SUNSHINE_PASSWORD="$SUNSHINE_PASSWORD" \
  SUNSHINE_PIN="$SUNSHINE_PIN" \
  "$INSTALL_ROOT_DIR/installer/write-config.sh" "$STATE_DIR"
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

  setup_logging
  log_runtime_snapshot
  log_msg "starting local installer with args: $*"
  parse_args "$@"
  if [[ "$CLEAR_CACHED_PRESET" == "1" ]]; then
    clear_cached_preset
    return 0
  fi
  if [[ "$LIST_PROXMOX_VMS_JSON" == "1" ]]; then
    list_proxmox_vms_json
    return 0
  fi
  if [[ "$CACHE_PROXMOX_VM_PRESET" == "1" ]]; then
    cache_proxmox_vm_preset
    return 0
  fi
  initialize_live_medium
  if [[ "$CACHE_PRESET_ONLY" == "1" ]]; then
    cache_bundled_preset
    return 0
  fi
  load_embedded_preset || true
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
  if [[ "$PRINT_DEBUG_JSON" == "1" ]]; then
    print_debug_json
    return 0
  fi

  require_root "$@"
  require_tools

  load_install_profile
  target_disk="$(choose_target_disk)"
  [[ -n "$target_disk" ]] || exit 0
  confirm_wipe "$target_disk" || exit 0
  prepare_install_assets

  if [[ ! -f "$INSTALL_LIVE_ASSET_DIR/filesystem.squashfs" ]]; then
    log_msg "missing installer assets under $INSTALL_LIVE_ASSET_DIR"
    echo "Install assets were not found under $INSTALL_LIVE_ASSET_DIR" >&2
    exit 1
  fi

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
    whiptail --title "Thinclient Installation" --msgbox \
      "Installation complete. Remove the USB stick and boot from the target disk." 12 72
  else
    echo "Installation complete. Remove the USB stick and boot from the target disk."
  fi
}

main "$@"
