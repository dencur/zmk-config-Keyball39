#!/usr/bin/env bash
# Flash Keyball39 firmware onto one or both halves.
#
# Usage:
#   ./flash.sh                       # flash both halves (interactive)
#   ./flash.sh --right-only          # only flash the right half (keymap-only changes)
#   ./flash.sh --left-only           # only flash the left half (peripheral firmware changes)
#   ./flash.sh --firmware-dir DIR    # firmware location (default: ~/Downloads/keyball39-firmware)
#
# How it works:
#   1. Tries a 1200-baud touch on each connected /dev/cu.usbmodem* to enter
#      the UF2 bootloader. This is UNRELIABLE on this firmware (Zephyr USB-CDC
#      doesn't always propagate the termios baud change), so it's best-effort.
#   2. If the touch doesn't work in 60s, you trigger the bootloader manually:
#        LEFT:  hold Z + hold X + tap T (or double-click reset on left MCU)
#        RIGHT: hold / + hold . + tap Y (or double-click reset on right MCU)
#   3. Once the NICENANO bootloader volume mounts, the script copies the
#      matching .uf2 onto it (via `cat`, NOT `cp`, to avoid the macOS FAT
#      xattr error).
#   4. The bootloader writes the UF2 and unmounts on its own — that's the
#      "flash complete" signal.
#
# Optimization tip: keymap-only changes only affect the right (central) half's
# firmware. Hash-compare the new left.uf2 against the previous; if identical,
# pass --right-only.

set -euo pipefail

# Chip USB serial numbers for THIS keyboard. Re-discover with:
#   ioreg -p IOUSB -l -w 0 | grep -B5 'Keyball39'
# The serial with the full USB descriptor block is the central (right).
LEFT_USB_SN="${LEFT_USB_SN:-3B2C7181143C3FB8}"
RIGHT_USB_SN="${RIGHT_USB_SN:-59C2FC44095CA4E0}"

FIRMWARE_DIR="${HOME}/Downloads/keyball39-firmware"
FLASH_LEFT=true
FLASH_RIGHT=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --right-only)    FLASH_LEFT=false; shift ;;
    --left-only)     FLASH_RIGHT=false; shift ;;
    --firmware-dir)  FIRMWARE_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

LEFT_UF2="$FIRMWARE_DIR/keyball39_left-nice_nano_v2-zmk.uf2"
RIGHT_UF2="$FIRMWARE_DIR/keyball39_right-nice_nano_v2-zmk.uf2"

[[ -d "$FIRMWARE_DIR" ]] || { echo "firmware dir not found: $FIRMWARE_DIR" >&2; exit 1; }
$FLASH_LEFT  && { [[ -f "$LEFT_UF2"  ]] || { echo "missing: $LEFT_UF2"  >&2; exit 1; }; }
$FLASH_RIGHT && { [[ -f "$RIGHT_UF2" ]] || { echo "missing: $RIGHT_UF2" >&2; exit 1; }; }

BOOTLOADER_VOLUMES=(NICENANO FTHR840BOOT BOOT)

find_bootloader_volume() {
  for name in "${BOOTLOADER_VOLUMES[@]}"; do
    [[ -d "/Volumes/$name" ]] && { echo "/Volumes/$name"; return 0; }
  done
  return 1
}

serial_dev_for() {
  python3 - "$1" <<'PYEOF'
import sys, subprocess, re
target = sys.argv[1]
out = subprocess.check_output(['ioreg', '-p', 'IOUSB', '-l', '-w', '0', '-r', '-c', 'IOUSBHostDevice'], text=True)
current_sn = None
for line in out.splitlines():
    m = re.search(r'"USB Serial Number"\s*=\s*"([^"]+)"', line)
    if m:
        current_sn = m.group(1)
    m = re.search(r'"IOCalloutDevice"\s*=\s*"([^"]+)"', line)
    if m and current_sn == target:
        print(m.group(1))
        break
PYEOF
}

touch_1200() {
  python3 - "$1" <<'PYEOF'
import os, sys, termios, time
fd = os.open(sys.argv[1], os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
a = termios.tcgetattr(fd); a[4] = termios.B1200; a[5] = termios.B1200
termios.tcsetattr(fd, termios.TCSANOW, a)
time.sleep(0.1); os.close(fd)
PYEOF
}

wait_for_volume() {
  local timeout="${1:-120}" waited=0
  while ! find_bootloader_volume >/dev/null; do
    sleep 1; waited=$((waited+1))
    (( waited >= timeout )) && return 1
  done
}

wait_for_unmount() {
  local vol="$1" timeout="${2:-30}" waited=0
  while [[ -d "$vol" ]]; do
    sleep 1; waited=$((waited+1))
    (( waited >= timeout )) && return 1
  done
}

flash_half() {
  local label="$1" uf2="$2" usb_sn="$3"
  echo
  echo "=== $label ==="

  local dev=""
  dev=$(serial_dev_for "$usb_sn") || true
  if [[ -n "$dev" && -e "$dev" ]]; then
    echo "  $label is at $dev — trying 1200-baud touch (best-effort)"
    touch_1200 "$dev" 2>/dev/null || true
  else
    echo "  $label not connected via USB (or serial port unknown)"
  fi

  echo "  waiting for bootloader volume (up to 120s)"
  echo "  if it doesn't auto-mount, trigger manually:"
  if [[ "$label" == "LEFT" ]]; then
    echo "    -> hold Z + X + tap T,  OR  double-click reset on left MCU"
  else
    echo "    -> hold / + . + tap Y,  OR  double-click reset on right MCU"
  fi

  wait_for_volume 120 || { echo "  TIMEOUT" >&2; return 1; }
  local vol; vol=$(find_bootloader_volume)
  echo "  mounted: $vol"
  sleep 1

  echo "  writing $(basename "$uf2") -> $vol/firmware.uf2"
  cat "$uf2" > "$vol/firmware.uf2"
  sync

  echo "  waiting for $vol to unmount (signals flash complete)"
  wait_for_unmount "$vol" 30 || { echo "  WARN: still mounted after 30s" >&2; return 1; }
  echo "  $label flashed"
}

$FLASH_LEFT && flash_half "LEFT" "$LEFT_UF2" "$LEFT_USB_SN"
$FLASH_LEFT && $FLASH_RIGHT && sleep 2
$FLASH_RIGHT && flash_half "RIGHT" "$RIGHT_UF2" "$RIGHT_USB_SN"

echo
echo "Done. Halves will reboot and re-bond."
