#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LB_TEMPLATE_DIR="$ROOT_DIR/thin-client-assistant/live-build"
BUILD_DIR="$ROOT_DIR/.build/pve-thin-client-live-build"
DIST_DIR="$ROOT_DIR/dist/pve-thin-client-installer"
THINCLIENT_ARCH="${THINCLIENT_ARCH:-amd64}"

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  live-build \
  debootstrap \
  squashfs-tools \
  xorriso \
  dosfstools \
  mtools \
  rsync \
  curl \
  ca-certificates

sudo rm -rf "$BUILD_DIR"
sudo install -d -m 0755 "$BUILD_DIR" "$DIST_DIR/live"
sudo rsync -a --delete "$LB_TEMPLATE_DIR/" "$BUILD_DIR/"

sudo install -d -m 0755 "$BUILD_DIR/config/includes.chroot/usr/local/lib"
sudo rsync -a --delete "$ROOT_DIR/thin-client-assistant/" "$BUILD_DIR/config/includes.chroot/usr/local/lib/pve-thin-client/"
sudo chmod 0755 "$BUILD_DIR"

pushd "$BUILD_DIR" >/dev/null
sudo chmod +x auto/config
THINCLIENT_ARCH="$THINCLIENT_ARCH" ./auto/config
sudo lb clean --purge || true
BUILD_RC=0
if ! sudo lb build; then
  BUILD_RC=$?
fi
popd >/dev/null

sudo chown -R "$(id -u):$(id -g)" "$BUILD_DIR"
chmod -R u+rwX "$DIST_DIR"

mapfile -t kernel_images < <(find "$BUILD_DIR/binary/live" -maxdepth 1 -type f -name 'vmlinuz*' | sort)
mapfile -t initrd_images < <(find "$BUILD_DIR/binary/live" -maxdepth 1 -type f -name 'initrd.img*' | sort)

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
