#!/usr/bin/env bash
set -euo pipefail

SUNSHINE_STATE="${SUNSHINE_STATE:-$HOME/.config/sunshine/sunshine_state.json}"
CLIENT_CONFIG="${CLIENT_CONFIG:-}"
DEVICE_NAME="${DEVICE_NAME:-beagle-os-client}"
RESTART_SUNSHINE="${RESTART_SUNSHINE:-1}"

usage() {
  cat <<EOF
Usage: $0 --client-config /path/to/Moonlight.conf [--sunshine-state /path/to/sunshine_state.json] [--device-name NAME] [--no-restart]

Registers the Moonlight client certificate from a Beagle endpoint on a Sunshine host
so the endpoint can stream without an interactive pairing workflow.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --client-config) CLIENT_CONFIG="$2"; shift 2 ;;
      --sunshine-state) SUNSHINE_STATE="$2"; shift 2 ;;
      --device-name) DEVICE_NAME="$2"; shift 2 ;;
      --no-restart) RESTART_SUNSHINE="0"; shift ;;
      -h|--help) usage; exit 0 ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

restart_sunshine() {
  if [[ "$RESTART_SUNSHINE" != "1" ]]; then
    return 0
  fi

  if systemctl --user list-unit-files sunshine.service >/dev/null 2>&1; then
    systemctl --user restart sunshine.service >/dev/null 2>&1 || true
    return 0
  fi

  pkill -x sunshine >/dev/null 2>&1 || true
  nohup sunshine >/dev/null 2>&1 </dev/null &
  sleep 2
}

main() {
  parse_args "$@"

  [[ -n "$CLIENT_CONFIG" ]] || {
    echo "--client-config is required" >&2
    exit 1
  }
  [[ -r "$CLIENT_CONFIG" ]] || {
    echo "Moonlight client config is not readable: $CLIENT_CONFIG" >&2
    exit 1
  }
  [[ -f "$SUNSHINE_STATE" ]] || {
    echo "Sunshine state file not found: $SUNSHINE_STATE" >&2
    exit 1
  }

  python3 - "$CLIENT_CONFIG" "$SUNSHINE_STATE" "$DEVICE_NAME" <<'PY'
import json
import sys
import uuid
from pathlib import Path

client_config = Path(sys.argv[1])
sunshine_state = Path(sys.argv[2])
device_name = sys.argv[3]

text = client_config.read_text()
marker = 'certificate="@ByteArray('
start = text.find(marker)
if start < 0:
    raise SystemExit("Moonlight certificate not found in client config.")

start += len(marker)
end = text.find(')"\nkey=', start)
if end < 0:
    raise SystemExit("Unable to parse Moonlight certificate payload.")

cert = bytes(text[start:end], "utf-8").decode("unicode_escape")

state = json.loads(sunshine_state.read_text())
root = state.setdefault("root", {})
named_devices = root.setdefault("named_devices", [])

for entry in named_devices:
    if entry.get("cert") == cert:
        entry["name"] = device_name
        sunshine_state.write_text(json.dumps(state, indent=4) + "\n")
        print("updated-existing")
        raise SystemExit(0)

named_devices.append(
    {
        "name": device_name,
        "cert": cert,
        "uuid": str(uuid.uuid4()).upper(),
    }
)

sunshine_state.write_text(json.dumps(state, indent=4) + "\n")
print("registered-new")
PY

  restart_sunshine
}

main "$@"
