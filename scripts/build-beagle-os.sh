#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${BEAGLE_OS_WORK_DIR:-$ROOT_DIR/.build/beagle-os}"
OUT_DIR="${BEAGLE_OS_OUT_DIR:-$ROOT_DIR/dist/beagle-os}"
ROOTFS_DIR="$WORK_DIR/rootfs"
MOUNT_DIR="$WORK_DIR/mnt"

DEBIAN_RELEASE="${BEAGLE_OS_RELEASE:-bookworm}"
DEBIAN_ARCH="${BEAGLE_OS_ARCH:-amd64}"
DEBIAN_MIRROR="${BEAGLE_OS_MIRROR:-http://deb.debian.org/debian}"
HOSTNAME_VALUE="${BEAGLE_OS_HOSTNAME:-beagle-os}"
RUNTIME_USER="${BEAGLE_OS_USER:-thinclient}"
IMAGE_SIZE_GB="${BEAGLE_OS_IMAGE_SIZE_GB:-8}"
JOBS="${BEAGLE_OS_JOBS:-$(nproc)}"

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
  exec sudo --preserve-env=BEAGLE_OS_RELEASE,BEAGLE_OS_ARCH,BEAGLE_OS_MIRROR,BEAGLE_OS_KERNEL_VERSION,BEAGLE_OS_KERNEL_LOCALVERSION,BEAGLE_OS_KERNEL_DEB_PATH,BEAGLE_OS_SKIP_KERNEL_BUILD,BEAGLE_OS_HOSTNAME,BEAGLE_OS_USER,BEAGLE_OS_IMAGE_SIZE_GB,BEAGLE_OS_WORK_DIR,BEAGLE_OS_OUT_DIR,BEAGLE_OS_JOBS "$0" "$@"
}

install_dependencies() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    debootstrap \
    curl \
    xz-utils \
    tar \
    build-essential \
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
    ca-certificates
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

download_kernel_source() {
  local major url tarball
  major="${KERNEL_VERSION%%.*}"
  url="$KERNEL_SRC_URL"

  if [[ -z "$url" ]]; then
    url="https://cdn.kernel.org/pub/linux/kernel/v${major}.x/linux-${KERNEL_VERSION}.tar.xz"
  fi

  tarball="$WORK_DIR/linux-${KERNEL_VERSION}.tar.xz"
  if [[ ! -f "$tarball" ]]; then
    echo "Downloading kernel source: $url"
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
  yes "" | make olddefconfig

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
  rm -rf "$ROOTFS_DIR"
  mkdir -p "$ROOTFS_DIR"

  echo "Bootstrapping rootfs: release=$DEBIAN_RELEASE arch=$DEBIAN_ARCH"
  debootstrap --arch="$DEBIAN_ARCH" --variant=minbase "$DEBIAN_RELEASE" "$ROOTFS_DIR" "$DEBIAN_MIRROR"

  mkdir -p "$ROOTFS_DIR"/{dev,dev/pts,proc,sys,run,tmp,boot/efi}
  chmod 1777 "$ROOTFS_DIR/tmp"

  mount_chroot_fs "$ROOTFS_DIR" ROOTFS_CHROOT_MOUNTS

  chroot_run_rootfs "apt-get update"
  chroot_run_rootfs "apt-get install -y systemd-sysv dbus sudo openssh-server ca-certificates iproute2 iputils-ping curl vim-tiny grub-efi-amd64-bin initramfs-tools linux-base"

  printf '%s\n' "$HOSTNAME_VALUE" > "$ROOTFS_DIR/etc/hostname"
  cat > "$ROOTFS_DIR/etc/hosts" <<HOSTS
127.0.0.1 localhost
127.0.1.1 $HOSTNAME_VALUE
::1 localhost ip6-localhost ip6-loopback
HOSTS

  chroot_run_rootfs "id -u '$RUNTIME_USER' >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo '$RUNTIME_USER'"
  chroot_run_rootfs "echo '$RUNTIME_USER:$RUNTIME_USER' | chpasswd"
  chroot_run_rootfs "passwd -l root || true"
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

  chroot_run_rootfs "update-initramfs -c -k '$kernel_release'"
  chroot_run_rootfs "update-grub"

  echo "Installed kernel release in rootfs: $kernel_release"
}

build_disk_image() {
  local image_tag raw_img qcow_img
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

  rm -rf "$MOUNT_DIR"
  mkdir -p "$MOUNT_DIR"
  mount "${LOOP_DEV}p2" "$MOUNT_DIR"
  IMAGE_CHROOT_MOUNTS+=("$MOUNT_DIR")

  mkdir -p "$MOUNT_DIR/boot/efi"
  mount "${LOOP_DEV}p1" "$MOUNT_DIR/boot/efi"
  IMAGE_CHROOT_MOUNTS+=("$MOUNT_DIR/boot/efi")

  rsync -aHAX --numeric-ids "$ROOTFS_DIR/" "$MOUNT_DIR/"

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

  mkdir -p "$WORK_DIR" "$OUT_DIR"
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
  install_kernel_into_rootfs
  build_disk_image

  cleanup_mounts ROOTFS_CHROOT_MOUNTS
}

main "$@"
