#!/usr/bin/env bash
set -euo pipefail

MODE="${MODE:-MOONLIGHT}"
CONNECTION_METHOD="${CONNECTION_METHOD:-}"
PROFILE_NAME="${PROFILE_NAME:-default}"
RUNTIME_USER="${RUNTIME_USER:-thinclient}"
HOSTNAME_VALUE="${HOSTNAME_VALUE:-pve-thin-client}"
AUTOSTART="${AUTOSTART:-1}"
NETWORK_MODE="${NETWORK_MODE:-dhcp}"
NETWORK_INTERFACE="${NETWORK_INTERFACE:-eth0}"
NETWORK_STATIC_ADDRESS="${NETWORK_STATIC_ADDRESS:-}"
NETWORK_STATIC_PREFIX="${NETWORK_STATIC_PREFIX:-24}"
NETWORK_GATEWAY="${NETWORK_GATEWAY:-}"
NETWORK_DNS_SERVERS="${NETWORK_DNS_SERVERS:-1.1.1.1 8.8.8.8}"
SPICE_URL="${SPICE_URL:-}"
NOVNC_URL="${NOVNC_URL:-}"
DCV_URL="${DCV_URL:-}"
MOONLIGHT_HOST="${MOONLIGHT_HOST:-}"
MOONLIGHT_APP="${MOONLIGHT_APP:-Desktop}"
MOONLIGHT_BIN="${MOONLIGHT_BIN:-moonlight}"
MOONLIGHT_RESOLUTION="${MOONLIGHT_RESOLUTION:-auto}"
MOONLIGHT_FPS="${MOONLIGHT_FPS:-60}"
MOONLIGHT_BITRATE="${MOONLIGHT_BITRATE:-20000}"
MOONLIGHT_VIDEO_CODEC="${MOONLIGHT_VIDEO_CODEC:-H.264}"
MOONLIGHT_VIDEO_DECODER="${MOONLIGHT_VIDEO_DECODER:-auto}"
MOONLIGHT_AUDIO_CONFIG="${MOONLIGHT_AUDIO_CONFIG:-stereo}"
MOONLIGHT_ABSOLUTE_MOUSE="${MOONLIGHT_ABSOLUTE_MOUSE:-1}"
MOONLIGHT_QUIT_AFTER="${MOONLIGHT_QUIT_AFTER:-0}"
SUNSHINE_API_URL="${SUNSHINE_API_URL:-}"
PROXMOX_SCHEME="${PROXMOX_SCHEME:-https}"
PROXMOX_HOST="${PROXMOX_HOST:-proxmox.example.internal}"
PROXMOX_PORT="${PROXMOX_PORT:-8006}"
PROXMOX_NODE="${PROXMOX_NODE:-pve01}"
PROXMOX_VMID="${PROXMOX_VMID:-100}"
PROXMOX_REALM="${PROXMOX_REALM:-pam}"
PROXMOX_VERIFY_TLS="${PROXMOX_VERIFY_TLS:-0}"
CONNECTION_USERNAME="${CONNECTION_USERNAME:-}"
CONNECTION_PASSWORD="${CONNECTION_PASSWORD:-}"
CONNECTION_TOKEN="${CONNECTION_TOKEN:-}"
SUNSHINE_USERNAME="${SUNSHINE_USERNAME:-}"
SUNSHINE_PASSWORD="${SUNSHINE_PASSWORD:-}"
SUNSHINE_PIN="${SUNSHINE_PIN:-1234}"

tty_printf() {
  printf '%s' "$*" >&2
}

tty_read() {
  local value=""
  IFS= read -r value || true
  printf '%s\n' "$value"
}

prompt() {
  local label="$1"
  local default_value="$2"
  local value=""
  tty_printf "$label [$default_value]: "
  value="$(tty_read)"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

prompt_secret() {
  local label="$1"
  local default_value="$2"
  local value=""
  read -r -s -p "$label [hidden]: " value || true
  printf '\n' >&2
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

choose_numeric() {
  local prompt_text="$1"
  shift
  local options=("$@")
  local answer
  while true; do
    tty_printf "$prompt_text"$'\n'
    tty_printf "Choice: "
    answer="$(tty_read)"
    if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#options[@]} )); then
      printf '%s\n' "${options[$((answer - 1))]}"
      return 0
    fi
  done
}

emit_var() {
  local key="$1"
  local value="$2"
  printf '%s=%q\n' "$key" "$value"
}

if [[ -z "$MODE" ]]; then
  MODE="MOONLIGHT"
fi

if [[ "$MODE" != "MOONLIGHT" ]]; then
  echo "Beagle OS supports only Moonlight + Sunshine." >&2
  exit 1
fi

if [[ -z "$CONNECTION_METHOD" ]]; then
  CONNECTION_METHOD="direct"
fi

PROFILE_NAME="$(prompt "Profile name" "$PROFILE_NAME")"
RUNTIME_USER="$(prompt "Runtime user" "$RUNTIME_USER")"
HOSTNAME_VALUE="$(prompt "Hostname" "$HOSTNAME_VALUE")"
AUTOSTART="$(prompt "Autostart after boot (1/0)" "$AUTOSTART")"
if [[ "$NETWORK_MODE" != "dhcp" && "$NETWORK_MODE" != "static" ]]; then
  NETWORK_MODE="$(choose_numeric $'Network mode:\n  1) DHCP\n  2) Static IPv4' dhcp static)"
fi
NETWORK_INTERFACE="$(prompt "Primary network interface" "$NETWORK_INTERFACE")"

if [[ "$NETWORK_MODE" == "static" ]]; then
  NETWORK_STATIC_ADDRESS="$(prompt "Static IPv4 address" "${NETWORK_STATIC_ADDRESS:-192.168.10.50}")"
  NETWORK_STATIC_PREFIX="$(prompt "Static IPv4 prefix" "$NETWORK_STATIC_PREFIX")"
  NETWORK_GATEWAY="$(prompt "Default gateway" "${NETWORK_GATEWAY:-192.168.10.1}")"
  NETWORK_DNS_SERVERS="$(prompt "DNS servers (space separated)" "$NETWORK_DNS_SERVERS")"
fi

MOONLIGHT_HOST="$(prompt "Moonlight target host" "${MOONLIGHT_HOST:-10.10.10.100}")"
MOONLIGHT_APP="$(prompt "Sunshine app name" "$MOONLIGHT_APP")"
SUNSHINE_API_URL="$(prompt "Sunshine API URL" "${SUNSHINE_API_URL:-https://${MOONLIGHT_HOST}:47990}")"
SUNSHINE_USERNAME="$(prompt "Sunshine admin username" "${SUNSHINE_USERNAME:-sunshine}")"
SUNSHINE_PASSWORD="$(prompt_secret "Sunshine admin password" "$SUNSHINE_PASSWORD")"
SUNSHINE_PIN="$(prompt "Moonlight pairing PIN" "$SUNSHINE_PIN")"
MOONLIGHT_RESOLUTION="$(prompt "Moonlight resolution (auto/720/1080/1440/4K/custom)" "$MOONLIGHT_RESOLUTION")"
MOONLIGHT_FPS="$(prompt "Moonlight FPS" "$MOONLIGHT_FPS")"
MOONLIGHT_BITRATE="$(prompt "Moonlight bitrate Kbps" "$MOONLIGHT_BITRATE")"
MOONLIGHT_VIDEO_CODEC="$(prompt "Moonlight video codec" "$MOONLIGHT_VIDEO_CODEC")"
MOONLIGHT_VIDEO_DECODER="$(prompt "Moonlight video decoder" "$MOONLIGHT_VIDEO_DECODER")"
MOONLIGHT_AUDIO_CONFIG="$(prompt "Moonlight audio config" "$MOONLIGHT_AUDIO_CONFIG")"

emit_var MODE "$MODE"
emit_var CONNECTION_METHOD "$CONNECTION_METHOD"
emit_var PROFILE_NAME "$PROFILE_NAME"
emit_var RUNTIME_USER "$RUNTIME_USER"
emit_var HOSTNAME_VALUE "$HOSTNAME_VALUE"
emit_var AUTOSTART "$AUTOSTART"
emit_var NETWORK_MODE "$NETWORK_MODE"
emit_var NETWORK_INTERFACE "$NETWORK_INTERFACE"
emit_var NETWORK_STATIC_ADDRESS "$NETWORK_STATIC_ADDRESS"
emit_var NETWORK_STATIC_PREFIX "$NETWORK_STATIC_PREFIX"
emit_var NETWORK_GATEWAY "$NETWORK_GATEWAY"
emit_var NETWORK_DNS_SERVERS "$NETWORK_DNS_SERVERS"
emit_var MOONLIGHT_HOST "$MOONLIGHT_HOST"
emit_var MOONLIGHT_APP "$MOONLIGHT_APP"
emit_var MOONLIGHT_BIN "$MOONLIGHT_BIN"
emit_var MOONLIGHT_RESOLUTION "$MOONLIGHT_RESOLUTION"
emit_var MOONLIGHT_FPS "$MOONLIGHT_FPS"
emit_var MOONLIGHT_BITRATE "$MOONLIGHT_BITRATE"
emit_var MOONLIGHT_VIDEO_CODEC "$MOONLIGHT_VIDEO_CODEC"
emit_var MOONLIGHT_VIDEO_DECODER "$MOONLIGHT_VIDEO_DECODER"
emit_var MOONLIGHT_AUDIO_CONFIG "$MOONLIGHT_AUDIO_CONFIG"
emit_var MOONLIGHT_ABSOLUTE_MOUSE "$MOONLIGHT_ABSOLUTE_MOUSE"
emit_var MOONLIGHT_QUIT_AFTER "$MOONLIGHT_QUIT_AFTER"
emit_var SUNSHINE_API_URL "$SUNSHINE_API_URL"
emit_var PROXMOX_SCHEME "$PROXMOX_SCHEME"
emit_var PROXMOX_HOST "$PROXMOX_HOST"
emit_var PROXMOX_PORT "$PROXMOX_PORT"
emit_var PROXMOX_NODE "$PROXMOX_NODE"
emit_var PROXMOX_VMID "$PROXMOX_VMID"
emit_var PROXMOX_REALM "$PROXMOX_REALM"
emit_var PROXMOX_VERIFY_TLS "$PROXMOX_VERIFY_TLS"
emit_var CONNECTION_USERNAME "$CONNECTION_USERNAME"
emit_var CONNECTION_PASSWORD "$CONNECTION_PASSWORD"
emit_var CONNECTION_TOKEN "$CONNECTION_TOKEN"
emit_var SUNSHINE_USERNAME "$SUNSHINE_USERNAME"
emit_var SUNSHINE_PASSWORD "$SUNSHINE_PASSWORD"
emit_var SUNSHINE_PIN "$SUNSHINE_PIN"
