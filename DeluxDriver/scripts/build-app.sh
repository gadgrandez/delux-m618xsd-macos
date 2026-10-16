#!/bin/bash
# Builds in release mode and packages "DELUX M618XSD.app" into DeluxDriver/build/.
# The binaries are universal (Apple Silicon + Intel).
# With --zip, also creates the release archives in build/release/.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="1.0.0"
ARCHS=(arm64 x86_64)
TMP="build/arch"
rm -rf "$TMP"

# SwiftPM writes every triple to the same output folder, so build one at a time.
for arch in "${ARCHS[@]}"; do
    triple="$arch-apple-macosx13.0"
    swift build -c release --triple "$triple" --product DeluxDriverApp
    swift build -c release --triple "$triple" --product deluxctl
    BIN="$(swift build -c release --triple "$triple" --show-bin-path)"
    mkdir -p "$TMP/$arch"
    cp "$BIN/DeluxDriverApp" "$BIN/deluxctl" "$TMP/$arch/"
done

APP="build/DELUX M618XSD.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/DeluxDriverApp" $(for a in "${ARCHS[@]}"; do echo "$TMP/$a/DeluxDriverApp"; done)
lipo -create -output "build/deluxctl" $(for a in "${ARCHS[@]}"; do echo "$TMP/$a/deluxctl"; done)
rm -rf "$TMP"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DELUX M618XSD</string>
    <key>CFBundleDisplayName</key><string>DELUX M618XSD</string>
    <key>CFBundleIdentifier</key><string>local.gadgrandez.delux-m618xsd</string>
    <key>CFBundleExecutable</key><string>DeluxDriverApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
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
codesign --force --sign - "build/deluxctl"
echo "App created at: $(pwd)/$APP"

if [[ "${1:-}" == "--zip" ]]; then
    OUT="build/release"
    rm -rf "$OUT" && mkdir -p "$OUT"
    ditto -c -k --keepParent "$APP" "$OUT/DELUX-M618XSD-$VERSION-macOS.zip"
    ditto -c -k --keepParent "build/deluxctl" "$OUT/deluxctl-$VERSION-macOS.zip"
    (cd "$OUT" && shasum -a 256 *.zip > SHA256SUMS.txt)
    echo "Release archives in: $(pwd)/$OUT"
fi
