#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${PVE_DCV_PROXY_CONFIG_DIR:-/etc/pve-dcv-integration}"
ENV_FILE="$CONFIG_DIR/dcv-proxy.env"
LISTEN_PORT="${PVE_DCV_PROXY_LISTEN_PORT:-8443}"
BACKEND_HOST="${PVE_DCV_PROXY_BACKEND_HOST:-}"
BACKEND_PORT="${PVE_DCV_PROXY_BACKEND_PORT:-8443}"
BACKEND_VMID="${PVE_DCV_PROXY_VMID:-}"
SERVER_NAME="${PVE_DCV_PROXY_SERVER_NAME:-$(hostname -f 2>/dev/null || hostname)}"
DOWNLOADS_PATH="${PVE_DCV_DOWNLOADS_PATH:-/pve-dcv-downloads}"
DOWNLOADS_BASE_URL="${PVE_DCV_DOWNLOADS_BASE_URL:-https://${SERVER_NAME}:${LISTEN_PORT}${DOWNLOADS_PATH}}"
CERT_FILE="${PVE_DCV_PROXY_CERT_FILE:-/etc/pve/local/pveproxy-ssl.pem}"
KEY_FILE="${PVE_DCV_PROXY_KEY_FILE:-/etc/pve/local/pveproxy-ssl.key}"
NGINX_SITE="/etc/nginx/sites-available/pve-dcv-integration-dcv-proxy.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/pve-dcv-integration-dcv-proxy.conf"

ensure_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    exec sudo \
      PVE_DCV_PROXY_CONFIG_DIR="$CONFIG_DIR" \
      PVE_DCV_PROXY_LISTEN_PORT="$LISTEN_PORT" \
      PVE_DCV_PROXY_BACKEND_HOST="$BACKEND_HOST" \
      PVE_DCV_PROXY_BACKEND_PORT="$BACKEND_PORT" \
      PVE_DCV_PROXY_VMID="$BACKEND_VMID" \
      PVE_DCV_PROXY_SERVER_NAME="$SERVER_NAME" \
      PVE_DCV_DOWNLOADS_PATH="$DOWNLOADS_PATH" \
      PVE_DCV_DOWNLOADS_BASE_URL="$DOWNLOADS_BASE_URL" \
      PVE_DCV_PROXY_CERT_FILE="$CERT_FILE" \
      PVE_DCV_PROXY_KEY_FILE="$KEY_FILE" \
      "$0" "$@"
  fi

  echo "This installer must run as root or use sudo." >&2
  exit 1
}

log() {
  echo "[pve-dcv-proxy] $*"
}

ensure_dependencies() {
  local package=()

  command -v nginx >/dev/null 2>&1 || package+=(nginx)
  command -v python3 >/dev/null 2>&1 || package+=(python3)

  if (( ${#package[@]} == 0 )); then
    return 0
  fi

  apt_update_with_proxmox_fallback
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${package[@]}"
}

disable_proxmox_enterprise_repo() {
  local found=0
  local file

  while IFS= read -r file; do
    grep -q 'enterprise.proxmox.com' "$file" || continue
    cp "$file" "$file.pve-dcv-backup"
    awk '!/enterprise\.proxmox\.com/' "$file.pve-dcv-backup" > "$file"
    found=1
  done < <(find /etc/apt -maxdepth 2 -type f \( -name '*.list' -o -name '*.sources' \) 2>/dev/null)

  return $(( ! found ))
}

restore_proxmox_enterprise_repo() {
  local backup original

  while IFS= read -r backup; do
    original="${backup%.pve-dcv-backup}"
    mv "$backup" "$original"
  done < <(find /etc/apt -maxdepth 2 -type f -name '*.pve-dcv-backup' 2>/dev/null)
}

apt_update_with_proxmox_fallback() {
  if apt-get update; then
    return 0
  fi

  if ! disable_proxmox_enterprise_repo; then
    echo "apt-get update failed and no Proxmox enterprise repository fallback was available." >&2
    exit 1
  fi

  if ! apt-get update; then
    restore_proxmox_enterprise_repo
    exit 1
  fi
  restore_proxmox_enterprise_repo
}

load_env_file() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  fi

  LISTEN_PORT="${PVE_DCV_PROXY_LISTEN_PORT:-${LISTEN_PORT}}"
  BACKEND_HOST="${PVE_DCV_PROXY_BACKEND_HOST:-${BACKEND_HOST}}"
  BACKEND_PORT="${PVE_DCV_PROXY_BACKEND_PORT:-${BACKEND_PORT}}"
  BACKEND_VMID="${PVE_DCV_PROXY_VMID:-${BACKEND_VMID}}"
  SERVER_NAME="${PVE_DCV_PROXY_SERVER_NAME:-${SERVER_NAME}}"
  DOWNLOADS_PATH="${PVE_DCV_DOWNLOADS_PATH:-${DOWNLOADS_PATH}}"
  DOWNLOADS_BASE_URL="${PVE_DCV_DOWNLOADS_BASE_URL:-${DOWNLOADS_BASE_URL}}"
  CERT_FILE="${PVE_DCV_PROXY_CERT_FILE:-${CERT_FILE}}"
  KEY_FILE="${PVE_DCV_PROXY_KEY_FILE:-${KEY_FILE}}"
}

first_guest_ipv4() {
  local vmid="$1"
  qm guest cmd "$vmid" network-get-interfaces 2>/dev/null | python3 - <<'PY'
import json
import sys

try:
    payload = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)

for iface in payload:
    for addr in iface.get("ip-addresses", []):
        ip = addr.get("ip-address", "")
        if addr.get("ip-address-type") != "ipv4":
            continue
        if ip.startswith("127.") or ip.startswith("169.254.") or not ip:
            continue
        print(ip)
        raise SystemExit(0)

raise SystemExit(1)
PY
}

decode_description() {
  python3 - "$1" <<'PY'
import sys
import urllib.parse

print(urllib.parse.unquote(sys.argv[1]))
PY
}

extract_meta_value() {
  local text="$1"
  local key="$2"
  printf '%s\n' "$text" | sed -n "s/^${key}:[[:space:]]*//p" | head -n1
}

dcv_url_matches_host() {
  local url="$1"
  local target_host="$2"
  local target_port="$3"

  python3 - "$url" "$target_host" "$target_port" <<'PY'
import sys
import urllib.parse

url = sys.argv[1]
target_host = sys.argv[2].lower()
target_port = int(sys.argv[3])
parsed = urllib.parse.urlparse(url)
host = (parsed.hostname or "").lower()
port = parsed.port or 8443
if host == target_host and port == target_port:
    raise SystemExit(0)
raise SystemExit(1)
PY
}

resolve_candidate_backend() {
  local vmid="$1"
  local raw_description description dcv_url dcv_ip

  raw_description="$(qm config "$vmid" 2>/dev/null | sed -n 's/^description: //p' | head -n1)"
  description="$(decode_description "${raw_description:-}")"
  dcv_url="$(extract_meta_value "$description" "dcv-url")"
  dcv_ip="$(extract_meta_value "$description" "dcv-ip")"

  if [[ -n "$BACKEND_VMID" && "$vmid" != "$BACKEND_VMID" ]]; then
    return 1
  fi

  if [[ -z "$BACKEND_VMID" ]]; then
    [[ -n "$dcv_url" ]] || return 1
    dcv_url_matches_host "$dcv_url" "$SERVER_NAME" "$LISTEN_PORT" || return 1
  fi

  if [[ -n "$dcv_ip" ]]; then
    printf '%s\n' "$dcv_ip"
    return 0
  fi

  first_guest_ipv4 "$vmid"
}

auto_detect_backend() {
  local candidates=()
  local vmid backend

  command -v qm >/dev/null 2>&1 || return 1

  while read -r vmid; do
    [[ -n "$vmid" ]] || continue
    backend="$(resolve_candidate_backend "$vmid" 2>/dev/null || true)"
    [[ -n "$backend" ]] || continue
    candidates+=("${vmid}:${backend}")
  done < <(qm list 2>/dev/null | awk 'NR > 1 {print $1}')

  if (( ${#candidates[@]} == 1 )); then
    BACKEND_VMID="${candidates[0]%%:*}"
    BACKEND_HOST="${candidates[0]#*:}"
    return 0
  fi

  if (( ${#candidates[@]} > 1 )); then
    log "Multiple DCV proxy candidates detected (${candidates[*]}). Set PVE_DCV_PROXY_VMID or PVE_DCV_PROXY_BACKEND_HOST explicitly."
  fi

  return 1
}

write_env_file() {
  install -d -m 0755 "$CONFIG_DIR"
  cat > "$ENV_FILE" <<EOF
PVE_DCV_PROXY_LISTEN_PORT="$LISTEN_PORT"
PVE_DCV_PROXY_BACKEND_HOST="$BACKEND_HOST"
PVE_DCV_PROXY_BACKEND_PORT="$BACKEND_PORT"
PVE_DCV_PROXY_VMID="$BACKEND_VMID"
PVE_DCV_PROXY_SERVER_NAME="$SERVER_NAME"
PVE_DCV_DOWNLOADS_PATH="$DOWNLOADS_PATH"
PVE_DCV_DOWNLOADS_BASE_URL="$DOWNLOADS_BASE_URL"
PVE_DCV_PROXY_CERT_FILE="$CERT_FILE"
PVE_DCV_PROXY_KEY_FILE="$KEY_FILE"
EOF
}

remove_rule_if_present() {
  local cmd="$1"
  if eval "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

cleanup_legacy_port_forward() {
  local rule delete_rule

  while IFS= read -r rule; do
    [[ "$rule" == *"--dport $LISTEN_PORT"* ]] || continue
    [[ "$rule" == *"--to-destination ${BACKEND_HOST}:${BACKEND_PORT}"* ]] || continue
    delete_rule="${rule/-A /-D }"
    iptables -t nat $delete_rule
  done < <(iptables -t nat -S PREROUTING 2>/dev/null || true)

  while IFS= read -r rule; do
    [[ "$rule" == *"--dport $LISTEN_PORT"* ]] || continue
    [[ "$rule" == *"-d ${BACKEND_HOST}/32"* ]] || continue
    delete_rule="${rule/-A /-D }"
    iptables $delete_rule
  done < <(iptables -S FORWARD 2>/dev/null || true)
}

write_nginx_config() {
  cat > "$NGINX_SITE" <<EOF
server {
    listen ${LISTEN_PORT} ssl;
    listen [::]:${LISTEN_PORT} ssl;
    server_name ${SERVER_NAME};

    ssl_certificate ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;

    location = /pve-dcv-autologin.js {
        alias ${ROOT_DIR}/proxmox-ui/pve-dcv-autologin.js;
        add_header Cache-Control "no-store";
    }

    location = ${DOWNLOADS_PATH} {
        return 302 ${DOWNLOADS_PATH}/;
    }

    location ^~ ${DOWNLOADS_PATH}/ {
        alias ${ROOT_DIR}/dist/;
        index pve-dcv-downloads-index.html;
        add_header Cache-Control "no-store";
        autoindex on;
        types {
            application/x-sh sh;
            text/plain txt;
        }
    }

EOF

  if [[ -n "$BACKEND_HOST" ]]; then
    cat >> "$NGINX_SITE" <<EOF
    location / {
        proxy_pass https://${BACKEND_HOST}:${BACKEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Accept-Encoding "";
        proxy_ssl_server_name on;
        proxy_ssl_verify off;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        sub_filter_once on;
        sub_filter '</body>' '<script src="/pve-dcv-autologin.js"></script></body>';
    }
}
EOF
    return 0
  fi

  cat >> "$NGINX_SITE" <<EOF
    location = / {
        default_type text/html;
        return 200 '<!doctype html><html><head><meta charset="utf-8"><title>PVE DCV Integration</title></head><body><h1>PVE DCV Integration</h1><p>Host-local downloads are available under <a href="${DOWNLOADS_PATH}/">${DOWNLOADS_PATH}/</a>.</p></body></html>';
    }

    location / {
        return 404;
    }
}
EOF
}

link_nginx_config() {
  ln -sfn "$NGINX_SITE" "$NGINX_ENABLED"
  if [[ -f /etc/nginx/sites-enabled/default ]]; then
    rm -f /etc/nginx/sites-enabled/default
  fi
}

ensure_root "$@"
load_env_file
ensure_dependencies

[[ -r "$CERT_FILE" ]] || {
  echo "Certificate file not found: $CERT_FILE" >&2
  exit 1
}
[[ -r "$KEY_FILE" ]] || {
  echo "Certificate key not found: $KEY_FILE" >&2
  exit 1
}

if [[ -z "$BACKEND_HOST" ]]; then
  if ! auto_detect_backend; then
    log "No DCV backend detected. Configuring downloads-only HTTPS endpoint on https://${SERVER_NAME}:${LISTEN_PORT}${DOWNLOADS_PATH}/."
  fi
fi

write_env_file
cleanup_legacy_port_forward
write_nginx_config
link_nginx_config
nginx -t
systemctl enable --now nginx
systemctl reload nginx
if [[ -n "$BACKEND_HOST" ]]; then
  log "Configured DCV TLS proxy on https://${SERVER_NAME}:${LISTEN_PORT}/ -> https://${BACKEND_HOST}:${BACKEND_PORT}/"
else
  log "Configured host-local HTTPS downloads on ${DOWNLOADS_BASE_URL%/}/"
fi
