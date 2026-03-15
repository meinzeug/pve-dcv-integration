#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/pve-dcv-integration}"
CONFIG_DIR="${PVE_DCV_CONFIG_DIR:-/etc/pve-dcv-integration}"
HOST_ENV_FILE="${PVE_DCV_HOST_ENV_FILE:-$CONFIG_DIR/host.env}"
SERVER_NAME="${PVE_DCV_PROXY_SERVER_NAME:-$(hostname -f 2>/dev/null || hostname)}"
LISTEN_PORT="${PVE_DCV_PROXY_LISTEN_PORT:-8443}"
DOWNLOADS_PATH="${PVE_DCV_DOWNLOADS_PATH:-/pve-dcv-downloads}"
BASE_URL="https://${SERVER_NAME}:${LISTEN_PORT}"
FAILURES=0

load_host_env() {
  if [[ -f "$HOST_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$HOST_ENV_FILE"
  fi

  SERVER_NAME="${PVE_DCV_PROXY_SERVER_NAME:-$SERVER_NAME}"
  LISTEN_PORT="${PVE_DCV_PROXY_LISTEN_PORT:-$LISTEN_PORT}"
  DOWNLOADS_PATH="${PVE_DCV_DOWNLOADS_PATH:-$DOWNLOADS_PATH}"
  BASE_URL="https://${SERVER_NAME}:${LISTEN_PORT}"
}

check_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    echo "OK  file  $path"
    return 0
  fi
  echo "ERR file  $path"
  FAILURES=$((FAILURES + 1))
}

check_http() {
  local url="$1"
  if curl -kfsSI "$url" >/dev/null 2>&1; then
    echo "OK  http  $url"
    return 0
  fi
  echo "ERR http  $url"
  FAILURES=$((FAILURES + 1))
}

load_host_env

check_file "$INSTALL_DIR/VERSION"
check_file "$INSTALL_DIR/dist/pve-thin-client-usb-installer-host-latest.sh"
check_file "$INSTALL_DIR/dist/pve-thin-client-usb-payload-latest.tar.gz"
check_file "$INSTALL_DIR/dist/pve-dcv-downloads-status.json"
check_file "/usr/share/pve-manager/js/pve-dcv-integration.js"
check_file "/usr/share/pve-manager/js/pve-dcv-integration-config.js"
check_file "/etc/nginx/sites-available/pve-dcv-integration-dcv-proxy.conf"

check_http "$BASE_URL/"
check_http "$BASE_URL${DOWNLOADS_PATH}/pve-thin-client-usb-installer-host-latest.sh"
check_http "$BASE_URL${DOWNLOADS_PATH}/pve-thin-client-usb-payload-latest.tar.gz"
check_http "$BASE_URL${DOWNLOADS_PATH}/pve-dcv-downloads-status.json"

if (( FAILURES > 0 )); then
  echo "Host validation failed with $FAILURES problem(s)." >&2
  exit 1
fi

echo "Host validation completed successfully."
