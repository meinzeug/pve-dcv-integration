#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
VERSION="$(tr -d ' \n\r' < "$ROOT_DIR/VERSION")"
TAG="v${VERSION}"
REPO="${GITHUB_REPO:-meinzeug/beagle-os}"
TITLE="${RELEASE_TITLE:-$TAG}"
NOTES_FILE="${RELEASE_NOTES_FILE:-}"
BEAGLE_OS_DIST_DIR="${BEAGLE_OS_DIST_DIR:-$DIST_DIR/beagle-os}"
INCLUDE_BEAGLE_OS_ASSETS="${INCLUDE_BEAGLE_OS_ASSETS:-1}"

collect_beagle_os_release_assets() {
  local path
  [[ "$INCLUDE_BEAGLE_OS_ASSETS" == "1" ]] || return 0
  [[ -d "$BEAGLE_OS_DIST_DIR" ]] || return 0

  while IFS= read -r path; do
    RELEASE_ASSETS+=("$path")
  done < <(
    find "$BEAGLE_OS_DIST_DIR" -maxdepth 1 -type f \
      \( -name '*.qcow2' -o -name '*.raw' -o -name '*.deb' -o -name '*.txt' \) \
      | sort
  )
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
}

require_clean_tree() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is not clean." >&2
    exit 1
  fi
}

ensure_tag() {
  if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    git tag -a "$TAG" -m "$TAG"
  fi
}

require_tool git
require_tool gh

require_clean_tree
RUN_PACKAGE=1 "$ROOT_DIR/scripts/validate-project.sh"

RELEASE_ASSETS=(
  "$DIST_DIR/beagle-extension-$TAG.zip"
  "$DIST_DIR/beagle-os-$TAG.tar.gz"
  "$DIST_DIR/beagle-os-latest.tar.gz"
  "$DIST_DIR/pve-thin-client-usb-payload-$TAG.tar.gz"
  "$DIST_DIR/pve-thin-client-usb-payload-latest.tar.gz"
  "$DIST_DIR/pve-thin-client-usb-installer-$TAG.sh"
  "$DIST_DIR/pve-thin-client-usb-installer-latest.sh"
  "$DIST_DIR/SHA256SUMS"
)
collect_beagle_os_release_assets

for asset in "${RELEASE_ASSETS[@]}"; do
  [[ -f "$asset" ]] || {
    echo "Missing release asset: $asset" >&2
    exit 1
  }
done

git push origin main
ensure_tag
git push origin "$TAG"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release already exists: $TAG" >&2
  exit 1
fi

if [[ -n "$NOTES_FILE" ]]; then
  gh release create "$TAG" \
    "${RELEASE_ASSETS[@]}" \
    --repo "$REPO" \
    --title "$TITLE" \
    --notes-file "$NOTES_FILE"
else
  gh release create "$TAG" \
    "${RELEASE_ASSETS[@]}" \
    --repo "$REPO" \
    --title "$TITLE" \
    --notes "$TAG"
fi

echo "Created GitHub release $TAG for $REPO"
