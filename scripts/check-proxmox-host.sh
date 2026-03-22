#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/beagle}"
CONFIG_DIR="${PVE_DCV_CONFIG_DIR:-/etc/beagle}"
HOST_ENV_FILE="${PVE_DCV_HOST_ENV_FILE:-$CONFIG_DIR/host.env}"
SERVER_NAME="${PVE_DCV_PROXY_SERVER_NAME:-$(hostname -f 2>/dev/null || hostname)}"
LISTEN_PORT="${PVE_DCV_PROXY_LISTEN_PORT:-8443}"
DOWNLOADS_PATH="${PVE_DCV_DOWNLOADS_PATH:-/beagle-downloads}"
BASE_URL="https://${SERVER_NAME}:${LISTEN_PORT}"
FAILURES=0
STATUS_JSON_FILE="$INSTALL_DIR/dist/beagle-downloads-status.json"
REFRESH_STATUS_FILE="${PVE_DCV_STATUS_DIR:-/var/lib/beagle}/refresh.status.json"

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

record_failure() {
  FAILURES=$((FAILURES + 1))
}

check_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    echo "OK  file  $path"
    return 0
  fi
  echo "ERR file  $path"
  record_failure
}

check_http() {
  local url="$1"
  if curl -kfsSI "$url" >/dev/null 2>&1; then
    echo "OK  http  $url"
    return 0
  fi
  echo "ERR http  $url"
  record_failure
}

check_service_active() {
  local service="$1"
  if systemctl is-active --quiet "$service"; then
    echo "OK  svc   $service"
    return 0
  fi
  echo "ERR svc   $service"
  record_failure
}

check_status_json() {
  python3 - "$STATUS_JSON_FILE" "$INSTALL_DIR/VERSION" "$BASE_URL${DOWNLOADS_PATH}/pve-thin-client-usb-installer-host-latest.sh" "$BASE_URL${DOWNLOADS_PATH}/pve-thin-client-usb-bootstrap-latest.tar.gz" "$BASE_URL${DOWNLOADS_PATH}/pve-thin-client-usb-payload-latest.tar.gz" "$SERVER_NAME" "$LISTEN_PORT" "$DOWNLOADS_PATH" "$INSTALL_DIR/dist/pve-thin-client-usb-installer-host-latest.sh" "$INSTALL_DIR/dist/pve-thin-client-usb-bootstrap-latest.tar.gz" "$INSTALL_DIR/dist/pve-thin-client-usb-payload-latest.tar.gz" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

status_path = Path(sys.argv[1])
version_file = Path(sys.argv[2])
expected_installer_url = sys.argv[3]
expected_bootstrap_url = sys.argv[4]
expected_payload_url = sys.argv[5]
expected_server = sys.argv[6]
expected_port = int(sys.argv[7])
expected_downloads_path = sys.argv[8]
installer_file = Path(sys.argv[9])
bootstrap_file = Path(sys.argv[10])
payload_file = Path(sys.argv[11])

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

status = json.loads(status_path.read_text())
errors = []
version = version_file.read_text().strip()

if status.get("version") != version:
    errors.append(f"status version mismatch: {status.get('version')} != {version}")
if status.get("installer_url") != expected_installer_url:
    errors.append("installer_url mismatch")
if status.get("bootstrap_url") != expected_bootstrap_url:
    errors.append("bootstrap_url mismatch")
if status.get("payload_url") != expected_payload_url:
    errors.append("payload_url mismatch")
if status.get("server_name") != expected_server:
    errors.append("server_name mismatch")
if int(status.get("listen_port", -1)) != expected_port:
    errors.append("listen_port mismatch")
if status.get("downloads_path") != expected_downloads_path:
    errors.append("downloads_path mismatch")
if status.get("installer_size") != installer_file.stat().st_size:
    errors.append("installer_size mismatch")
if status.get("bootstrap_size") != bootstrap_file.stat().st_size:
    errors.append("bootstrap_size mismatch")
if status.get("payload_size") != payload_file.stat().st_size:
    errors.append("payload_size mismatch")
if status.get("installer_sha256") != sha256(installer_file):
    errors.append("installer_sha256 mismatch")
if status.get("bootstrap_sha256") != sha256(bootstrap_file):
    errors.append("bootstrap_sha256 mismatch")
if status.get("payload_sha256") != sha256(payload_file):
    errors.append("payload_sha256 mismatch")

if errors:
    raise SystemExit("; ".join(errors))
PY
}

check_hosted_installer_binding() {
  local expected_bootstrap_url="${BASE_URL}${DOWNLOADS_PATH}/pve-thin-client-usb-bootstrap-latest.tar.gz"
  local expected_payload_url="${BASE_URL}${DOWNLOADS_PATH}/pve-thin-client-usb-payload-latest.tar.gz"
  if ! grep -Fq "RELEASE_BOOTSTRAP_URL=\"\${RELEASE_BOOTSTRAP_URL:-${expected_bootstrap_url}}\"" "$INSTALL_DIR/dist/pve-thin-client-usb-installer-host-latest.sh"; then
    echo "ERR bind  hosted installer bootstrap URL"
    record_failure
    return 1
  fi
  if ! grep -Fq "INSTALL_PAYLOAD_URL=\"\${INSTALL_PAYLOAD_URL:-${expected_payload_url}}\"" "$INSTALL_DIR/dist/pve-thin-client-usb-installer-host-latest.sh"; then
    echo "ERR bind  hosted installer install payload URL"
    record_failure
    return 1
  fi
  echo "OK  bind  hosted installer bootstrap/payload URLs"
  return 0
}

load_host_env

check_file "$INSTALL_DIR/VERSION"
check_file "$INSTALL_DIR/dist/pve-thin-client-usb-installer-host-latest.sh"
check_file "$INSTALL_DIR/dist/pve-thin-client-usb-bootstrap-latest.tar.gz"
check_file "$INSTALL_DIR/dist/pve-thin-client-usb-payload-latest.tar.gz"
check_file "$INSTALL_DIR/dist/beagle-downloads-status.json"
check_file "$INSTALL_DIR/dist/SHA256SUMS"
check_file "$REFRESH_STATUS_FILE"
check_file "/usr/share/pve-manager/js/beagle-ui.js"
check_file "/usr/share/pve-manager/js/beagle-ui-config.js"
check_file "/etc/nginx/sites-available/beagle-proxy.conf"
check_file "/etc/systemd/system/beagle-ui-reapply.service"
check_file "/etc/systemd/system/beagle-ui-reapply.path"
check_file "/etc/systemd/system/beagle-control-plane.service"

check_service_active "pveproxy"
check_service_active "nginx"
check_service_active "beagle-artifacts-refresh.timer"
check_service_active "beagle-ui-reapply.path"
check_service_active "beagle-control-plane"

check_http "$BASE_URL/"
check_http "$BASE_URL${DOWNLOADS_PATH}/pve-thin-client-usb-installer-host-latest.sh"
check_http "$BASE_URL${DOWNLOADS_PATH}/pve-thin-client-usb-bootstrap-latest.tar.gz"
check_http "$BASE_URL${DOWNLOADS_PATH}/pve-thin-client-usb-payload-latest.tar.gz"
check_http "$BASE_URL${DOWNLOADS_PATH}/beagle-downloads-status.json"
check_http "$BASE_URL${DOWNLOADS_PATH}/SHA256SUMS"
check_http "$BASE_URL/beagle-api/api/v1/health"

if check_status_json; then
  echo "OK  json  $STATUS_JSON_FILE"
else
  echo "ERR json  $STATUS_JSON_FILE"
  record_failure
fi

check_hosted_installer_binding

if (( FAILURES > 0 )); then
  echo "Host validation failed with $FAILURES problem(s)." >&2
  exit 1
fi

echo "Host validation completed successfully."
