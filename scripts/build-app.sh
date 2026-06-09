#!/bin/bash
# Build Notiful.app — compiles the release binary and assembles a signed .app bundle.
# Requires only the Swift toolchain (Command Line Tools is enough). No Xcode needed.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/Notiful.app"
BUNDLE_ID="com.notiful.app"
VERSION="1.0.0"

echo "==> Building release binary (universal: arm64 + x86_64)"
# Full Xcode's xcbuild is needed for SwiftPM's combined --arch build; with Command Line Tools we
# build each slice separately and lipo them into a universal binary.
swift build -c release --arch arm64  --product Notiful
swift build -c release --arch x86_64 --product Notiful
BIN_ARM="$(swift build -c release --arch arm64  --product Notiful --show-bin-path)/Notiful"
BIN_X86="$(swift build -c release --arch x86_64 --product Notiful --show-bin-path)/Notiful"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/Notiful" "$BIN_ARM" "$BIN_X86"
echo "    architectures: $(lipo -archs "$APP/Contents/MacOS/Notiful")"

# App icon — generate it once if missing.
if [ ! -f "$ROOT/scripts/AppIcon.icns" ]; then
  echo "==> Generating app icon"
  "$ROOT/scripts/make-icon.sh"
fi
cp "$ROOT/scripts/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Notiful</string>
    <key>CFBundleDisplayName</key>     <string>Notiful</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>      <string>Notiful</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundleVersion</key>         <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Local-only. No network access.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing (required for UNUserNotificationCenter + SMAppService)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --verbose "$APP" 2>&1 | sed 's/^/    /'

echo ""
echo "Built: $APP"
echo "Run:   open \"$APP\"          (menu-bar app)"
echo "Once:  \"$APP/Contents/MacOS/Notiful\" --once"
echo ""
echo "NOTE: Grant Notiful Full Disk Access in System Settings → Privacy & Security."
