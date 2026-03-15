#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${PVE_DCV_CONFIG_DIR:-/etc/pve-dcv-integration}"
HOST_ENV_FILE="${PVE_DCV_HOST_ENV_FILE:-$CONFIG_DIR/host.env}"

ensure_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    exec sudo \
      PVE_DCV_CONFIG_DIR="$CONFIG_DIR" \
      PVE_DCV_HOST_ENV_FILE="$HOST_ENV_FILE" \
      "$0" "$@"
  fi

  echo "This command must run as root or use sudo." >&2
  exit 1
}

load_host_env() {
  if [[ -f "$HOST_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$HOST_ENV_FILE"
  fi
}

ensure_root "$@"
load_host_env

export PVE_DCV_PROXY_SERVER_NAME="${PVE_DCV_PROXY_SERVER_NAME:-$(hostname -f 2>/dev/null || hostname)}"
export PVE_DCV_PROXY_LISTEN_PORT="${PVE_DCV_PROXY_LISTEN_PORT:-8443}"
export PVE_DCV_DOWNLOADS_PATH="${PVE_DCV_DOWNLOADS_PATH:-/pve-dcv-downloads}"
export PVE_DCV_DOWNLOADS_BASE_URL="${PVE_DCV_DOWNLOADS_BASE_URL:-https://${PVE_DCV_PROXY_SERVER_NAME}:${PVE_DCV_PROXY_LISTEN_PORT}${PVE_DCV_DOWNLOADS_PATH}}"

"$ROOT_DIR/scripts/package.sh"
"$ROOT_DIR/scripts/prepare-host-downloads.sh"

echo "Refreshed hosted artifacts under $ROOT_DIR/dist"
