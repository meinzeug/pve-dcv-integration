#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LB_TEMPLATE_DIR="$ROOT_DIR/thin-client-assistant/live-build"
BUILD_DIR="$ROOT_DIR/.build/pve-thin-client-live-build"
DIST_DIR="$ROOT_DIR/dist/pve-thin-client-installer"
THINCLIENT_ARCH="${THINCLIENT_ARCH:-amd64}"
OWNER_UID="${SUDO_UID:-$(id -u)}"
OWNER_GID="${SUDO_GID:-$(id -g)}"
MOONLIGHT_URL="${PVE_THIN_CLIENT_MOONLIGHT_URL:-https://github.com/moonlight-stream/moonlight-qt/releases/download/v6.1.0/Moonlight-6.1.0-x86_64.AppImage}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

ensure_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    return 0
  fi

  exec sudo THINCLIENT_ARCH="$THINCLIENT_ARCH" "$0" "$@"
}

disable_proxmox_enterprise_repo() {
  local found=0
  local file

  while IFS= read -r file; do
    grep -q 'enterprise.proxmox.com' "$file" || continue
    cp "$file" "$file.beagle-backup"
    awk '!/enterprise\.proxmox\.com/' "$file.beagle-backup" > "$file"
    found=1
  done < <(find /etc/apt -maxdepth 2 -type f \( -name '*.list' -o -name '*.sources' \) 2>/dev/null)

  return $(( ! found ))
}

restore_proxmox_enterprise_repo() {
  local backup original

  while IFS= read -r backup; do
    original="${backup%.beagle-backup}"
    mv "$backup" "$original"
  done < <(find /etc/apt -maxdepth 2 -type f -name '*.beagle-backup' 2>/dev/null)
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

ensure_root "$@"
apt_update_with_proxmox_fallback
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  live-build \
  debootstrap \
  squashfs-tools \
  xorriso \
  dosfstools \
  mtools \
  rsync \
  curl \
  ca-certificates

stage_moonlight_assets() {
  local work_dir target_dir wrapper_path

  work_dir="$(mktemp -d)"
  target_dir="$BUILD_DIR/config/includes.chroot/opt/moonlight"
  wrapper_path="$BUILD_DIR/config/includes.chroot/usr/local/bin/moonlight"

  cleanup_stage() {
    rm -rf "$work_dir"
  }
  trap cleanup_stage RETURN

  curl -fL \
    --retry 8 \
    --retry-delay 3 \
    --retry-connrefused \
    --continue-at - \
    --speed-limit 5000 \
    --speed-time 30 \
    -o "$work_dir/Moonlight.AppImage" \
    "$MOONLIGHT_URL"

  chmod +x "$work_dir/Moonlight.AppImage"
  (
    cd "$work_dir"
    ./Moonlight.AppImage --appimage-extract >/dev/null
  )

  rm -rf "$target_dir"
  install -d -m 0755 "$target_dir" "$(dirname "$wrapper_path")"
  cp -a "$work_dir/squashfs-root/." "$target_dir/"

  cat > "$wrapper_path" <<'EOF'
#!/bin/sh
set -eu

APPDIR="/opt/moonlight"
export APPDIR
export QT_PLUGIN_PATH="${APPDIR}/usr/plugins"
export QML2_IMPORT_PATH="${APPDIR}/usr/qml"
export QT_XKB_CONFIG_ROOT="/usr/share/X11/xkb"
export LD_LIBRARY_PATH="${APPDIR}/usr/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

exec "${APPDIR}/usr/bin/moonlight" "$@"
EOF
  chmod 0755 "$wrapper_path"
}

rm -rf "$BUILD_DIR"
install -d -m 0755 "$BUILD_DIR" "$DIST_DIR/live"
rsync -a --delete "$LB_TEMPLATE_DIR/" "$BUILD_DIR/"

install -d -m 0755 "$BUILD_DIR/config/includes.chroot/usr/local/lib"
rsync -a --delete \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  "$ROOT_DIR/thin-client-assistant/" \
  "$BUILD_DIR/config/includes.chroot/usr/local/lib/pve-thin-client/"
stage_moonlight_assets
chmod 0755 "$BUILD_DIR"

pushd "$BUILD_DIR" >/dev/null
chmod +x auto/config
THINCLIENT_ARCH="$THINCLIENT_ARCH" ./auto/config
lb clean --purge || true
BUILD_RC=0
if ! lb build; then
  BUILD_RC=$?
fi
popd >/dev/null

chown -R "$OWNER_UID:$OWNER_GID" "$BUILD_DIR" "$DIST_DIR"
chmod -R u+rwX,go+rX "$DIST_DIR"
find "$DIST_DIR" -type f -name '*.sh' -exec chmod 0755 {} +

mapfile -t kernel_images < <(find "$BUILD_DIR/binary/live" -maxdepth 1 -type f -name 'vmlinuz*' | sort)
mapfile -t initrd_images < <(find "$BUILD_DIR/binary/live" -maxdepth 1 -type f -name 'initrd.img*' | sort)

# Newer live-build paths can leave kernel/initrd in chroot/boot even when
# binary/live only contains filesystem.squashfs.
if [[ "${#kernel_images[@]}" -eq 0 ]]; then
  mapfile -t kernel_images < <(find "$BUILD_DIR/chroot/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | sort)
fi
if [[ "${#initrd_images[@]}" -eq 0 ]]; then
  mapfile -t initrd_images < <(find "$BUILD_DIR/chroot/boot" -maxdepth 1 -type f -name 'initrd.img-*' | sort)
fi

if [[ "${#kernel_images[@]}" -eq 0 || "${#initrd_images[@]}" -eq 0 || ! -f "$BUILD_DIR/binary/live/filesystem.squashfs" ]]; then
  echo "Thin client build did not produce the required live assets." >&2
  exit "${BUILD_RC:-1}"
fi

install -m 0644 "${kernel_images[0]}" "$DIST_DIR/live/vmlinuz"
install -m 0644 "${initrd_images[0]}" "$DIST_DIR/live/initrd.img"
install -m 0644 "$BUILD_DIR/binary/live/filesystem.squashfs" "$DIST_DIR/live/filesystem.squashfs"

(
  cd "$DIST_DIR/live"
  sha256sum vmlinuz initrd.img filesystem.squashfs > SHA256SUMS
)

if [[ -f "$BUILD_DIR/live-image-${THINCLIENT_ARCH}.hybrid.iso" ]]; then
  install -m 0644 "$BUILD_DIR/live-image-${THINCLIENT_ARCH}.hybrid.iso" "$DIST_DIR/pve-thin-client-installer-${THINCLIENT_ARCH}.iso"
  install -m 0644 "$BUILD_DIR/live-image-${THINCLIENT_ARCH}.hybrid.iso" "$DIST_DIR/pve-thin-client-installer.iso"
elif [[ "${BUILD_RC}" -ne 0 ]]; then
  echo "Live assets are ready, but ISO packaging failed in live-build; continuing without a local ISO." >&2
fi

echo "Built PVE Thin Client installer assets in $DIST_DIR"
