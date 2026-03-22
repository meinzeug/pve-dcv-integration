#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
STATUS_DIR="${PVE_THIN_CLIENT_STATUS_DIR:-${XDG_RUNTIME_DIR:-/tmp}/pve-thin-client}"
LAUNCH_STATUS_FILE="$STATUS_DIR/launch.status.json"

load_runtime_config

if [[ "${PVE_THIN_CLIENT_AUTOSTART:-1}" != "1" ]]; then
  exit 0
fi

write_launch_status() {
  local mode="$1"
  local method="$2"
  local binary="$3"
  local target="$4"

  mkdir -p "$STATUS_DIR" 2>/dev/null || return 0

  python3 - "$LAUNCH_STATUS_FILE" "$mode" "$method" "$binary" "$target" "${PVE_THIN_CLIENT_PROFILE_NAME:-default}" "${PVE_THIN_CLIENT_RUNTIME_USER:-}" <<'PY' || true
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path = Path(sys.argv[1])
mode = sys.argv[2]
method = sys.argv[3]
binary = sys.argv[4]
target = sys.argv[5]
profile = sys.argv[6]
runtime_user = sys.argv[7]

payload = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "mode": mode,
    "launch_method": method,
    "binary": binary,
    "target": target,
    "profile_name": profile,
    "runtime_user": runtime_user,
}
path.write_text(json.dumps(payload, indent=2) + "\n")
PY
}

launch_moonlight() {
  local host app
  host="$(render_template "${PVE_THIN_CLIENT_MOONLIGHT_HOST:-}")"
  app="$(render_template "${PVE_THIN_CLIENT_MOONLIGHT_APP:-Desktop}")"
  write_launch_status "MOONLIGHT" "sunshine" "${PVE_THIN_CLIENT_MOONLIGHT_BIN:-moonlight}" "${host}:${app}"
  exec "$SCRIPT_DIR/launch-moonlight.sh"
}

if [[ "${PVE_THIN_CLIENT_MODE:-MOONLIGHT}" != "MOONLIGHT" ]]; then
  echo "Unsupported mode for Beagle OS: ${PVE_THIN_CLIENT_MODE:-UNSET}" >&2
  exit 1
fi

launch_moonlight
