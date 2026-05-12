# scripts/

Helper scripts for working with this Keyball39 build on macOS.

## `flash.sh` — flash one or both halves

Writes the latest `.uf2` artifacts onto each half via the nice_nano_v2 UF2 bootloader.

```bash
./flash.sh                          # both halves
./flash.sh --right-only             # only the central (use for keymap-only changes)
./flash.sh --left-only              # only the peripheral
./flash.sh --firmware-dir <path>    # custom firmware location
```

**Default firmware directory:** `~/Downloads/keyball39-firmware/`. Drop the GitHub Actions artifact zip there and unzip it; the script picks up `keyball39_left-nice_nano_v2-zmk.uf2` and `keyball39_right-nice_nano_v2-zmk.uf2` automatically.

**How it triggers the bootloader** (in order of fallback):
1. **1200-baud touch** on the half's `/dev/cu.usbmodem*` port — best-effort, frequently doesn't work on this firmware because of a Zephyr USB-CDC quirk.
2. **Manual trigger** — the script will pause and tell you what to do:
   - `LEFT` (peripheral): hold `Z` + `X` + tap `T`, OR double-click the reset button on the left MCU
   - `RIGHT` (central): hold `/` + `.` + tap `Y`, OR double-click the reset button on the right MCU

Once the `NICENANO` bootloader volume mounts, the script writes the UF2 with `cat` (NOT `cp` — macOS `cp` errors on FAT extended-attributes), then waits for the volume to eject (the bootloader's "I'm done" signal).

**Chip USB serials** for *this specific* keyboard are baked into the script — override via `LEFT_USB_SN` / `RIGHT_USB_SN` env vars if you flash a different board. Find them with:

```bash
ioreg -p IOUSB -l -w 0 | grep -B5 'Keyball39'
```

**Optimization**: if you only changed the keymap, run with `--right-only`. The peripheral firmware is keymap-agnostic. Verify by hash-comparing the new `keyball39_left*.uf2` against the previous; if identical, skip flashing it.

## `read_batteries.swift` + `build_battery_reader.sh` — both-halves battery levels

macOS's Bluetooth stack only surfaces ONE Battery Service per device, even though ZMK with `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y` broadcasts two BAS instances. This Swift script reads them directly via CoreBluetooth and bypasses the filter.

```bash
./build_battery_reader.sh           # builds + runs (first time only)
./build_battery_reader.sh build     # just builds
open ./BatteryReader.app && sleep 6 && cat /tmp/battery_reader.log   # re-run anytime
```

**Why a `.app` bundle and not `swift script.swift`**: macOS TCC kills any process touching Bluetooth that doesn't declare `NSBluetoothAlwaysUsageDescription` in its `Info.plist`. `swift` from the CLI has no plist, so it `SIGABRT`s with `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__`. The build script wraps the compiled binary in a minimal `.app` with the required usage description and ad-hoc-signs it (`codesign --sign -`) so TCC will surface a permission prompt instead of crashing.

**First run** will show a macOS Bluetooth permission dialog — click **Allow**. The grant is sticky.

**Why launch via `open` and not directly**: a direct binary exec inherits the shell's TCC identity and still crashes. `open` goes through Launch Services and the app gets tracked as its own TCC subject. Because `open` detaches stdio, the script redirects stdout/stderr to `/tmp/battery_reader.log` so you can read the output after the fact.

Output looks like:

```
=== BATTERY LEVELS ===
CENTRAL (right):   100%
PERIPHERAL (left): 100%
```

The OLED on the right half also displays both — this script is just for when you want them on the Mac.

## Common workflow after pushing a change

```bash
# 1. Wait for GitHub Actions build, download artifact
curl -sL -o ~/Downloads/keyball39-firmware/firmware.zip \
  "https://nightly.link/dencur/zmk-config-Keyball39/actions/runs/<RUN_ID>/firmware.zip"
unzip -o ~/Downloads/keyball39-firmware/firmware.zip -d ~/Downloads/keyball39-firmware/

# 2. Check if peripheral firmware changed (keymap-only changes leave it untouched)
shasum -a 256 ~/Downloads/keyball39-firmware/*.uf2

# 3. Flash whichever halves need it
./scripts/flash.sh --right-only   # if only the central changed
```
