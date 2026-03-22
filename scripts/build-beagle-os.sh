#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${BEAGLE_OS_WORK_DIR:-$ROOT_DIR/.build/beagle-os}"
OUT_DIR="${BEAGLE_OS_OUT_DIR:-$ROOT_DIR/dist/beagle-os}"
ROOTFS_DIR="$WORK_DIR/rootfs"
MOUNT_DIR="$WORK_DIR/mnt"
PROFILE_DIR="${BEAGLE_OS_PROFILE_DIR:-$ROOT_DIR/beagle-os}"
PACKAGE_LIST_FILE="$PROFILE_DIR/packages/base.list"
OVERLAY_DIR="$PROFILE_DIR/overlay"

DEBIAN_RELEASE="${BEAGLE_OS_RELEASE:-bookworm}"
DEBIAN_ARCH="${BEAGLE_OS_ARCH:-amd64}"
DEBIAN_MIRROR="${BEAGLE_OS_MIRROR:-http://deb.debian.org/debian}"
HOSTNAME_VALUE="${BEAGLE_OS_HOSTNAME:-beagle-os}"
RUNTIME_USER="${BEAGLE_OS_USER:-thinclient}"
IMAGE_SIZE_GB="${BEAGLE_OS_IMAGE_SIZE_GB:-8}"
JOBS="${BEAGLE_OS_JOBS:-$(nproc)}"
MOONLIGHT_URL="${BEAGLE_OS_MOONLIGHT_URL:-https://github.com/moonlight-stream/moonlight-qt/releases/download/v6.1.0/Moonlight-6.1.0-x86_64.AppImage}"
MOONLIGHT_HOST="${BEAGLE_OS_MOONLIGHT_HOST:-}"
MOONLIGHT_APP="${BEAGLE_OS_MOONLIGHT_APP:-Desktop}"
MOONLIGHT_RESOLUTION="${BEAGLE_OS_MOONLIGHT_RESOLUTION:-auto}"
MOONLIGHT_FPS="${BEAGLE_OS_MOONLIGHT_FPS:-60}"
MOONLIGHT_BITRATE="${BEAGLE_OS_MOONLIGHT_BITRATE:-20000}"
SUNSHINE_API_URL="${BEAGLE_OS_SUNSHINE_API_URL:-}"
SUNSHINE_USERNAME="${BEAGLE_OS_SUNSHINE_USERNAME:-}"
SUNSHINE_PASSWORD="${BEAGLE_OS_SUNSHINE_PASSWORD:-}"
SUNSHINE_PIN="${BEAGLE_OS_SUNSHINE_PIN:-}"
PROXMOX_HOST="${BEAGLE_OS_PROXMOX_HOST:-}"
PROXMOX_NODE="${BEAGLE_OS_PROXMOX_NODE:-}"
PROXMOX_VMID="${BEAGLE_OS_PROXMOX_VMID:-}"
MANAGER_URL="${BEAGLE_OS_MANAGER_URL:-}"
MANAGER_TOKEN="${BEAGLE_OS_MANAGER_TOKEN:-}"

KERNEL_VERSION="${BEAGLE_OS_KERNEL_VERSION:-6.12.22}"
KERNEL_LOCALVERSION="${BEAGLE_OS_KERNEL_LOCALVERSION:--beagle}"
KERNEL_SRC_URL="${BEAGLE_OS_KERNEL_SRC_URL:-}"
KERNEL_IMAGE_DEB="${BEAGLE_OS_KERNEL_DEB_PATH:-}"
SKIP_KERNEL_BUILD="${BEAGLE_OS_SKIP_KERNEL_BUILD:-0}"

LOOP_DEV=""
ROOTFS_CHROOT_MOUNTS=()
IMAGE_CHROOT_MOUNTS=()

usage() {
  cat <<'USAGE'
Build an own Beagle OS image with a custom kernel package.

Usage:
  ./scripts/build-beagle-os.sh [options]

Options:
  --release <name>            Debian release (default: bookworm)
  --arch <arch>               Architecture (default: amd64)
  --mirror <url>              Debian mirror URL
  --kernel-version <ver>      Linux kernel version (default: 6.12.22)
  --kernel-localversion <str> Kernel localversion suffix (default: -beagle)
  --kernel-deb <path>         Reuse existing linux-image .deb package
  --skip-kernel-build         Skip kernel build and use --kernel-deb
  --hostname <name>           Hostname inside image (default: beagle-os)
  --user <name>               Runtime user (default: thinclient)
  --image-size-gb <n>         Raw disk size in GiB (default: 8)
  --work-dir <path>           Build workspace (default: .build/beagle-os)
  --out-dir <path>            Artifact output directory (default: dist/beagle-os)
  --profile-dir <path>        OS profile directory (default: beagle-os/)
  -h, --help                  Show this help
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --release) DEBIAN_RELEASE="$2"; shift 2 ;;
      --arch) DEBIAN_ARCH="$2"; shift 2 ;;
      --mirror) DEBIAN_MIRROR="$2"; shift 2 ;;
      --kernel-version) KERNEL_VERSION="$2"; shift 2 ;;
      --kernel-localversion) KERNEL_LOCALVERSION="$2"; shift 2 ;;
      --kernel-deb) KERNEL_IMAGE_DEB="$2"; shift 2 ;;
      --skip-kernel-build) SKIP_KERNEL_BUILD="1"; shift ;;
      --hostname) HOSTNAME_VALUE="$2"; shift 2 ;;
      --user) RUNTIME_USER="$2"; shift 2 ;;
      --image-size-gb) IMAGE_SIZE_GB="$2"; shift 2 ;;
      --work-dir)
        WORK_DIR="$2"
        ROOTFS_DIR="$2/rootfs"
        MOUNT_DIR="$2/mnt"
        shift 2
        ;;
      --out-dir) OUT_DIR="$2"; shift 2 ;;
      --profile-dir) PROFILE_DIR="$2"; PACKAGE_LIST_FILE="$2/packages/base.list"; OVERLAY_DIR="$2/overlay"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

require_root() {
  if [[ "$EUID" -eq 0 ]]; then
    return
  fi
  exec sudo --preserve-env=BEAGLE_OS_RELEASE,BEAGLE_OS_ARCH,BEAGLE_OS_MIRROR,BEAGLE_OS_KERNEL_VERSION,BEAGLE_OS_KERNEL_LOCALVERSION,BEAGLE_OS_KERNEL_DEB_PATH,BEAGLE_OS_SKIP_KERNEL_BUILD,BEAGLE_OS_HOSTNAME,BEAGLE_OS_USER,BEAGLE_OS_IMAGE_SIZE_GB,BEAGLE_OS_WORK_DIR,BEAGLE_OS_OUT_DIR,BEAGLE_OS_JOBS,BEAGLE_OS_PROFILE_DIR,BEAGLE_OS_MOONLIGHT_URL,BEAGLE_OS_MOONLIGHT_HOST,BEAGLE_OS_MOONLIGHT_APP,BEAGLE_OS_MOONLIGHT_RESOLUTION,BEAGLE_OS_MOONLIGHT_FPS,BEAGLE_OS_MOONLIGHT_BITRATE,BEAGLE_OS_SUNSHINE_API_URL,BEAGLE_OS_SUNSHINE_USERNAME,BEAGLE_OS_SUNSHINE_PASSWORD,BEAGLE_OS_SUNSHINE_PIN,BEAGLE_OS_PROXMOX_HOST,BEAGLE_OS_PROXMOX_NODE,BEAGLE_OS_PROXMOX_VMID,BEAGLE_OS_MANAGER_URL,BEAGLE_OS_MANAGER_TOKEN "$0" "$@"
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

install_dependencies() {
  export DEBIAN_FRONTEND=noninteractive
  apt_update_with_proxmox_fallback
  apt-get install -y \
    debootstrap \
    curl \
    xz-utils \
    tar \
    build-essential \
    debhelper \
    bc \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    dwarves \
    fakeroot \
    rsync \
    parted \
    dosfstools \
    e2fsprogs \
    grub-efi-amd64-bin \
    grub2-common \
    initramfs-tools \
    qemu-utils \
    ca-certificates \
    gdisk
}

cleanup_mounts() {
  local -n mounts_ref="$1"
  local idx
  for (( idx=${#mounts_ref[@]}-1; idx>=0; idx-- )); do
    if mountpoint -q "${mounts_ref[$idx]}"; then
      umount "${mounts_ref[$idx]}" || true
    fi
  done
  mounts_ref=()
}

cleanup() {
  cleanup_mounts IMAGE_CHROOT_MOUNTS
  cleanup_mounts ROOTFS_CHROOT_MOUNTS

  if [[ -n "$LOOP_DEV" ]]; then
    losetup -d "$LOOP_DEV" || true
    LOOP_DEV=""
  fi
}
trap cleanup EXIT

mount_chroot_fs() {
  local target="$1"
  local array_name="$2"
  local -n mount_array="$array_name"

  mount --bind /dev "$target/dev"
  mount_array+=("$target/dev")

  mount -t devpts devpts "$target/dev/pts"
  mount_array+=("$target/dev/pts")

  mount -t proc proc "$target/proc"
  mount_array+=("$target/proc")

  mount -t sysfs sysfs "$target/sys"
  mount_array+=("$target/sys")

  mount --bind /run "$target/run"
  mount_array+=("$target/run")
}

chroot_run_rootfs() {
  chroot "$ROOTFS_DIR" /usr/bin/env DEBIAN_FRONTEND=noninteractive bash -lc "$*"
}

host_preflight() {
  local work_parent out_parent need_kib=0 avail_work=0 avail_out=0
  local symlink_probe_dir symlink_target symlink_link

  work_parent="$(dirname "$WORK_DIR")"
  out_parent="$(dirname "$OUT_DIR")"

  mkdir -p "$WORK_DIR" "$OUT_DIR"

  if [[ "$SKIP_KERNEL_BUILD" == "1" ]]; then
    need_kib=$((10 * 1024 * 1024))
  else
    need_kib=$((20 * 1024 * 1024))
  fi

  avail_work="$(df -Pk "$work_parent" | awk 'NR==2 {print $4}')"
  avail_out="$(df -Pk "$out_parent" | awk 'NR==2 {print $4}')"

  if (( avail_work < need_kib )); then
    echo "Insufficient free space for WORK_DIR on $work_parent. Need at least $((need_kib / 1024 / 1024)) GiB free." >&2
    exit 1
  fi

  if (( avail_out < 4 * 1024 * 1024 )); then
    echo "Insufficient free space for OUT_DIR on $out_parent. Need at least 4 GiB free." >&2
    exit 1
  fi

  symlink_probe_dir="$WORK_DIR/.fs-probe"
  symlink_target="$symlink_probe_dir/target"
  symlink_link="$symlink_probe_dir/link"
  rm -rf "$symlink_probe_dir"
  mkdir -p "$symlink_probe_dir"
  : > "$symlink_target"
  if ! ln -s "$symlink_target" "$symlink_link" 2>/dev/null; then
    echo "WORK_DIR filesystem does not support symlinks: $WORK_DIR" >&2
    echo "Use a POSIX filesystem such as ext4 for the Beagle OS build workspace." >&2
    exit 1
  fi
  rm -rf "$symlink_probe_dir"
}

read_package_list() {
  if [[ ! -f "$PACKAGE_LIST_FILE" ]]; then
    echo "Package list is missing: $PACKAGE_LIST_FILE" >&2
    exit 1
  fi

  awk '
    /^[[:space:]]*#/ {next}
    /^[[:space:]]*$/ {next}
    {print $1}
  ' "$PACKAGE_LIST_FILE"
}

download_kernel_source() {
  local major url tarball
  major="${KERNEL_VERSION%%.*}"
  url="$KERNEL_SRC_URL"

  if [[ -z "$url" ]]; then
    url="https://cdn.kernel.org/pub/linux/kernel/v${major}.x/linux-${KERNEL_VERSION}.tar.xz"
  fi

  tarball="$WORK_DIR/linux-${KERNEL_VERSION}.tar.xz"
  if [[ ! -f "$tarball" ]]; then
    echo "Downloading kernel source: $url" >&2
    curl -fL --retry 5 --retry-delay 2 -o "$tarball" "$url"
  fi

  printf '%s\n' "$tarball"
}

build_kernel_deb() {
  local src_tar src_dir pkg_version
  src_tar="$(download_kernel_source)"
  src_dir="$WORK_DIR/linux-${KERNEL_VERSION}"
  pkg_version="${KERNEL_VERSION}${KERNEL_LOCALVERSION}.1"

  rm -rf "$src_dir"
  tar -xf "$src_tar" -C "$WORK_DIR"

  pushd "$src_dir" >/dev/null
  make mrproper
  make x86_64_defconfig

  if [[ ! -x scripts/config ]]; then
    echo "Kernel helper scripts/config not found in source tree." >&2
    exit 1
  fi

  scripts/config --set-str LOCALVERSION "$KERNEL_LOCALVERSION"
  make olddefconfig

  echo "Building kernel package (this can take a while)..."
  make -j"$JOBS" bindeb-pkg KDEB_PKGVERSION="$pkg_version"
  popd >/dev/null

  KERNEL_IMAGE_DEB="$WORK_DIR/$(find "$WORK_DIR" -maxdepth 1 -type f -name "linux-image-*${KERNEL_LOCALVERSION}*_${DEBIAN_ARCH}.deb" ! -name "*dbg*" -printf '%f\n' | sort | tail -n 1)"

  if [[ ! -f "$KERNEL_IMAGE_DEB" ]]; then
    echo "Unable to locate built linux-image package in $WORK_DIR" >&2
    exit 1
  fi

  echo "Using kernel package: $KERNEL_IMAGE_DEB"
}

prepare_rootfs() {
  local -a packages=()

  rm -rf "$ROOTFS_DIR"
  mkdir -p "$ROOTFS_DIR"

  echo "Bootstrapping rootfs: release=$DEBIAN_RELEASE arch=$DEBIAN_ARCH"
  debootstrap --arch="$DEBIAN_ARCH" --variant=minbase "$DEBIAN_RELEASE" "$ROOTFS_DIR" "$DEBIAN_MIRROR"

  mkdir -p "$ROOTFS_DIR"/{dev,dev/pts,proc,sys,run,tmp,boot/efi}
  chmod 1777 "$ROOTFS_DIR/tmp"

  mount_chroot_fs "$ROOTFS_DIR" ROOTFS_CHROOT_MOUNTS

  chroot_run_rootfs "apt-get update"
  mapfile -t packages < <(read_package_list)
  chroot_run_rootfs "apt-get install -y ${packages[*]}"

  printf '%s\n' "$HOSTNAME_VALUE" > "$ROOTFS_DIR/etc/hostname"
  cat > "$ROOTFS_DIR/etc/hosts" <<HOSTS
127.0.0.1 localhost
127.0.1.1 $HOSTNAME_VALUE
::1 localhost ip6-localhost ip6-loopback
HOSTS

  chroot_run_rootfs "id -u '$RUNTIME_USER' >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo '$RUNTIME_USER'"
  chroot_run_rootfs "echo '$RUNTIME_USER:$RUNTIME_USER' | chpasswd"
  chroot_run_rootfs "passwd -l root || true"
  rm -f "$ROOTFS_DIR/etc/.pwd.lock"
}

write_os_release() {
  cat > "$ROOTFS_DIR/etc/os-release" <<EOF
PRETTY_NAME="Beagle OS"
NAME="Beagle OS"
VERSION="${DEBIAN_RELEASE}"
VERSION_ID="${DEBIAN_RELEASE}"
ID=beagle
ID_LIKE=debian
HOME_URL="https://github.com/meinzeug/beagle-os"
SUPPORT_URL="https://github.com/meinzeug/beagle-os/issues"
BUG_REPORT_URL="https://github.com/meinzeug/beagle-os/issues"
EOF
}

install_project_payload() {
  install -d -m 0755 "$ROOTFS_DIR/opt/beagle"
  rsync -a \
    --chown=root:root \
    --delete \
    --exclude '.git/' \
    --exclude '.build/' \
    --exclude 'dist/' \
    --exclude '__pycache__/' \
    --exclude '*.pyc' \
    "$ROOT_DIR/thin-client-assistant/" \
    "$ROOTFS_DIR/opt/beagle/thin-client-assistant/"
  install -m 0644 "$ROOT_DIR/README.md" "$ROOTFS_DIR/opt/beagle/README.md"
}

install_thin_client_runtime() {
  local install_root

  install_root="$ROOTFS_DIR/usr/local/lib/pve-thin-client"
  install -d -m 0755 "$install_root/runtime" "$install_root/installer" "$install_root/templates"

  rsync -a --chown=root:root "$ROOT_DIR/thin-client-assistant/runtime/" "$install_root/runtime/"
  rsync -a --chown=root:root "$ROOT_DIR/thin-client-assistant/installer/" "$install_root/installer/"
  rsync -a --chown=root:root "$ROOT_DIR/thin-client-assistant/templates/" "$install_root/templates/"

  install -m 0755 "$ROOT_DIR/thin-client-assistant/runtime/launch-session.sh" "$install_root/launch-session.sh"
  install -m 0755 "$ROOT_DIR/thin-client-assistant/runtime/prepare-runtime.sh" "$install_root/prepare-runtime.sh"
  install -m 0755 "$ROOT_DIR/thin-client-assistant/runtime/launch-moonlight.sh" "$install_root/launch-moonlight.sh"
  install -m 0755 "$ROOT_DIR/thin-client-assistant/runtime/common.sh" "$install_root/common.sh"
  install -m 0755 "$ROOT_DIR/thin-client-assistant/runtime/apply-network-config.sh" "$install_root/apply-network-config.sh"
  install -m 0755 "$ROOT_DIR/thin-client-assistant/installer/write-config.sh" "$install_root/installer/write-config.sh"
  install -m 0644 "$ROOT_DIR/thin-client-assistant/systemd/pve-thin-client-prepare.service" "$ROOTFS_DIR/etc/systemd/system/pve-thin-client-prepare.service"
}

seed_endpoint_profile() {
  cat > "$ROOTFS_DIR/etc/beagle-os/endpoint.env" <<EOF
BEAGLE_ENDPOINT_PROFILE_NAME="default"
BEAGLE_ENDPOINT_AUTOSTART=""
BEAGLE_ENDPOINT_MOONLIGHT_HOST="${MOONLIGHT_HOST}"
BEAGLE_ENDPOINT_MOONLIGHT_APP="${MOONLIGHT_APP}"
BEAGLE_ENDPOINT_MOONLIGHT_RESOLUTION="${MOONLIGHT_RESOLUTION}"
BEAGLE_ENDPOINT_MOONLIGHT_FPS="${MOONLIGHT_FPS}"
BEAGLE_ENDPOINT_MOONLIGHT_BITRATE="${MOONLIGHT_BITRATE}"
BEAGLE_ENDPOINT_MOONLIGHT_VIDEO_CODEC="H.264"
BEAGLE_ENDPOINT_MOONLIGHT_VIDEO_DECODER="auto"
BEAGLE_ENDPOINT_MOONLIGHT_AUDIO_CONFIG="stereo"
BEAGLE_ENDPOINT_MOONLIGHT_ABSOLUTE_MOUSE="1"
BEAGLE_ENDPOINT_MOONLIGHT_QUIT_AFTER="0"
BEAGLE_ENDPOINT_SUNSHINE_API_URL="${SUNSHINE_API_URL}"
BEAGLE_ENDPOINT_SUNSHINE_USERNAME="${SUNSHINE_USERNAME}"
BEAGLE_ENDPOINT_SUNSHINE_PASSWORD="${SUNSHINE_PASSWORD}"
BEAGLE_ENDPOINT_SUNSHINE_PIN="${SUNSHINE_PIN}"
BEAGLE_ENDPOINT_PROXMOX_HOST="${PROXMOX_HOST}"
BEAGLE_ENDPOINT_PROXMOX_PORT="8006"
BEAGLE_ENDPOINT_PROXMOX_NODE="${PROXMOX_NODE}"
BEAGLE_ENDPOINT_PROXMOX_VMID="${PROXMOX_VMID}"
BEAGLE_ENDPOINT_PROXMOX_REALM="pam"
BEAGLE_ENDPOINT_PROXMOX_VERIFY_TLS="0"
BEAGLE_ENDPOINT_MANAGER_URL="${MANAGER_URL}"
BEAGLE_ENDPOINT_MANAGER_TOKEN="${MANAGER_TOKEN}"
BEAGLE_ENDPOINT_NETWORK_MODE="dhcp"
BEAGLE_ENDPOINT_NETWORK_INTERFACE=""
BEAGLE_ENDPOINT_NETWORK_STATIC_ADDRESS=""
BEAGLE_ENDPOINT_NETWORK_STATIC_PREFIX="24"
BEAGLE_ENDPOINT_NETWORK_GATEWAY=""
BEAGLE_ENDPOINT_NETWORK_DNS_SERVERS="1.1.1.1 8.8.8.8"
EOF
}

apply_profile_overlay() {
  if [[ -d "$OVERLAY_DIR" ]]; then
    rsync -a --chown=root:root "$OVERLAY_DIR/" "$ROOTFS_DIR/"
  fi
}

install_moonlight_into_rootfs() {
  local work_dir target_dir wrapper_path

  work_dir="$(mktemp -d "$WORK_DIR/moonlight.XXXXXX")"
  target_dir="$ROOTFS_DIR/opt/moonlight"
  wrapper_path="$ROOTFS_DIR/usr/local/bin/moonlight"

  cleanup_stage() {
    rm -rf "${work_dir:-}"
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

write_build_metadata() {
  install -d -m 0755 "$ROOTFS_DIR/etc/beagle-os"
  cat > "$ROOTFS_DIR/etc/beagle-os/build-info" <<EOF
BUILD_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DEBIAN_RELEASE=$DEBIAN_RELEASE
DEBIAN_ARCH=$DEBIAN_ARCH
KERNEL_VERSION=$KERNEL_VERSION
KERNEL_LOCALVERSION=$KERNEL_LOCALVERSION
HOSTNAME=$HOSTNAME_VALUE
RUNTIME_USER=$RUNTIME_USER
PROFILE_DIR=$PROFILE_DIR
EOF
}

enable_rootfs_services() {
  chroot_run_rootfs "systemctl set-default multi-user.target"
  chroot_run_rootfs "systemctl enable NetworkManager.service"
  chroot_run_rootfs "systemctl enable qemu-guest-agent.service >/dev/null 2>&1 || true"
  chroot_run_rootfs "systemctl enable systemd-journald.service >/dev/null 2>&1 || true"
  chroot_run_rootfs "systemctl enable ssh.service"
  chroot_run_rootfs "systemctl enable beagle-firstboot.service"
  chroot_run_rootfs "systemctl enable beagle-healthcheck.timer"
  chroot_run_rootfs "systemctl enable beagle-endpoint-report.timer"
  chroot_run_rootfs "systemctl enable pve-thin-client-prepare.service"
  chroot_run_rootfs "systemctl enable beagle-autologin.service"
  chroot_run_rootfs "systemctl disable lightdm.service >/dev/null 2>&1 || true"
}

install_kernel_into_rootfs() {
  local kernel_pkg_name kernel_release

  if [[ ! -f "$KERNEL_IMAGE_DEB" ]]; then
    echo "Kernel package not found: $KERNEL_IMAGE_DEB" >&2
    exit 1
  fi

  kernel_pkg_name="$(basename "$KERNEL_IMAGE_DEB")"
  cp "$KERNEL_IMAGE_DEB" "$ROOTFS_DIR/tmp/$kernel_pkg_name"

  chroot_run_rootfs "dpkg -i /tmp/$kernel_pkg_name || apt-get -f install -y"
  chroot_run_rootfs "apt-get install -f -y"

  kernel_release="$(chroot "$ROOTFS_DIR" bash -lc "ls /lib/modules | sort | tail -n 1")"
  if [[ -z "$kernel_release" ]]; then
    echo "Kernel modules are missing after package install." >&2
    exit 1
  fi

  mkdir -p "$ROOTFS_DIR/boot/grub"
  chroot_run_rootfs "update-initramfs -c -k '$kernel_release'"
  chroot_run_rootfs "update-grub"

  echo "Installed kernel release in rootfs: $kernel_release"
}

build_disk_image() {
  local image_tag raw_img qcow_img root_uuid efi_uuid
  image_tag="${DEBIAN_RELEASE}-${DEBIAN_ARCH}-k${KERNEL_VERSION}${KERNEL_LOCALVERSION}"
  raw_img="$OUT_DIR/beagle-os-${image_tag}.raw"
  qcow_img="$OUT_DIR/beagle-os-${image_tag}.qcow2"

  mkdir -p "$OUT_DIR"
  rm -f "$raw_img" "$qcow_img"

  truncate -s "${IMAGE_SIZE_GB}G" "$raw_img"

  parted -s "$raw_img" mklabel gpt
  parted -s "$raw_img" mkpart ESP fat32 1MiB 513MiB
  parted -s "$raw_img" set 1 esp on
  parted -s "$raw_img" mkpart root ext4 513MiB 100%

  LOOP_DEV="$(losetup --show -Pf "$raw_img")"

  mkfs.vfat -F 32 "${LOOP_DEV}p1"
  mkfs.ext4 -F "${LOOP_DEV}p2"

  root_uuid="$(blkid -s UUID -o value "${LOOP_DEV}p2")"
  efi_uuid="$(blkid -s UUID -o value "${LOOP_DEV}p1")"

  rm -rf "$MOUNT_DIR"
  mkdir -p "$MOUNT_DIR"
  mount "${LOOP_DEV}p2" "$MOUNT_DIR"
  IMAGE_CHROOT_MOUNTS+=("$MOUNT_DIR")

  mkdir -p "$MOUNT_DIR/boot/efi"
  mount "${LOOP_DEV}p1" "$MOUNT_DIR/boot/efi"
  IMAGE_CHROOT_MOUNTS+=("$MOUNT_DIR/boot/efi")

  rsync -aHAX --numeric-ids "$ROOTFS_DIR/" "$MOUNT_DIR/"

  cat > "$MOUNT_DIR/etc/fstab" <<EOF
UUID=$root_uuid / ext4 defaults 0 1
UUID=$efi_uuid /boot/efi vfat umask=0077 0 1
EOF

  mount_chroot_fs "$MOUNT_DIR" IMAGE_CHROOT_MOUNTS
  chroot "$MOUNT_DIR" /usr/bin/env DEBIAN_FRONTEND=noninteractive bash -lc "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=BEAGLE --removable --no-nvram"
  chroot "$MOUNT_DIR" /usr/bin/env DEBIAN_FRONTEND=noninteractive bash -lc "update-grub"

  cleanup_mounts IMAGE_CHROOT_MOUNTS

  losetup -d "$LOOP_DEV"
  LOOP_DEV=""

  qemu-img convert -f raw -O qcow2 "$raw_img" "$qcow_img"

  echo "Beagle OS images built:"
  echo "  RAW : $raw_img"
  echo "  QCOW: $qcow_img"
}

main() {
  parse_args "$@"
  require_root "$@"

  if [[ "$DEBIAN_ARCH" != "amd64" ]]; then
    echo "Currently only amd64 is supported." >&2
    exit 1
  fi

  host_preflight
  install_dependencies

  if [[ "$SKIP_KERNEL_BUILD" == "1" ]]; then
    if [[ -z "$KERNEL_IMAGE_DEB" ]]; then
      echo "--skip-kernel-build requires --kernel-deb <path>" >&2
      exit 1
    fi
    KERNEL_IMAGE_DEB="$(readlink -f "$KERNEL_IMAGE_DEB")"
  else
    build_kernel_deb
  fi

  prepare_rootfs
  write_os_release
  install_project_payload
  install_thin_client_runtime
  apply_profile_overlay
  seed_endpoint_profile
  install_moonlight_into_rootfs
  chroot_run_rootfs "/usr/local/sbin/beagle-render-config"
  write_build_metadata
  install_kernel_into_rootfs
  enable_rootfs_services
  cleanup_mounts ROOTFS_CHROOT_MOUNTS
  build_disk_image
}

main "$@"
