#!/usr/bin/env bash
set -euo pipefail

PROXMOX_HOST="${PROXMOX_HOST:-thinovernet}"
VMID="${VMID:-}"
ENABLE_AUDIO="${ENABLE_AUDIO:-1}"
SET_ONBOOT="${SET_ONBOOT:-1}"

usage() {
  cat <<'EOF'
Usage: optimize-proxmox-vm-for-beagle.sh --vmid <id> [--proxmox-host <ssh-host>] [--no-audio] [--no-onboot]

Applies a reproducible Beagle OS / Moonlight-friendly baseline to a Proxmox VM:
  - machine: q35
  - cpu: host
  - qemu guest agent: enabled
  - scsi controller: virtio-scsi-single
  - vga: virtio
  - memory ballooning: disabled
  - rng device: enabled
  - optional virtual audio device
EOF
}

require_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing required tool: $tool" >&2
    exit 1
  }
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vmid) VMID="$2"; shift 2 ;;
      --proxmox-host) PROXMOX_HOST="$2"; shift 2 ;;
      --no-audio) ENABLE_AUDIO="0"; shift ;;
      --no-onboot) SET_ONBOOT="0"; shift ;;
      -h|--help) usage; exit 0 ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

ssh_host() {
  ssh "$PROXMOX_HOST" "$@"
}

qm_set() {
  local args=("$@")
  ssh_host "sudo /usr/sbin/qm set '$VMID' ${args[*]}"
}

main() {
  parse_args "$@"
  require_tool ssh

  [[ -n "$VMID" ]] || {
    echo "--vmid is required" >&2
    exit 1
  }

  # Core VM baseline for low-latency remote desktop workloads.
  qm_set --machine q35
  qm_set --cpu host
  qm_set --agent enabled=1
  qm_set --scsihw virtio-scsi-single
  qm_set --vga virtio
  qm_set --balloon 0
  qm_set --rng0 source=/dev/urandom

  if [[ "$SET_ONBOOT" == "1" ]]; then
    qm_set --onboot 1
  fi

  if [[ "$ENABLE_AUDIO" == "1" ]]; then
    # Provide a deterministic virtual audio device for guest audio capture paths.
    qm_set --audio0 device=ich9-intel-hda,driver=spice
  fi

  echo "Applied Beagle OS VM baseline to VM $VMID on host $PROXMOX_HOST"
}

main "$@"
