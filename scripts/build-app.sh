#!/bin/bash
# Build Notiful.app — compiles the release binary and assembles a signed .app bundle.
# Requires only the Swift toolchain (Command Line Tools is enough). No Xcode needed.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/Notiful.app"
BUNDLE_ID="com.notiful.app"
VERSION="1.0.5"

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

echo "==> Code signing (required for UNUserNotificationCenter + SMAppService)"
# Prefer a STABLE self-signed identity so macOS TCC grants (Full Disk Access, Accessibility) survive
# rebuilds — the signed app keeps the same designated requirement (identifier + cert hash) every
# build. Falls back to ad-hoc if the identity isn't set up. Run scripts/make-signing-cert.sh once.
SIGN_IDENTITY="Notiful Self-Signed"
SIGN_KEYCHAIN="$HOME/Library/Keychains/notiful-codesign.keychain-db"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  SIGN_ID="$SIGN_IDENTITY"
  [ -f "$SIGN_KEYCHAIN" ] && security unlock-keychain -p "" "$SIGN_KEYCHAIN" 2>/dev/null || true
  echo "    using stable identity: $SIGN_IDENTITY (TCC grants persist across rebuilds)"
else
  SIGN_ID="-"
  echo "    no stable identity found — using ad-hoc (FDA/Accessibility will reset each rebuild)."
  echo "    run ./scripts/make-signing-cert.sh once to fix that."
fi
# Strip extended attributes first — stray xattrs (e.g. on the copied .icns) make codesign fail with
# "resource fork ... detritus not allowed", silently leaving a wrong/incomplete signature.
xattr -cr "$APP"
codesign --force --deep --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP"
# Finder/sync services often drop a com.apple.FinderInfo xattr on the bundle root afterward, which
# trips `codesign --strict`. It isn't part of the sealed signature, so strip it post-sign.
xattr -c "$APP" 2>/dev/null || true
echo "    signed identifier: $(codesign -dv "$APP" 2>&1 | grep -i '^Identifier')"
# Hard-fail if the signature isn't valid — never silently ship/test an unsigned or broken build.
if ! codesign --verify --deep --strict "$APP" 2>/tmp/notiful_codesign.txt; then
    echo "ERROR: code signing verification FAILED:" >&2
    sed 's/^/    /' /tmp/notiful_codesign.txt >&2
    exit 1
fi
echo "    signature: valid (strict). Authority: $(codesign -dvv "$APP" 2>&1 | grep -i '^Authority' | head -1 | cut -d= -f2)"

echo ""
echo "Built: $APP"
echo "Run:   open \"$APP\"          (menu-bar app)"
echo "Once:  \"$APP/Contents/MacOS/Notiful\" --once"
echo ""
echo "NOTE: Grant Notiful Full Disk Access in System Settings → Privacy & Security."
