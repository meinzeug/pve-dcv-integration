#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/pve-thin-client/thinclient.conf}"
STATUS_DIR="${STATUS_DIR:-/var/lib/pve-thin-client}"
STATUS_FILE="$STATUS_DIR/runtime.status"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

install -d -m 0755 "$STATUS_DIR"

required_binary=""
case "${PVE_THIN_CLIENT_MODE:-}" in
  SPICE) required_binary="remote-viewer" ;;
  NOVNC) required_binary="${PVE_THIN_CLIENT_BROWSER_BIN:-chromium}" ;;
  DCV) required_binary="dcvviewer" ;;
  *)
    echo "Unsupported mode: ${PVE_THIN_CLIENT_MODE:-UNSET}" >&2
    exit 1
    ;;
esac

{
  echo "timestamp=$(date -Iseconds)"
  echo "mode=${PVE_THIN_CLIENT_MODE:-UNSET}"
  echo "runtime_user=${PVE_THIN_CLIENT_RUNTIME_USER:-UNSET}"
  echo "required_binary=$required_binary"
  if command -v "$required_binary" >/dev/null 2>&1; then
    echo "binary_available=1"
  else
    echo "binary_available=0"
  fi
} > "$STATUS_FILE"

chmod 0644 "$STATUS_FILE"
