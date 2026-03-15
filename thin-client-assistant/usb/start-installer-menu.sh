#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/pve-dcv-integration"

if [[ ! -d "$PROJECT_DIR/thin-client-assistant" ]]; then
  echo "Project payload not found next to this script." >&2
  exit 1
fi

cd "$PROJECT_DIR"
exec ./thin-client-assistant/installer/install.sh "$@"
