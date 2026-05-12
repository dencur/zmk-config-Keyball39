#!/usr/bin/env bash
# Local equivalent of the GitHub Actions firmware build.
# Mirrors build.yaml exactly: keyball39_left, keyball39_right (with
# studio-rpc-usb-uart snippet), settings_reset. Outputs the three UF2s
# into ~/Downloads/keyball39-firmware/ where flash.sh expects them.
#
# Requires a one-time local toolchain setup — see scripts/README.md
# "Local builds" section.
#
# Usage:
#   ./build_local.sh                 # build all three targets
#   ./build_local.sh --left          # just the left half
#   ./build_local.sh --right         # just the right half (the one
#                                    # affected by keymap-only changes)
#   ./build_local.sh --settings-reset
#
# Env vars:
#   ZMK_WORKSPACE     workspace root (default: ~/zmk-workspace)
#   ZMK_CONFIG_DIR    config repo to build (default: workspace's clone).
#                     Set to your primary clone to build local edits
#                     without pushing first.
#   ZMK_OUT_DIR       firmware output dir (default: ~/Downloads/keyball39-firmware)

set -euo pipefail

WORKSPACE="${ZMK_WORKSPACE:-$HOME/zmk-workspace}"
CONFIG_DIR="${ZMK_CONFIG_DIR:-$WORKSPACE/zmk-config}"
OUT_DIR="${ZMK_OUT_DIR:-$HOME/Downloads/keyball39-firmware}"

BUILD_LEFT=true
BUILD_RIGHT=true
BUILD_RESET=true
case "${1:-}" in
  --left)            BUILD_RIGHT=false; BUILD_RESET=false ;;
  --right)           BUILD_LEFT=false;  BUILD_RESET=false ;;
  --settings-reset)  BUILD_LEFT=false;  BUILD_RIGHT=false ;;
  --all|"")          ;;
  -h|--help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
    exit 0 ;;
  *) echo "unknown arg: $1" >&2; exit 1 ;;
esac

[[ -d "$WORKSPACE/.venv" ]] || {
  echo "missing $WORKSPACE/.venv — run the local toolchain setup first" >&2
  echo "see scripts/README.md → Local builds" >&2
  exit 1
}
[[ -d "$CONFIG_DIR/config" ]] || {
  echo "no config/ inside $CONFIG_DIR" >&2
  exit 1
}

# shellcheck source=/dev/null
source "$WORKSPACE/.venv/bin/activate"
mkdir -p "$OUT_DIR"

WORKSPACE_CONFIG="$WORKSPACE/zmk-config"  # where west.yml was initialized

build_one() {
  local shield="$1" snippet="${2:-}"
  local build_dir="$WORKSPACE_CONFIG/build/$shield"
  local cmd=(west build -p -d "$build_dir" -s zmk/app -b nice_nano_v2)
  [[ -n "$snippet" ]] && cmd+=(-S "$snippet")
  cmd+=(-- "-DSHIELD=$shield" "-DZMK_CONFIG=$CONFIG_DIR/config")

  echo
  echo "=== build: $shield${snippet:+ ($snippet)} ==="
  (cd "$WORKSPACE_CONFIG" && "${cmd[@]}")

  local out="$OUT_DIR/${shield}-nice_nano_v2-zmk.uf2"
  cp "$build_dir/zephyr/zmk.uf2" "$out"
  echo "  → $out  ($(stat -f %z "$out") bytes, sha256:$(shasum -a 256 "$out" | cut -c1-12)...)"
}

START=$SECONDS
$BUILD_LEFT  && build_one keyball39_left
$BUILD_RIGHT && build_one keyball39_right studio-rpc-usb-uart
$BUILD_RESET && build_one settings_reset

echo
echo "Done in $((SECONDS - START))s. Artifacts in $OUT_DIR/"
ls -la "$OUT_DIR"/*.uf2 2>/dev/null
