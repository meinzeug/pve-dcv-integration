#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_runtime_config

RUNTIME_NETWORK_DIR="${RUNTIME_NETWORK_DIR:-/run/systemd/network}"
NETWORK_FILE="$RUNTIME_NETWORK_DIR/90-pve-thin-client.network"
NM_CONNECTION_DIR="${NM_CONNECTION_DIR:-/etc/NetworkManager/system-connections}"
NM_CONNECTION_FILE="$NM_CONNECTION_DIR/beagle-thinclient.nmconnection"
RESOLV_CONF="${RESOLV_CONF:-/etc/resolv.conf}"
DEFAULT_DNS_SERVERS="${PVE_THIN_CLIENT_DEFAULT_DNS_SERVERS:-1.1.1.1 9.9.9.9 8.8.8.8}"
NETWORK_WAIT_TIMEOUT="${PVE_THIN_CLIENT_NETWORK_WAIT_TIMEOUT:-20}"

pick_interface() {
  local candidate="${PVE_THIN_CLIENT_NETWORK_INTERFACE:-}"
  local iface

  if [[ -n "$candidate" && -d "/sys/class/net/$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  while IFS= read -r iface; do
    [[ "$iface" == "lo" ]] && continue
    case "$iface" in
      docker*|virbr*|veth*|br-*|tun*|tap*|wg*|zt*|vmnet*|tailscale*) continue ;;
    esac
    printf '%s\n' "$iface"
    return 0
  done < <(ls /sys/class/net)

  return 1
}

write_network_file() {
  local iface="$1"
  local dns_servers
  install -d -m 0755 "$RUNTIME_NETWORK_DIR"
  dns_servers="$(resolve_dns_servers)"

  {
    echo "[Match]"
    echo "Name=$iface"
    echo
    echo "[Network]"
    if [[ "${PVE_THIN_CLIENT_NETWORK_MODE:-dhcp}" == "static" ]]; then
      echo "Address=${PVE_THIN_CLIENT_NETWORK_STATIC_ADDRESS}/${PVE_THIN_CLIENT_NETWORK_STATIC_PREFIX:-24}"
      [[ -n "${PVE_THIN_CLIENT_NETWORK_GATEWAY:-}" ]] && echo "Gateway=${PVE_THIN_CLIENT_NETWORK_GATEWAY}"
      echo "DHCP=no"
    else
      echo "DHCP=yes"
    fi
    for dns in $dns_servers; do
      echo "DNS=$dns"
    done
  } >"$NETWORK_FILE"
}

write_nmconnection() {
  local iface="$1"
  local dns_servers dns_csv address_line

  install -d -m 0700 "$NM_CONNECTION_DIR"
  dns_servers="$(resolve_dns_servers)"
  dns_csv="$(printf '%s\n' "$dns_servers" | tr ' ' ',' | sed 's/,$//')"

  {
    echo "[connection]"
    echo "id=beagle-thinclient"
    echo "uuid=3f5f30fe-1b98-45e1-a7ef-79f3f0cdfb27"
    echo "type=ethernet"
    echo "autoconnect=true"
    [[ -n "$iface" ]] && echo "interface-name=$iface"
    echo
    echo "[ethernet]"
    echo
    echo "[ipv4]"
    if [[ "${PVE_THIN_CLIENT_NETWORK_MODE:-dhcp}" == "static" ]]; then
      echo "method=manual"
      address_line="${PVE_THIN_CLIENT_NETWORK_STATIC_ADDRESS}/${PVE_THIN_CLIENT_NETWORK_STATIC_PREFIX:-24}"
      if [[ -n "${PVE_THIN_CLIENT_NETWORK_GATEWAY:-}" ]]; then
        address_line="${address_line},${PVE_THIN_CLIENT_NETWORK_GATEWAY}"
      fi
      echo "address1=${address_line}"
    else
      echo "method=auto"
    fi
    if [[ -n "$dns_csv" ]]; then
      echo "dns=$dns_csv;"
      echo "ignore-auto-dns=true"
    fi
    echo
    echo "[ipv6]"
    echo "method=ignore"
    echo
    echo "[proxy]"
  } >"$NM_CONNECTION_FILE"

  chmod 0600 "$NM_CONNECTION_FILE"
}

resolve_dns_servers() {
  if [[ -n "${PVE_THIN_CLIENT_NETWORK_DNS_SERVERS:-}" ]]; then
    printf '%s\n' "${PVE_THIN_CLIENT_NETWORK_DNS_SERVERS}"
    return 0
  fi

  printf '%s\n' "$DEFAULT_DNS_SERVERS"
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

extract_host_from_url() {
  python3 - "$1" <<'PY'
from urllib.parse import urlparse
import sys

text = (sys.argv[1] or "").strip()
if not text:
    raise SystemExit(0)

parsed = urlparse(text if "://" in text else f"https://{text}")
if parsed.hostname:
    print(parsed.hostname)
PY
}

dns_wait_targets() {
  local host
  local -a raw_targets=(
    "${PVE_THIN_CLIENT_PROXMOX_HOST:-}"
    "${PVE_THIN_CLIENT_MOONLIGHT_HOST:-}"
    "$(extract_host_from_url "${PVE_THIN_CLIENT_SUNSHINE_API_URL:-}" 2>/dev/null || true)"
  )

  for host in "${raw_targets[@]}"; do
    [[ -n "$host" ]] || continue
    printf '%s\n' "$host"
  done | awk '!seen[$0]++'
}

host_has_ipv4() {
  local host="$1"

  [[ -n "$host" ]] || return 0
  if is_ip_literal "$host"; then
    return 0
  fi

  getent ahostsv4 "$host" >/dev/null 2>&1
}

wait_for_default_route() {
  local remaining="$NETWORK_WAIT_TIMEOUT"
  while (( remaining > 0 )); do
    if ip route show default 2>/dev/null | grep -q .; then
      return 0
    fi
    sleep 1
    remaining=$((remaining - 1))
  done
  return 1
}

wait_for_dns_targets() {
  local remaining="$NETWORK_WAIT_TIMEOUT"
  local target unresolved

  while (( remaining > 0 )); do
    unresolved=""
    while IFS= read -r target; do
      [[ -n "$target" ]] || continue
      if ! host_has_ipv4 "$target"; then
        unresolved="$target"
        break
      fi
    done < <(dns_wait_targets)

    [[ -z "$unresolved" ]] && return 0
    sleep 1
    remaining=$((remaining - 1))
  done

  return 1
}

apply_hostname() {
  local hostname_value="${PVE_THIN_CLIENT_HOSTNAME:-}"
  [[ -n "$hostname_value" ]] || return 0

  if command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "$hostname_value" >/dev/null 2>&1 || true
  else
    printf '%s\n' "$hostname_value" > /etc/hostname
    hostname "$hostname_value" >/dev/null 2>&1 || true
  fi
}

restart_networkd() {
  if command -v systemctl >/dev/null 2>&1 && systemctl is-enabled systemd-networkd.service >/dev/null 2>&1; then
    systemctl restart systemd-networkd.service >/dev/null 2>&1 || true
  elif command -v systemctl >/dev/null 2>&1 && systemctl is-active systemd-networkd.service >/dev/null 2>&1; then
    systemctl restart systemd-networkd.service >/dev/null 2>&1 || true
  fi
}

have_networkmanager() {
  command -v nmcli >/dev/null 2>&1 || systemctl list-unit-files 2>/dev/null | grep -q '^NetworkManager\.service'
}

restart_networkmanager() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable NetworkManager.service >/dev/null 2>&1 || true
    systemctl restart NetworkManager.service >/dev/null 2>&1 || true
  fi

  if command -v nmcli >/dev/null 2>&1; then
    nmcli connection reload >/dev/null 2>&1 || true
    nmcli connection up beagle-thinclient >/dev/null 2>&1 || true
  fi
}

write_resolv_conf() {
  local dns_servers
  if [[ -L "$RESOLV_CONF" || ( -e "$RESOLV_CONF" && ! -w "$RESOLV_CONF" ) ]]; then
    return 0
  fi

  dns_servers="$(resolve_dns_servers)"

  {
    for dns in $dns_servers; do
      printf 'nameserver %s\n' "$dns"
    done
  } >"$RESOLV_CONF"

  chmod 0644 "$RESOLV_CONF"
}

main() {
  local iface

  iface="$(pick_interface)" || exit 0
  if have_networkmanager; then
    write_nmconnection "$iface"
    restart_networkmanager
  else
    write_network_file "$iface"
    restart_networkd
  fi
  apply_hostname
  write_resolv_conf || true
  wait_for_default_route || true
  wait_for_dns_targets || true
}

main "$@"
