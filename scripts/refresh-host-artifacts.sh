#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${PVE_DCV_CONFIG_DIR:-/etc/beagle}"
HOST_ENV_FILE="${PVE_DCV_HOST_ENV_FILE:-$CONFIG_DIR/host.env}"
STATUS_DIR="${PVE_DCV_STATUS_DIR:-/var/lib/beagle}"
REFRESH_STATUS_FILE="$STATUS_DIR/refresh.status.json"

START_TS="$(date +%s)"
STATUS_RESULT="failed"

write_refresh_status() {
  local end_ts duration version

  end_ts="$(date +%s)"
  duration="$(( end_ts - START_TS ))"
  version="$(tr -d ' \n\r' < "$ROOT_DIR/VERSION" 2>/dev/null || echo unknown)"

  install -d -m 0755 "$STATUS_DIR"
  python3 - "$REFRESH_STATUS_FILE" "$STATUS_RESULT" "$version" "$START_TS" "$end_ts" "$duration" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
status = sys.argv[2]
version = sys.argv[3]
started = int(sys.argv[4])
ended = int(sys.argv[5])
duration = int(sys.argv[6])

payload = {
    "status": status,
    "version": version,
    "started_at": datetime.fromtimestamp(started, timezone.utc).isoformat(),
    "finished_at": datetime.fromtimestamp(ended, timezone.utc).isoformat(),
    "duration_seconds": duration,
}
path.write_text(json.dumps(payload, indent=2) + "\n")
PY
}

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

trap write_refresh_status EXIT

ensure_root "$@"
load_host_env

export PVE_DCV_PROXY_SERVER_NAME="${PVE_DCV_PROXY_SERVER_NAME:-$(hostname -f 2>/dev/null || hostname)}"
export PVE_DCV_PROXY_LISTEN_PORT="${PVE_DCV_PROXY_LISTEN_PORT:-8443}"
export PVE_DCV_DOWNLOADS_PATH="${PVE_DCV_DOWNLOADS_PATH:-/beagle-downloads}"
export PVE_DCV_DOWNLOADS_BASE_URL="${PVE_DCV_DOWNLOADS_BASE_URL:-https://${PVE_DCV_PROXY_SERVER_NAME}:${PVE_DCV_PROXY_LISTEN_PORT}${PVE_DCV_DOWNLOADS_PATH}}"

"$ROOT_DIR/scripts/package.sh"
"$ROOT_DIR/scripts/prepare-host-downloads.sh"
STATUS_RESULT="ok"

echo "Refreshed hosted artifacts under $ROOT_DIR/dist"
