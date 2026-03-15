#!/usr/bin/env bash
set -euo pipefail

MODE="${MODE:-}"
RUNTIME_USER="${RUNTIME_USER:-thinclient}"
SPICE_URL="${SPICE_URL:-}"
NOVNC_URL="${NOVNC_URL:-}"
DCV_URL="${DCV_URL:-}"
BROWSER_BIN="${BROWSER_BIN:-chromium}"

prompt() {
  local label="$1"
  local default_value="$2"
  local value
  read -r -p "$label [$default_value]: " value
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

select_mode() {
  local answer
  while true; do
    echo "Select target mode:"
    echo "  1) SPICE"
    echo "  2) NOVNC"
    echo "  3) DCV"
    read -r -p "Choice [1-3]: " answer
    case "$answer" in
      1) printf 'SPICE\n'; return 0 ;;
      2) printf 'NOVNC\n'; return 0 ;;
      3) printf 'DCV\n'; return 0 ;;
    esac
  done
}

if [[ -z "$MODE" ]]; then
  MODE="$(select_mode)"
fi

RUNTIME_USER="$(prompt "Runtime user" "$RUNTIME_USER")"

case "$MODE" in
  SPICE)
    SPICE_URL="$(prompt "SPICE URL or .vv target" "${SPICE_URL:-spice://proxmox.example.internal:3128}")"
    ;;
  NOVNC)
    NOVNC_URL="$(prompt "noVNC URL" "${NOVNC_URL:-https://proxmox.example.internal:8006/?console=kvm}")"
    BROWSER_BIN="$(prompt "Browser binary" "$BROWSER_BIN")"
    ;;
  DCV)
    DCV_URL="$(prompt "DCV connection URL" "${DCV_URL:-dcv://dcv-gateway.example.internal/session/example}")"
    ;;
  *)
    echo "Unsupported mode: $MODE" >&2
    exit 1
    ;;
esac

cat <<EOF
MODE=$MODE
RUNTIME_USER=$RUNTIME_USER
SPICE_URL=$SPICE_URL
NOVNC_URL=$NOVNC_URL
DCV_URL=$DCV_URL
BROWSER_BIN=$BROWSER_BIN
EOF
