#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_runtime_config

MOONLIGHT_LOG_DIR="${PVE_THIN_CLIENT_LOG_DIR:-${XDG_RUNTIME_DIR:-/tmp}/pve-thin-client}"
MOONLIGHT_LIST_LOG="$MOONLIGHT_LOG_DIR/moonlight-list.log"
MOONLIGHT_PAIR_LOG="$MOONLIGHT_LOG_DIR/moonlight-pair.log"

mkdir -p "$MOONLIGHT_LOG_DIR" 2>/dev/null || true

have_binary() {
  command -v "$1" >/dev/null 2>&1
}

moonlight_bin() {
  printf '%s\n' "${PVE_THIN_CLIENT_MOONLIGHT_BIN:-moonlight}"
}

prefer_ipv4() {
  [[ "${PVE_THIN_CLIENT_MOONLIGHT_PREFER_IPV4:-1}" == "1" ]]
}

is_ip_literal() {
  python3 - "$1" <<'PY'
import ipaddress
import sys

try:
    ipaddress.ip_address(sys.argv[1].strip("[]"))
except ValueError:
    raise SystemExit(1)
PY
}

moonlight_host() {
  render_template "${PVE_THIN_CLIENT_MOONLIGHT_HOST:-}"
}

resolve_ipv4_host() {
  python3 - "$1" <<'PY'
import socket
import sys

host = sys.argv[1]
seen = set()
for entry in socket.getaddrinfo(host, None, family=socket.AF_INET, type=socket.SOCK_STREAM):
    address = entry[4][0]
    if address not in seen:
        seen.add(address)
        print(address)
        raise SystemExit(0)

raise SystemExit(1)
PY
}

moonlight_connect_host() {
  local host resolved
  host="$(moonlight_host)"
  [[ -n "$host" ]] || return 0
  if prefer_ipv4 && ! is_ip_literal "$host"; then
    resolved="$(resolve_ipv4_host "$host" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  fi
  printf '%s\n' "$host"
}

moonlight_app() {
  render_template "${PVE_THIN_CLIENT_MOONLIGHT_APP:-Desktop}"
}

moonlight_audio_driver() {
  printf '%s\n' "${PVE_THIN_CLIENT_MOONLIGHT_AUDIO_DRIVER:-alsa}"
}

local_display_resolution() {
  if command -v xrandr >/dev/null 2>&1; then
    xrandr --query 2>/dev/null | awk '
      / connected primary / {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^[0-9]+x[0-9]+\+/) {
            split($i, parts, "+")
            print parts[1]
            exit
          }
        }
      }
      / connected / {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^[0-9]+x[0-9]+\+/) {
            split($i, parts, "+")
            print parts[1]
            exit
          }
        }
      }
      /^Screen [0-9]+:/ {
        if (match($0, /current [0-9]+ x [0-9]+/)) {
          value = substr($0, RSTART + 8, RLENGTH - 8)
          gsub(/ /, "", value)
          print value
          exit
        }
      }
    '
  fi
}

moonlight_resolution() {
  local configured detected
  configured="${PVE_THIN_CLIENT_MOONLIGHT_RESOLUTION:-auto}"

  if [[ "${PVE_THIN_CLIENT_MOONLIGHT_AUTO_RESOLUTION:-1}" == "1" ]]; then
    detected="$(local_display_resolution 2>/dev/null || true)"
    case "$configured" in
      ""|auto|native)
        if [[ -n "$detected" ]]; then
          printf '%s\n' "$detected"
          return 0
        fi
        ;;
      720|1080|1440|4K)
        if [[ -n "$detected" && "$detected" != "1024x768" ]]; then
          printf '%s\n' "$detected"
          return 0
        fi
        ;;
    esac
  fi

  printf '%s\n' "$configured"
}

moonlight_list_timeout() {
  printf '%s\n' "${PVE_THIN_CLIENT_MOONLIGHT_LIST_TIMEOUT:-12}"
}

sunshine_api_url() {
  local configured host
  configured="$(render_template "${PVE_THIN_CLIENT_SUNSHINE_API_URL:-}" 2>/dev/null || true)"
  if [[ -n "$configured" ]]; then
    printf '%s\n' "$configured"
    return 0
  fi

  host="$(moonlight_host)"
  if [[ -n "$host" ]]; then
    printf 'https://%s:47990\n' "$host"
  fi
}

moonlight_target_reachable() {
  local api_url host
  local -a curl_opts
  local username password

  api_url="$(sunshine_api_url)"
  curl_opts=(-ksS -o /dev/null --connect-timeout 2 --max-time 4)
  username="${PVE_THIN_CLIENT_SUNSHINE_USERNAME:-}"
  password="${PVE_THIN_CLIENT_SUNSHINE_PASSWORD:-}"
  if prefer_ipv4; then
    curl_opts+=(-4)
  fi
  if [[ -n "$username" && -n "$password" ]]; then
    curl_opts+=(--user "${username}:${password}")
  fi
  if [[ -n "$api_url" ]]; then
    curl "${curl_opts[@]}" "${api_url%/}/api/apps" && return 0
  fi

  host="$(moonlight_connect_host)"
  [[ -n "$host" ]] || return 1

  if command -v ping >/dev/null 2>&1; then
    if prefer_ipv4; then
      ping -4 -c 1 -W 2 "$host" >/dev/null 2>&1 && return 0
    fi
    ping -c 1 -W 2 "$host" >/dev/null 2>&1 && return 0
  fi

  return 1
}

json_bool() {
  local payload="$1"
  python3 - "$payload" <<'PY'
import json
import sys

try:
    data = json.loads(sys.argv[1] or "{}")
except json.JSONDecodeError:
    raise SystemExit(1)

print("1" if bool(data.get("status")) else "0")
PY
}

moonlight_list() {
  local bin host timeout_value
  bin="$(moonlight_bin)"
  host="$(moonlight_connect_host)"
  timeout_value="$(moonlight_list_timeout)"

  if command -v timeout >/dev/null 2>&1; then
    timeout --preserve-status "$timeout_value" "$bin" list "$host" >"$MOONLIGHT_LIST_LOG" 2>&1
    return $?
  fi

  "$bin" list "$host" >"$MOONLIGHT_LIST_LOG" 2>&1
}

submit_sunshine_pin() {
  local api_url username password pin name response

  api_url="$(sunshine_api_url)"
  username="${PVE_THIN_CLIENT_SUNSHINE_USERNAME:-}"
  password="${PVE_THIN_CLIENT_SUNSHINE_PASSWORD:-}"
  pin="${PVE_THIN_CLIENT_SUNSHINE_PIN:-}"
  name="${PVE_THIN_CLIENT_MOONLIGHT_CLIENT_NAME:-${PVE_THIN_CLIENT_HOSTNAME:-$(hostname)}}"

  [[ -n "$api_url" && -n "$username" && -n "$password" && -n "$pin" ]] || return 1

  response="$(
    curl -kfsS \
      --connect-timeout 2 \
      --max-time 4 \
      --user "${username}:${password}" \
      -H 'Content-Type: application/json' \
      --data "{\"pin\":\"${pin}\",\"name\":\"${name}\"}" \
      "${api_url%/}/api/pin"
  )" || return 1

  [[ "$(json_bool "$response")" == "1" ]]
}

ensure_paired() {
  local bin host pin pair_pid paired_ok attempt pair_status

  bin="$(moonlight_bin)"
  host="$(moonlight_connect_host)"
  pin="${PVE_THIN_CLIENT_SUNSHINE_PIN:-}"

  moonlight_list && return 0

  [[ -n "$pin" ]] || return 1

  if command -v timeout >/dev/null 2>&1; then
    timeout --preserve-status "$(moonlight_list_timeout)" "$bin" pair "$host" --pin "$pin" >"$MOONLIGHT_PAIR_LOG" 2>&1 &
  else
    "$bin" pair "$host" --pin "$pin" >"$MOONLIGHT_PAIR_LOG" 2>&1 &
  fi
  pair_pid=$!
  paired_ok="0"

  for attempt in $(seq 1 20); do
    sleep 1
    if submit_sunshine_pin; then
      paired_ok="1"
      break
    fi
  done

  pair_status=0
  wait "$pair_pid" || pair_status=$?

  [[ "$pair_status" == "0" ]] || return "$pair_status"
  [[ "$paired_ok" == "1" ]] || return 1
  moonlight_list
}

build_stream_args() {
  local resolution fps bitrate codec decoder audio_config app host connect_host
  local -n out_ref="$1"

  host="$(moonlight_host)"
  connect_host="$(moonlight_connect_host)"
  app="$(moonlight_app)"
  resolution="$(moonlight_resolution)"
  fps="${PVE_THIN_CLIENT_MOONLIGHT_FPS:-60}"
  bitrate="${PVE_THIN_CLIENT_MOONLIGHT_BITRATE:-20000}"
  codec="${PVE_THIN_CLIENT_MOONLIGHT_VIDEO_CODEC:-H.264}"
  decoder="${PVE_THIN_CLIENT_MOONLIGHT_VIDEO_DECODER:-auto}"
  audio_config="${PVE_THIN_CLIENT_MOONLIGHT_AUDIO_CONFIG:-stereo}"

  out_ref=("$(moonlight_bin)" stream "${connect_host:-$host}" "$app")

  case "$resolution" in
    720|1080|1440|4K)
      out_ref+=("--$resolution")
      ;;
    *x*)
      out_ref+=(--resolution "$resolution")
      ;;
  esac

  [[ -n "$fps" ]] && out_ref+=(--fps "$fps")
  [[ -n "$bitrate" ]] && out_ref+=(--bitrate "$bitrate")
  [[ -n "$codec" ]] && out_ref+=(--video-codec "$codec")
  [[ -n "$decoder" ]] && out_ref+=(--video-decoder "$decoder")
  [[ -n "$audio_config" ]] && out_ref+=(--audio-config "$audio_config")

  out_ref+=(--display-mode fullscreen --frame-pacing --keep-awake --no-hdr --no-yuv444)

  if [[ "${PVE_THIN_CLIENT_MOONLIGHT_ABSOLUTE_MOUSE:-1}" == "1" ]]; then
    out_ref+=(--absolute-mouse)
  fi
  if [[ "${PVE_THIN_CLIENT_MOONLIGHT_QUIT_AFTER:-0}" == "1" ]]; then
    out_ref+=(--quit-after)
  fi
}

configure_graphics_runtime() {
  if [[ "${PVE_THIN_CLIENT_MOONLIGHT_VIDEO_DECODER:-auto}" == "software" ]]; then
    export QT_QUICK_BACKEND="${QT_QUICK_BACKEND:-software}"
    export LIBVA_DRIVER_NAME="${LIBVA_DRIVER_NAME:-none}"
    export VDPAU_DRIVER="${VDPAU_DRIVER:-noop}"
  fi
}

main() {
  local bin host connect_host app audio_driver
  local -a args=()

  bin="$(moonlight_bin)"
  host="$(moonlight_host)"
  connect_host="$(moonlight_connect_host)"
  app="$(moonlight_app)"

  [[ -n "$host" ]] || {
    echo "Missing Moonlight host." >&2
    exit 1
  }

  have_binary "$bin" || {
    echo "Moonlight binary not found: $bin" >&2
    exit 1
  }

  audio_driver="$(moonlight_audio_driver)"
  if [[ -n "$audio_driver" && "$audio_driver" != "auto" ]]; then
    export SDL_AUDIODRIVER="$audio_driver"
  fi

  configure_graphics_runtime

  moonlight_target_reachable || {
    echo "Moonlight host '$host' is unreachable from this network." >&2
    exit 1
  }

  if command -v /usr/local/bin/pve-thin-client-display-init >/dev/null 2>&1; then
    /usr/local/bin/pve-thin-client-display-init >/dev/null 2>&1 || true
  fi

  if command -v /usr/local/bin/pve-thin-client-audio-init >/dev/null 2>&1; then
    /usr/local/bin/pve-thin-client-audio-init >/dev/null 2>&1 || true
    pkill -f '^bash /usr/local/bin/pve-thin-client-audio-init --watch' >/dev/null 2>&1 || true
    /usr/local/bin/pve-thin-client-audio-init --watch "${PVE_THIN_CLIENT_AUDIO_WATCH_LOOPS:-0}" >/dev/null 2>&1 &
  fi

  if ! moonlight_list; then
    ensure_paired || {
      echo "Moonlight pairing failed for host '$host'." >&2
      exit 1
    }
  fi

  build_stream_args args
  if [[ -n "$connect_host" && "$connect_host" != "$host" ]]; then
    echo "Starting Moonlight stream: host=$host resolved_ipv4=$connect_host app=$app resolution=$(moonlight_resolution) fps=${PVE_THIN_CLIENT_MOONLIGHT_FPS:-60}" >&2
  else
    echo "Starting Moonlight stream: host=$host app=$app resolution=$(moonlight_resolution) fps=${PVE_THIN_CLIENT_MOONLIGHT_FPS:-60}" >&2
  fi
  exec "${args[@]}"
}

main "$@"
