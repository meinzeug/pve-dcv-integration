#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/pve-thin-client/thinclient.conf}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config file: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

if [[ "${PVE_THIN_CLIENT_AUTOSTART:-1}" != "1" ]]; then
  exit 0
fi

launch_spice() {
  exec remote-viewer "${PVE_THIN_CLIENT_SPICE_URL}"
}

launch_novnc() {
  exec "${PVE_THIN_CLIENT_BROWSER_BIN}" \
    --kiosk \
    --incognito \
    --no-first-run \
    --disable-session-crashed-bubble \
    "${PVE_THIN_CLIENT_NOVNC_URL}"
}

launch_dcv() {
  exec dcvviewer "${PVE_THIN_CLIENT_DCV_URL}"
}

case "${PVE_THIN_CLIENT_MODE:-}" in
  SPICE) launch_spice ;;
  NOVNC) launch_novnc ;;
  DCV) launch_dcv ;;
  *)
    echo "Unsupported mode: ${PVE_THIN_CLIENT_MODE:-UNSET}" >&2
    exit 1
    ;;
esac
