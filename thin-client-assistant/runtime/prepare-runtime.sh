#!/usr/bin/env bash
set -euo pipefail

STATUS_DIR="${STATUS_DIR:-/var/lib/pve-thin-client}"
STATUS_FILE="$STATUS_DIR/runtime.status"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_runtime_config

sync_runtime_config_to_system() {
  local target_dir="/etc/pve-thin-client"
  local source_dir="${CONFIG_DIR:-}"
  local file=""
  local copied=0

  [[ -n "$source_dir" ]] || return 0
  [[ "$source_dir" != "$target_dir" ]] || return 0
  [[ -d "$source_dir" ]] || return 0

  install -d -m 0755 "$target_dir"
  for file in thinclient.conf network.env credentials.env; do
    if [[ -f "$source_dir/$file" ]]; then
      install -m 0644 "$source_dir/$file" "$target_dir/$file"
      copied=1
    fi
  done

  if [[ "$copied" == "1" ]]; then
    CONFIG_DIR="$target_dir"
    CONFIG_FILE="$target_dir/thinclient.conf"
    NETWORK_FILE="$target_dir/network.env"
    CREDENTIALS_FILE="$target_dir/credentials.env"
  fi
}

ensure_runtime_user() {
  local runtime_user shell_path

  runtime_user="${PVE_THIN_CLIENT_RUNTIME_USER:-thinclient}"
  if [[ -x /usr/local/bin/beagle-login-shell ]]; then
    shell_path="/usr/local/bin/beagle-login-shell"
  elif [[ -x /usr/local/bin/pve-thin-client-login-shell ]]; then
    shell_path="/usr/local/bin/pve-thin-client-login-shell"
  else
    shell_path="/bin/bash"
  fi

  if ! id "$runtime_user" >/dev/null 2>&1; then
    useradd -m -s "$shell_path" -G audio,video,plugdev,users,netdev "$runtime_user" >/dev/null 2>&1 || true
  fi

  usermod -s "$shell_path" "$runtime_user" >/dev/null 2>&1 || true

  if [[ "$runtime_user" == "thinclient" ]]; then
    printf '%s:%s\n' "thinclient" "thinclient" | chpasswd >/dev/null 2>&1 || true
  fi
}

strip_managed_ssh_block() {
  local src_file="$1"
  local begin_marker="$2"
  local end_marker="$3"

  awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin {skip = 1; next}
    $0 == end {skip = 0; next}
    !skip {print}
  ' "$src_file"
}

apply_runtime_ssh_config() {
  local sshd_config begin_marker end_marker temp_file

  sshd_config="${PVE_THIN_CLIENT_SSHD_CONFIG:-/etc/ssh/sshd_config}"
  begin_marker="# --- pve-thin-client managed ssh begin ---"
  end_marker="# --- pve-thin-client managed ssh end ---"

  [[ -f "$sshd_config" ]] || return 0

  temp_file="$(mktemp)"
  strip_managed_ssh_block "$sshd_config" "$begin_marker" "$end_marker" >"$temp_file" || cp -f "$sshd_config" "$temp_file"

  {
    cat "$temp_file"
    printf '\n%s\n' "$begin_marker"
    printf 'PasswordAuthentication yes\n'
    printf 'KbdInteractiveAuthentication yes\n'
    printf 'PermitEmptyPasswords no\n'
    printf 'PermitRootLogin no\n'
    printf '%s\n' "$end_marker"
  } >"$sshd_config"

  rm -f "$temp_file"
  chmod 0600 "$sshd_config" >/dev/null 2>&1 || true

  if command -v sshd >/dev/null 2>&1 && sshd -t -f "$sshd_config" >/dev/null 2>&1; then
    systemctl restart ssh.service >/dev/null 2>&1 || true
  fi
}

normalize_boot_services() {
  local boot_mode
  boot_mode="$(/usr/local/bin/pve-thin-client-boot-mode 2>/dev/null || printf 'runtime')"

  case "$boot_mode" in
    runtime)
      systemctl list-unit-files pve-thin-client-runtime.service >/dev/null 2>&1 && \
        systemctl enable pve-thin-client-runtime.service >/dev/null 2>&1 || true
      systemctl list-unit-files pve-thin-client-installer-menu.service >/dev/null 2>&1 && \
        systemctl disable pve-thin-client-installer-menu.service >/dev/null 2>&1 || true
      systemctl disable getty@tty1.service >/dev/null 2>&1 || true
      ;;
    installer)
      systemctl list-unit-files pve-thin-client-installer-menu.service >/dev/null 2>&1 && \
        systemctl enable pve-thin-client-installer-menu.service >/dev/null 2>&1 || true
      systemctl list-unit-files pve-thin-client-runtime.service >/dev/null 2>&1 && \
        systemctl disable pve-thin-client-runtime.service >/dev/null 2>&1 || true
      systemctl disable getty@tty1.service >/dev/null 2>&1 || true
      ;;
    *)
      systemctl enable getty@tty1.service >/dev/null 2>&1 || true
      ;;
  esac
}

if [[ -x "$SCRIPT_DIR/apply-network-config.sh" ]]; then
  "$SCRIPT_DIR/apply-network-config.sh"
fi

sync_runtime_config_to_system
ensure_runtime_user
apply_runtime_ssh_config
normalize_boot_services

mkdir -p "$STATUS_DIR"
chmod 0755 "$STATUS_DIR"

required_binary=""
case "${PVE_THIN_CLIENT_MODE:-MOONLIGHT}" in
  MOONLIGHT)
    required_binary="${PVE_THIN_CLIENT_MOONLIGHT_BIN:-moonlight}"
    ;;
  *)
    echo "Unsupported mode for Beagle OS: ${PVE_THIN_CLIENT_MODE:-UNSET}" >&2
    exit 1
    ;;
esac

{
  echo "timestamp=$(date -Iseconds)"
  echo "mode=${PVE_THIN_CLIENT_MODE:-UNSET}"
  echo "runtime_user=${PVE_THIN_CLIENT_RUNTIME_USER:-UNSET}"
  echo "connection_method=${PVE_THIN_CLIENT_CONNECTION_METHOD:-UNSET}"
  echo "profile_name=${PVE_THIN_CLIENT_PROFILE_NAME:-UNSET}"
  echo "required_binary=$required_binary"
  echo "moonlight_host=${PVE_THIN_CLIENT_MOONLIGHT_HOST:-UNSET}"
  echo "moonlight_app=${PVE_THIN_CLIENT_MOONLIGHT_APP:-Desktop}"
  if command -v "$required_binary" >/dev/null 2>&1; then
    echo "binary_available=1"
  else
    echo "binary_available=0"
  fi
} > "$STATUS_FILE"

chmod 0644 "$STATUS_FILE"
