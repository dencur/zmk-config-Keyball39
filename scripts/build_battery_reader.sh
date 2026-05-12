#!/usr/bin/env bash
# Compiles read_batteries.swift into a minimal .app bundle with the required
# NSBluetoothAlwaysUsageDescription so macOS TCC will surface a permission
# prompt rather than killing the process.
#
# Usage:
#   ./build_battery_reader.sh        # builds and runs
#   ./build_battery_reader.sh build  # just builds
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/BatteryReader.app"
BIN_DIR="$APP/Contents/MacOS"
BIN="$BIN_DIR/BatteryReader"
PLIST="$APP/Contents/Info.plist"
SRC="$DIR/read_batteries.swift"

[[ -f "$SRC" ]] || { echo "missing $SRC" >&2; exit 1; }

echo "Building $APP..."
rm -rf "$APP"
mkdir -p "$BIN_DIR"

cat > "$PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>BatteryReader</string>
    <key>CFBundleIdentifier</key>
    <string>local.dencur.keyball39.batteryreader</string>
    <key>CFBundleName</key>
    <string>BatteryReader</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Read battery levels from your Keyball39 keyboard halves.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>Read battery levels from your Keyball39 keyboard halves.</string>
</dict>
</plist>
EOF

swiftc -framework CoreBluetooth -framework Foundation -o "$BIN" "$SRC"

# Ad-hoc sign so TCC will track this bundle's permission grant.
codesign --force --deep --sign - "$APP"

echo "Built. Bundle at: $APP"
echo "Binary:           $BIN"

if [[ "${1:-run}" == "run" ]]; then
  echo
  echo "Running. macOS will prompt for Bluetooth permission the FIRST time."
  echo "After clicking Allow, it may not finish this run — re-run if so."
  echo
  exec "$BIN"
fi
