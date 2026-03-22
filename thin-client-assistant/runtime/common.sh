#!/usr/bin/env bash
set -euo pipefail

DEFAULT_CONFIG_DIR="/etc/pve-thin-client"
LIVE_STATE_DIR_DEFAULT="/run/live/medium/pve-thin-client/state"

find_live_state_dir() {
  local dir
  local -a candidates=(
    "${LIVE_STATE_DIR:-$LIVE_STATE_DIR_DEFAULT}"
    "$LIVE_STATE_DIR_DEFAULT"
    "/lib/live/mount/medium/pve-thin-client/state"
  )

  for dir in "${candidates[@]}"; do
    if [[ -f "$dir/thinclient.conf" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done

  if command -v findmnt >/dev/null 2>&1; then
    while IFS= read -r dir; do
      [[ -n "$dir" ]] || continue
      dir="$dir/pve-thin-client/state"
      if [[ -f "$dir/thinclient.conf" ]]; then
        printf '%s\n' "$dir"
        return 0
      fi
    done < <(findmnt -rn -o TARGET 2>/dev/null || true)
  fi

  return 1
}

find_config_dir() {
  if [[ -f "${CONFIG_DIR:-$DEFAULT_CONFIG_DIR}/thinclient.conf" ]]; then
    printf '%s\n' "${CONFIG_DIR:-$DEFAULT_CONFIG_DIR}"
    return 0
  fi

  if LIVE_STATE_DIR="$(find_live_state_dir)"; then
    printf '%s\n' "$LIVE_STATE_DIR"
    return 0
  fi

  return 1
}

load_runtime_config() {
  local dir
  dir="$(find_config_dir)" || {
    echo "Unable to locate thin-client config." >&2
    return 1
  }

  CONFIG_DIR="$dir"
  CONFIG_FILE="$dir/thinclient.conf"
  NETWORK_FILE="$dir/network.env"
  CREDENTIALS_FILE="$dir/credentials.env"

  if [[ ! -r "$CONFIG_FILE" ]]; then
    echo "Thin-client config is not readable: $CONFIG_FILE" >&2
    return 1
  fi

  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  if [[ -r "$NETWORK_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$NETWORK_FILE"
  elif [[ -e "$NETWORK_FILE" ]]; then
    echo "Skipping unreadable network file: $NETWORK_FILE" >&2
  fi
  if [[ -r "$CREDENTIALS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CREDENTIALS_FILE"
  elif [[ -e "$CREDENTIALS_FILE" ]]; then
    echo "Skipping unreadable credentials file: $CREDENTIALS_FILE" >&2
  fi
}

render_template() {
  local template="$1"
  local output="$template"

  output="${output//\{mode\}/${PVE_THIN_CLIENT_MODE:-}}"
  output="${output//\{username\}/${PVE_THIN_CLIENT_CONNECTION_USERNAME:-}}"
  output="${output//\{password\}/${PVE_THIN_CLIENT_CONNECTION_PASSWORD:-}}"
  output="${output//\{token\}/${PVE_THIN_CLIENT_CONNECTION_TOKEN:-}}"
  output="${output//\{host\}/${PVE_THIN_CLIENT_PROXMOX_HOST:-}}"
  output="${output//\{node\}/${PVE_THIN_CLIENT_PROXMOX_NODE:-}}"
  output="${output//\{vmid\}/${PVE_THIN_CLIENT_PROXMOX_VMID:-}}"
  output="${output//\{moonlight_host\}/${PVE_THIN_CLIENT_MOONLIGHT_HOST:-}}"
  output="${output//\{sunshine_api_url\}/${PVE_THIN_CLIENT_SUNSHINE_API_URL:-}}"

  printf '%s\n' "$output"
}

split_browser_flags() {
  local flags="${PVE_THIN_CLIENT_BROWSER_FLAGS:-}"
  if [[ -z "$flags" ]]; then
    return 0
  fi

  # shellcheck disable=SC2206
  BROWSER_FLAG_ARRAY=($flags)
}
