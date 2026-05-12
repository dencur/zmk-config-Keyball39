# CLAUDE.md — agent quickstart

This is a personal ZMK config repo for a **Keyball39** split BLE keyboard with a PMW3610 trackball. Bought from FindKB Tokyo (vendor: `tangbonze` on GitHub); the controllers are nice_nano_v2 (nRF52840).

The companion doc [`ai_requirements.md`](ai_requirements.md) has more detail on style and architecture — read it for non-trivial keymap or behavior work. This file is the quick-reference for the things agents reliably get wrong on first try.

## Things to get right

### 1. The **RIGHT** half is the BLE central, NOT the left

Authoritative source: [config/boards/shields/keyball_nano/Kconfig.defconfig](config/boards/shields/keyball_nano/Kconfig.defconfig) sets `ZMK_SPLIT_BLE_ROLE_CENTRAL=y` only under `if SHIELD_KEYBALL39_RIGHT`. Consequences:

- USB host pairs with the right half. Plugging only the left in does nothing useful.
- The full keymap is compiled into the right half's firmware. The left half is a dumb matrix scanner that reports key positions to the right via BLE split.
- For flashing: prefer flashing the **left first, right second** (the peripheral coming up first means cleaner re-bond). But left only needs flashing when its firmware actually changed — see #2.

### 2. Keymap-only changes don't need a left-half re-flash

If only `config/keyball39.keymap` (or anything else that only affects the central build) changed, the left UF2 will be byte-for-byte identical across builds. Verify with `shasum`; if the hash matches the previous build, skip flashing the left. Use `scripts/flash.sh --right-only`.

Files that DO affect the peripheral build:
- `config/keyball39.conf` (global Kconfig — both halves)
- `config/west.yml` (driver/ZMK version pins — both halves)
- `config/boards/shields/keyball_nano/keyball39_left.conf`/`.overlay`

### 3. The PMW3610 driver remote is `tangbonze`, not `kumamuk-git`

[config/west.yml](config/west.yml) pulls the trackball driver from `tangbonze/zmk-pmw3610-driver` (vendor's pin of the active `AntoineGS` upstream). The historical `kumamuk-git` fork is stale and doesn't have ZMK v0.3 support. Don't "fix" west.yml by reverting to kumamuk.

The active driver lineage: `ufan → inorichi → kumamuk-git (stale) → AntoineGS (active) → tangbonze (vendor pin)`. Recent gains in tangbonze's fork: 5.5x reduced deep-sleep battery, mouse acceleration (sigmoid/quadratic), ZMK v0.3/Zephyr 3.5 compatibility, and the `compatible` string rename `pixart,pmw3610` → `zmk,pmw3610` (already applied in [keyball39_right.overlay:56](config/boards/shields/keyball_nano/keyball39_right.overlay:56)).

### 4. `&soft_off` is FRAGILE here; use `&sys_reset`

`&soft_off` in this ZMK fork does not produce a functioning binary even when `CONFIG_ZMK_SLEEP=y` is set, and explicitly enabling `CONFIG_ZMK_BEHAVIOR_SOFT_OFF=y` breaks the build. `&sys_reset` is a core ZMK behavior, always available, and serves the same "power-cycle to fix BT" use case. The SCROLL layer top-row R (left) and U (right) are bound to `&sys_reset` for this reason.

### 5. macOS shows only ONE battery for the keyboard — by design

[`config/keyball39.conf`](config/keyball39.conf) has both `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y` and `..._PROXY=y` — the central polls the peripheral and broadcasts BOTH battery levels as separate BAS GATT instances. Linux and Windows display both. macOS `IOBluetooth` silently filters to one. This is a macOS limitation, not a config bug. Don't try to fix it on the firmware side. To see both batteries on Mac, use [scripts/BatteryReader.app](scripts/README.md#read_batteriesswift--build_battery_readersh--both-halves-battery-levels) (raw CoreBluetooth) or the OLED on the right half.

## Build + flash workflow

1. Push to a branch on `origin` (`dencur/zmk-config-Keyball39`). GitHub Actions builds firmware for both halves + a `settings_reset` UF2. The `Build ZMK Firmware` workflow on the branch produces a `firmware` artifact zip.
2. Download via [nightly.link](https://nightly.link) (no auth needed) — pattern: `https://nightly.link/dencur/zmk-config-Keyball39/actions/runs/<RUN_ID>/firmware.zip`. Unzip to `~/Downloads/keyball39-firmware/`.
3. Hash-compare against the previous build to decide which halves need flashing.
4. Run `./scripts/flash.sh` (or `--right-only`).

See [`scripts/README.md`](scripts/README.md) for full script docs, including:
- Why `cat` instead of `cp` (FAT xattr bug)
- Why the 1200-baud touch is unreliable on this firmware
- The `&bootloader` keybinds for manual reset (left: `Z`+`X`+`T`; right: `/`+`.`+`Y`)

## Layer system

Layer indices and chord paths defined in [config/keyball39.keymap:1](config/keyball39.keymap:1):

| # | Name    | How to reach           |
|---|---------|------------------------|
| 0 | DEFAULT | (base)                 |
| 1 | GAME    | tap `to GAME` (thumb on default), tap `to DEFAULT` to exit |
| 2 | NUM     | hold space             |
| 3 | SYM     | hold enter             |
| 4 | FUN     | hold tab               |
| 5 | ARROW   | hold backspace         |
| 6 | MOUSE   | hold `Z` OR hold `/`   |
| 7 | SCROLL  | from MOUSE, hold `X` OR hold `.` |
| 8 | SNIPE   | (currently no hold key) |

The hold-tap chain means SCROLL is two layers deep — used as a "power tools" layer for `&bootloader` (T, Y) and `&sys_reset` (R, U). Combos block is empty as of 2026-05.

## Hardware reference

- **Right half (central)**: nice_nano_v2 + PMW3610 trackball, OLED, USB-C for host connection. Chip USB serial: `59C2FC44095CA4E0`.
- **Left half (peripheral)**: nice_nano_v2, OLED, USB-C for charging only (it also exposes USB-CDC post-v0.3 but doesn't enumerate to the host as a keyboard). Chip USB serial: `3B2C7181143C3FB8`.
- **Switches**: Kailh Deep Sea Silent Mini Low-Profile (Choc v2). User has tactile-Brown variant (45g).
- **Battery**: J&J 303450 3.7V 550mAh LiPo per half.

## Common operations

- **Adding a key binding**: edit [config/keyball39.keymap](config/keyball39.keymap). Layer-tap (`&lt LAYER KEY`) and mod-tap (`&mt MOD KEY`) timing is set by the `&lt` and `&mt` nodes at the top — `tapping-term-ms = 200`, `flavor = "tap-preferred"`.
- **Tuning the trackball CPI**: [config/boards/shields/keyball_nano/keyball39_right.conf](config/boards/shields/keyball_nano/keyball39_right.conf). Current: `CPI=700`, `CPI_DIVIDOR=1`. Snipe CPI is separate.
- **Tuning BT performance**: [config/keyball39.conf](config/keyball39.conf) lines 1-20. The current values are user-tuned (`MIN/MAX_INT=6`, `LATENCY=0`, etc.) — be careful overwriting them.
- **Tracking upstream**: vendor's main branch is `tangbonze/zmk-config-Keyball39:main`. Add as a remote with `git remote add upstream …` and `git merge upstream/main` periodically.

## Don'ts

- Don't `cp` UF2 files to a FAT bootloader volume — `cp` errors on extended attributes. Use `cat src > dest`.
- Don't bind `&soft_off` (see #4).
- Don't revert the pmw3610 driver to `kumamuk-git` (see #3).
- Don't assume the left half is the central (see #1).
- Don't modify base board DTS files — only `config/boards/shields/keyball_nano/*.overlay`.
- Don't `&bootloader` or `&sys_reset` in non-SCROLL layers — keep the "danger zone" gated behind a two-layer hold chain so it's not accidentally triggered.
