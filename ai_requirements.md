# AI Requirements - Keyball39 ZMK Configuration

## Project Overview

This repository contains a ZMK (Zephyr Mechanical Keyboard) configuration for the Keyball39 split Bluetooth keyboard. The Keyball39 features a 39-key split layout with an integrated trackball on the right half for mouse control. The configuration targets nice!nano v2 controllers and includes comprehensive mouse emulation, layer management, and Bluetooth optimization.

**Key Features:**
- Split Bluetooth keyboard (left/right halves)
- PMW3610 trackball sensor integration
- Auto-mouse layer activation
- Multiple function layers (NUM, SYM, FUN, ARROW, MOUSE, SCROLL, SNIPE, GAME)
- Home row modifiers (QWERTY base layer)
- Optimized Bluetooth performance settings

## Architecture Summary

**Languages & Configuration Files:**
- **ZMK Keymap**: `.keymap` files defining layer layouts and key bindings
- **Device Tree Overlays**: `.overlay` files for hardware configuration
- **Kconfig**: `.conf` files for build-time configuration options
- **West Manifest**: `west.yml` for dependency management
- **JSON Layout**: `keyball39.json` for visual keymap representation

**Directory Structure:**
```
config/
├── keyball39.keymap          # Main keymap definitions
├── keyball39.conf            # Build configuration
├── keyball39.json            # Layout metadata
├── slow_scroll.overlay       # Trackball behavior overrides
├── west.yml                  # Dependencies (ZMK + PMW3610 driver)
└── boards/shields/keyball_nano/
    ├── keyball39.dtsi        # Common hardware definitions  
    ├── keyball39_left.overlay # Left half configuration
    ├── keyball39_right.overlay# Right half + trackball config
    └── *.conf                # Hardware-specific settings
```

**Build System:**
- West-based Zephyr build system
- GitHub Actions CI/CD for automated firmware compilation
- Outputs `.uf2` files for flashing to nice!nano controllers

## Coding Style & Preferences

**Layer Organization:**
- Use descriptive `#define` constants for layer numbers (DEFAULT, GAME, NUM, etc.)
- Consistent layer labeling with meaningful names
- Home row modifiers: `&mt LGUI A`, `&mt LALT S`, `&mt LCTRL D`, `&mt LSHFT F`
- Layer-tap behaviors: `&lt MOUSE Z` for dual-function keys

**Trackball & Mouse Configuration:**
- Auto-mouse activation via `&zip_temp_layer MOUSE` input processors
- Layer-specific trackball behavior (mouse movement vs. scroll)
- Custom macros for click-and-exit behaviors
- Timeout-based layer transitions (1000ms for mouse, 5000ms for scroll)

**Behavior Timing:**
- Tapping term: 200ms for both `&lt` and `&mt` behaviors
- Quick tap: 150ms to enable rapid repeated taps
- Tap-preferred flavor for predictable behavior

## Workflow & Tooling

**Build Process:**
```bash
# Standard ZMK build commands
west build -s zmk/app -b nice_nano_v2 -- -DSHIELD=keyball39_left
west build -s zmk/app -b nice_nano_v2 -- -DSHIELD=keyball39_right
```

**Flashing:**
1. Put controller in bootloader mode. Three ways:
   - Double-tap reset on the MCU
   - Hold `Z`+`X`+tap `T` (left half) or `/`+`.`+tap `Y` (right half) — the `&bootloader` keybind lives on the SCROLL layer top row
   - 1200-baud touch on the half's `/dev/cu.usbmodem*` — best-effort, unreliable on this firmware
2. Copy the matching `.uf2` to the mounted `NICENANO` volume. **Use `cat src > dest`, not `cp`** — macOS `cp` errors out on FAT's missing xattr support and may leave the flash incomplete under `set -e`.
3. Volume unmounts on its own once the bootloader has flashed and rebooted.
4. Helper: `./scripts/flash.sh` handles all the above. `./scripts/flash.sh --right-only` for keymap-only changes (peripheral firmware doesn't depend on the keymap).

**Testing:**
- Use ZMK Studio for live configuration (right half has studio-rpc-usb-uart)
- Test trackball functionality across layers
- Verify Bluetooth pairing and split communication
- Check battery reporting and sleep behavior

**CI/CD:**
- GitHub Actions automatically builds firmware on push
- Generates artifacts for both left/right halves
- Includes settings reset firmware for troubleshooting

## Hardware / Infrastructure Notes

**Keyball39 Specifics:**
- Split design: 3x5+3 layout per half (39 keys total)
- Right half contains PMW3610 trackball sensor
- nice!nano v2 controllers (nRF52840-based)
- OLED displays on both halves
- Battery level monitoring and reporting

**Bluetooth Behavior:**
- Optimized connection intervals (6-6, 15ms) for low latency
- 2M PHY preferred for better throughput
- Auto-sleep after 15 minutes idle
- Split communication via BLE with battery level proxying

**Power Management:**
- External power control enabled
- Deep sleep support with wake-on-key
- Optimized buffer sizes to balance performance and power consumption

**Trackball Integration:**
- PMW3610 driver from **tangbonze** repository (vendor pin of the active `AntoineGS/zmk-pmw3610-driver` fork — see `CLAUDE.md` for lineage). NOT `kumamuk-git`, which is stale and lacks ZMK v0.3 support.
- CPI: 700, CPI divider: 1
- Snipe CPI: 400, snipe divider: 4
- Scroll/snipe layer support
- Movement threshold: 0 (maximum sensitivity)
- Device tree `compatible` string is `zmk,pmw3610` (vendor-prefix rename done in the AntoineGS fork in late 2025; the older `pixart,pmw3610` will not bind here).

## AI Prompting Guidance

**Preferred Approach:**
- Provide clean, readable layer definitions with clear intent
- Use minimal devicetree overrides - prefer configuration over hardware changes
- Maintain consistency in timing values across similar behaviors
- Explain the functional purpose of changes, especially for complex trackball processors

**Layer Design Philosophy:**
- Keep base layer (DEFAULT) simple and familiar (QWERTY)
- Use hold-based layer activation (Z for MOUSE, X for SCROLL) rather than toggle
- Maintain predictable escape routes from any layer
- Provide both keyboard and trackball methods for common actions

**Mouse/Trackball Preferences:**
- Auto-activation based on movement, not manual toggling
- Reasonable timeouts that don't interrupt workflow
- Clear separation between mouse movement and scroll behavior
- Support for both precision work and quick navigation

## Gotchas / Don'ts

**Critical Constraints:**
- **Never modify base board DTS files** - only use overlays in the config directory
- **Don't break HID mouse reports** - trackball must maintain standard mouse compatibility
- **Preserve Bluetooth connectivity** - changes to BT config can break pairing
- **Layer consistency** - ensure `#define` layer numbers match across all files

**Common Pitfalls:**
- Input processor order matters - `&zip_temp_layer` must come before other processors
- Layer-specific processors override base processors, not supplement them
- Button behavior mapping follows Left/Middle/Right order, not Left/Right/Middle
- Scroll layer requires `&zip_xy_to_scroll_mapper` to convert movement to scroll events
- Devicetree syntax is strict - invalid node references cause compile failures

**Configuration Dependencies:**
- PMW3610 driver must be included in `west.yml` for trackball support
- Input processor includes (`#include <input/processors.dtsi>`) required for trackball behaviors
- Mouse key bindings need `#include <dt-bindings/zmk/mouse.h>`
- Macro definitions must exist before they're referenced in keymaps or processors

**Testing Considerations:**
- Always test both halves after split-related changes
- Verify trackball works in all relevant layers (MOUSE, SCROLL)
- Check that auto-mouse timeout doesn't interfere with normal typing
- Ensure Bluetooth reconnection works after firmware updates

## Split Roles & Battery (post-2026-05 upgrade to ZMK v0.3)

- **Right half = BLE central (master)**, left half = peripheral. Source of truth: `config/boards/shields/keyball_nano/Kconfig.defconfig`. Plug the right half into USB to talk to the host; plugging only the left does nothing. The full keymap is compiled into the right's firmware only.
- ZMK is pinned to `v0.3` in `config/west.yml`; build workflow pinned to `@v0.3` in `.github/workflows/build.yml`.
- Battery proxying is enabled (`CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y` + `..._PROXY=y`), so both halves' battery levels are exposed as separate BAS GATT instances. **macOS Bluetooth UI only shows one** — this is an `IOBluetooth` limitation, not a config bug. Use `scripts/BatteryReader.app` (raw CoreBluetooth) or the right-half OLED to see both.

## Tooling in `scripts/`

See `scripts/README.md` for full docs. Quick summary:
- `flash.sh` — flash one or both halves; supports `--right-only` / `--left-only` / `--firmware-dir`
- `read_batteries.swift` + `build_battery_reader.sh` — Swift+CoreBluetooth tool that reads both halves' battery levels by enumerating all GATT BAS instances directly. Output lands in `/tmp/battery_reader.log`. First run prompts for macOS Bluetooth permission.

## Soft-off and sys_reset

- **Do not use `&soft_off`** in this repo. The behavior compiles to a no-op in this ZMK fork even with `CONFIG_ZMK_SLEEP=y`, and adding `CONFIG_ZMK_BEHAVIOR_SOFT_OFF=y` breaks the build.
- **Use `&sys_reset`** as the "power cycle" binding instead. Already on the SCROLL layer: position 3 (R, left half) and position 6 (U, right half). Combo paths: `Z`+`X`+`R` / `/`+`.`+`U`.
