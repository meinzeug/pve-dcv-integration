#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_PACKAGE="${RUN_PACKAGE:-0}"
VERSION="$(tr -d ' \n\r' < "$ROOT_DIR/VERSION")"

check_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
}

check_tool bash
check_tool node
check_tool rg
check_tool python3

mapfile -t shell_files < <(find "$ROOT_DIR/scripts" "$ROOT_DIR/thin-client-assistant" -type f -name '*.sh' | sort)
for file in "${shell_files[@]}"; do
  bash -n "$file"
done

mapfile -t python_files < <(find "$ROOT_DIR/thin-client-assistant" -type f -name '*.py' | sort)
if (( ${#python_files[@]} > 0 )); then
  python3 -m py_compile "${python_files[@]}"
fi

node --check "$ROOT_DIR/proxmox-ui/beagle-ui.js"
node --check "$ROOT_DIR/proxmox-ui/beagle-autologin.js"
node --check "$ROOT_DIR/extension/content.js"
node --check "$ROOT_DIR/extension/options.js"

python3 - "$ROOT_DIR/extension/manifest.json" "$VERSION" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
version = sys.argv[2]
manifest = json.loads(path.read_text())
if manifest.get("version") != version:
    raise SystemExit(f"extension manifest version mismatch: {manifest.get('version')} != {version}")
PY

rg -q "^## v${VERSION} -" "$ROOT_DIR/CHANGELOG.md"

if [[ "$RUN_PACKAGE" == "1" ]]; then
  "$ROOT_DIR/scripts/package.sh"
fi

if [[ -f "$ROOT_DIR/dist/beagle-extension-v${VERSION}.zip" ]]; then
  echo "OK  artifact dist/beagle-extension-v${VERSION}.zip"
fi

echo "Project validation completed successfully."
