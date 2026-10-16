#!/bin/bash
# Builds in release mode and packages "DELUX M618XSD.app" into DeluxDriver/build/.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product DeluxDriverApp
swift build -c release --product deluxctl
BIN="$(swift build -c release --show-bin-path)"

APP="build/DELUX M618XSD.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/DeluxDriverApp" "$APP/Contents/MacOS/DeluxDriverApp"
cp "$BIN/deluxctl" "build/deluxctl"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DELUX M618XSD</string>
    <key>CFBundleDisplayName</key><string>DELUX M618XSD</string>
    <key>CFBundleIdentifier</key><string>local.gadgrandez.delux-m618xsd</string>
    <key>CFBundleExecutable</key><string>DeluxDriverApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSBluetoothAlwaysUsageDescription</key><string>Configure the DELUX M618XSD mouse when it is connected over Bluetooth.</string>
</dict>
</plist>
PLIST

# Ad hoc signature so macOS runs it without complaining about an invalid signature.
codesign --force --sign - "$APP"
echo "App created at: $(pwd)/$APP"
