#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/beagle}"
CONFIG_DIR="${PVE_DCV_CONFIG_DIR:-/etc/beagle}"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_NAME="beagle-artifacts-refresh.service"
TIMER_NAME="beagle-artifacts-refresh.timer"
UI_REAPPLY_SERVICE="beagle-ui-reapply.service"
UI_REAPPLY_PATH="beagle-ui-reapply.path"
BEAGLE_CONTROL_SERVICE="beagle-control-plane.service"
BEAGLE_CONTROL_ENV_FILE="$CONFIG_DIR/beagle-manager.env"

ensure_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    exec sudo \
      INSTALL_DIR="$INSTALL_DIR" \
      PVE_DCV_CONFIG_DIR="$CONFIG_DIR" \
      "$0" "$@"
  fi

  echo "This installer must run as root or use sudo." >&2
  exit 1
}

install_unit() {
  local source_file="$1"
  local target_file="$2"

  sed "s|__INSTALL_DIR__|$INSTALL_DIR|g" "$source_file" > "$target_file"
}

generate_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
    return 0
  fi

  python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
}

ensure_root "$@"

install -d -m 0755 "$SYSTEMD_DIR"
install -d -m 0755 "$INSTALL_DIR/proxmox-host/bin"
install_unit "$ROOT_DIR/proxmox-host/systemd/$SERVICE_NAME" "$SYSTEMD_DIR/$SERVICE_NAME"
install -m 0644 "$ROOT_DIR/proxmox-host/systemd/$TIMER_NAME" "$SYSTEMD_DIR/$TIMER_NAME"
install_unit "$ROOT_DIR/proxmox-host/systemd/$UI_REAPPLY_SERVICE" "$SYSTEMD_DIR/$UI_REAPPLY_SERVICE"
install -m 0644 "$ROOT_DIR/proxmox-host/systemd/$UI_REAPPLY_PATH" "$SYSTEMD_DIR/$UI_REAPPLY_PATH"
install_unit "$ROOT_DIR/proxmox-host/systemd/$BEAGLE_CONTROL_SERVICE" "$SYSTEMD_DIR/$BEAGLE_CONTROL_SERVICE"
install -m 0755 "$ROOT_DIR/proxmox-host/bin/beagle-control-plane.py" "$INSTALL_DIR/proxmox-host/bin/beagle-control-plane.py"

install -d -m 0755 "$CONFIG_DIR"
if [[ ! -f "$BEAGLE_CONTROL_ENV_FILE" ]]; then
  cat > "$BEAGLE_CONTROL_ENV_FILE" <<EOF
BEAGLE_MANAGER_LISTEN_HOST="127.0.0.1"
BEAGLE_MANAGER_LISTEN_PORT="9088"
BEAGLE_MANAGER_DATA_DIR="/var/lib/beagle/beagle-manager"
BEAGLE_MANAGER_API_TOKEN="$(generate_token)"
BEAGLE_ENDPOINT_SHARED_TOKEN="$(generate_token)"
BEAGLE_MANAGER_ALLOW_LOCALHOST_NOAUTH="0"
EOF
  chmod 0600 "$BEAGLE_CONTROL_ENV_FILE"
elif ! grep -q '^BEAGLE_ENDPOINT_SHARED_TOKEN=' "$BEAGLE_CONTROL_ENV_FILE"; then
  printf 'BEAGLE_ENDPOINT_SHARED_TOKEN="%s"\n' "$(generate_token)" >> "$BEAGLE_CONTROL_ENV_FILE"
fi

systemctl daemon-reload
systemctl enable --now "$TIMER_NAME"
systemctl enable "$UI_REAPPLY_SERVICE"
systemctl enable --now "$UI_REAPPLY_PATH"
systemctl enable --now "$BEAGLE_CONTROL_SERVICE"

echo "Installed host services: $SERVICE_NAME, $TIMER_NAME, $UI_REAPPLY_SERVICE, $UI_REAPPLY_PATH, $BEAGLE_CONTROL_SERVICE"
