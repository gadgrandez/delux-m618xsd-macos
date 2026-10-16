#!/bin/bash
# Compila en modo release y empaqueta "DELUX M618XSD.app" en DeluxDriver/build/.
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
    <key>NSBluetoothAlwaysUsageDescription</key><string>Configurar el mouse DELUX M618XSD cuando está conectado por Bluetooth.</string>
</dict>
</plist>
PLIST

# Firma ad hoc para que macOS la ejecute sin quejarse de una firma inválida.
codesign --force --sign - "$APP"
echo "App creada en: $(pwd)/$APP"
