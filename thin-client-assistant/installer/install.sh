#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="/etc/pve-thin-client"
CONFIG_FILE="$CONFIG_DIR/thinclient.conf"
INSTALL_ROOT="/usr/local/lib/pve-thin-client"
BIN_DIR="/usr/local/bin"
AUTOSTART_DIR="/etc/xdg/autostart"
SYSTEMD_DIR="/etc/systemd/system"
MODE=""
RUNTIME_USER="thinclient"
SPICE_URL=""
NOVNC_URL=""
DCV_URL=""
BROWSER_BIN="chromium"

usage() {
  cat <<EOF
Usage: $0 [--mode SPICE|NOVNC|DCV] [--runtime-user USER] [--spice-url URL] [--novnc-url URL] [--dcv-url URL] [--browser-bin PATH]
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "This installer must run as root." >&2
    exit 1
  fi
}

copy_file() {
  local src="$1"
  local dst="$2"
  install -D -m 0755 "$src" "$dst"
}

copy_readonly() {
  local src="$1"
  local dst="$2"
  install -D -m 0644 "$src" "$dst"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) MODE="$2"; shift 2 ;;
      --runtime-user) RUNTIME_USER="$2"; shift 2 ;;
      --spice-url) SPICE_URL="$2"; shift 2 ;;
      --novnc-url) NOVNC_URL="$2"; shift 2 ;;
      --dcv-url) DCV_URL="$2"; shift 2 ;;
      --browser-bin) BROWSER_BIN="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

load_answers() {
  local output
  output="$(
    MODE="$MODE" \
    RUNTIME_USER="$RUNTIME_USER" \
    SPICE_URL="$SPICE_URL" \
    NOVNC_URL="$NOVNC_URL" \
    DCV_URL="$DCV_URL" \
    BROWSER_BIN="$BROWSER_BIN" \
    "$ROOT_DIR/installer/setup-menu.sh"
  )"
  eval "$output"
}

install_runtime_assets() {
  copy_file "$ROOT_DIR/runtime/launch-session.sh" "$INSTALL_ROOT/launch-session.sh"
  copy_file "$ROOT_DIR/runtime/prepare-runtime.sh" "$INSTALL_ROOT/prepare-runtime.sh"
  copy_file "$ROOT_DIR/installer/setup-menu.sh" "$INSTALL_ROOT/setup-menu.sh"
  copy_readonly "$ROOT_DIR/systemd/pve-thin-client-prepare.service" "$SYSTEMD_DIR/pve-thin-client-prepare.service"
  copy_readonly "$ROOT_DIR/templates/pve-thin-client.desktop" "$AUTOSTART_DIR/pve-thin-client.desktop"
  install -d -m 0755 "$BIN_DIR"
  ln -sf "$INSTALL_ROOT/launch-session.sh" "$BIN_DIR/pve-thin-client-launch"
  ln -sf "$INSTALL_ROOT/setup-menu.sh" "$BIN_DIR/pve-thin-client-setup"
}

write_config() {
  install -d -m 0755 "$CONFIG_DIR"
  sed \
    -e "s|@MODE@|$MODE|g" \
    -e "s|@RUNTIME_USER@|$RUNTIME_USER|g" \
    -e "s|@SPICE_URL@|$SPICE_URL|g" \
    -e "s|@NOVNC_URL@|$NOVNC_URL|g" \
    -e "s|@DCV_URL@|$DCV_URL|g" \
    -e "s|@BROWSER_BIN@|$BROWSER_BIN|g" \
    "$ROOT_DIR/templates/thinclient.conf" > "$CONFIG_FILE"
  chmod 0644 "$CONFIG_FILE"
}

ensure_user_exists() {
  if id "$RUNTIME_USER" >/dev/null 2>&1; then
    return 0
  fi
  echo "Runtime user '$RUNTIME_USER' does not exist." >&2
  echo "Create the account before first boot or adjust the config." >&2
}

install_packages_hint() {
  case "$MODE" in
    SPICE)
      echo "Suggested package: virt-viewer"
      ;;
    NOVNC)
      echo "Suggested package: chromium or chromium-browser"
      ;;
    DCV)
      echo "Install the NICE DCV Viewer package so 'dcvviewer' is available."
      ;;
    *)
      echo "Unsupported mode in summary: $MODE" >&2
      exit 1
      ;;
  esac
}

enable_services() {
  systemctl daemon-reload
  systemctl enable pve-thin-client-prepare.service >/dev/null
}

print_summary() {
  cat <<EOF
Installed pve-thin-client assets.
Config: $CONFIG_FILE
Mode: $MODE
Runtime user: $RUNTIME_USER
EOF
  install_packages_hint
}

require_root
parse_args "$@"
load_answers
install_runtime_assets
write_config
ensure_user_exists
enable_services
print_summary
