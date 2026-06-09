#!/bin/bash
# Build Notiful.app — compiles the release binary and assembles a signed .app bundle.
# Requires only the Swift toolchain (Command Line Tools is enough). No Xcode needed.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/Notiful.app"
BUNDLE_ID="com.notiful.app"
# Embedded bundle version. release.sh overrides this via the VERSION env var so the release artifact,
# the git tag, and the cask all agree; this default is just the fallback for a plain local build.
VERSION="${VERSION:-1.0.6}"

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
# Signing identity, in order of preference:
#   1. Developer ID Application — signs with hardened runtime + secure timestamp so the app can be
#      NOTARIZED and distributed without the --no-quarantine workaround.
#   2. A STABLE self-signed identity — for local dev, so macOS TCC grants (Full Disk Access,
#      Accessibility) survive rebuilds. Run scripts/make-signing-cert.sh once to set it up.
#   3. Ad-hoc — last resort; FDA/Accessibility reset every rebuild and it can't be notarized.
DEVID_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null \
  | grep -o 'Developer ID Application: [^"]*' | head -1)"
SELFSIGN_IDENTITY="Notiful Self-Signed"
SIGN_KEYCHAIN="$HOME/Library/Keychains/notiful-codesign.keychain-db"
RUNTIME_OPTS=()
if [ -n "$DEVID_IDENTITY" ]; then
  SIGN_ID="$DEVID_IDENTITY"
  RUNTIME_OPTS=(--options runtime --timestamp)   # required for notarization
  echo "    using Developer ID: $DEVID_IDENTITY (hardened runtime + timestamp; notarizable)"
elif security find-identity -p codesigning 2>/dev/null | grep -q "$SELFSIGN_IDENTITY"; then
  SIGN_ID="$SELFSIGN_IDENTITY"
  [ -f "$SIGN_KEYCHAIN" ] && security unlock-keychain -p "" "$SIGN_KEYCHAIN" 2>/dev/null || true
  echo "    using stable self-signed identity (TCC grants persist across rebuilds; NOT notarizable)"
else
  SIGN_ID="-"
  echo "    no signing identity found — using ad-hoc (FDA/Accessibility reset each rebuild)."
  echo "    run ./scripts/make-signing-cert.sh once to fix that."
fi
# The repo may live in an iCloud-synced folder (~/Documents), where the file-provider daemon
# continuously re-stamps com.apple.FinderInfo onto the bundle root — racing codesign both at sign
# time AND at `--strict` verify time. Stage the bundle in a temp dir OUTSIDE the synced tree so all
# signing/notarizing runs on a copy nothing else touches, then copy the finished app back.
FINAL_APP="$APP"
STAGE_DIR="$(mktemp -d)"
ditto "$APP" "$STAGE_DIR/Notiful.app"
APP="$STAGE_DIR/Notiful.app"

# Strip extended attributes, then sign. No --deep: the bundle has a single Mach-O and no nested
# code, and Apple's notary service prefers items signed directly rather than via --deep. The retry
# is belt-and-suspenders in case anything still touches the staged copy.
sign_ok=0
for attempt in 1 2 3 4 5; do
  xattr -cr "$APP"
  if codesign --force "${RUNTIME_OPTS[@]}" --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP" 2>/tmp/notiful_sign.txt; then
    sign_ok=1; break
  fi
  echo "    sign attempt $attempt failed (likely an xattr race); retrying…"
  sleep 1
done
if [ "$sign_ok" != "1" ]; then
  echo "ERROR: code signing failed after retries:" >&2
  sed 's/^/    /' /tmp/notiful_sign.txt >&2
  echo "    Tip: building from a non-iCloud path (e.g. ~/Developer) avoids the xattr race entirely." >&2
  exit 1
fi
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

# Optional notarization + stapling. Enabled by NOTARIZE=1 (release.sh sets this). Needs a Developer
# ID signature and a stored notarytool keychain profile (see NOTARY_PROFILE).
NOTARY_PROFILE="${NOTARY_PROFILE:-notiful-notary}"
if [ "${NOTARIZE:-0}" = "1" ]; then
  if [ -z "$DEVID_IDENTITY" ]; then
    echo "ERROR: NOTARIZE=1 but no Developer ID identity — can't notarize." >&2
    exit 1
  fi
  echo "==> Notarizing (profile: $NOTARY_PROFILE)"
  NOTARY_ZIP="$(mktemp -d)/Notiful-notarize.zip"
  ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"
  if ! xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
    echo "ERROR: notarization failed. If this is a credentials error, run once:" >&2
    echo "    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <email> --team-id 84T567KMYD --password <app-specific-pw>" >&2
    exit 1
  fi
  echo "==> Stapling ticket to the app"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

# Copy the finished (signed + possibly notarized/stapled) app from the staging dir back to the repo
# root. The signature and stapled ticket live INSIDE the bundle, so they survive the copy even if
# iCloud later re-stamps the unsealed root xattr.
rm -rf "$FINAL_APP"
ditto "$APP" "$FINAL_APP"
rm -rf "$STAGE_DIR"
APP="$FINAL_APP"
# Final acceptance check on the real artifact. For a notarized+stapled app this should report
# "accepted ... source=Notarized Developer ID" regardless of any loose root xattr.
if [ "${NOTARIZE:-0}" = "1" ]; then
  echo "==> Gatekeeper assessment"
  spctl -a -vvv "$APP" 2>&1 | sed 's/^/    /' || true
fi

echo ""
echo "Built: $APP"
echo "Run:   open \"$APP\"          (menu-bar app)"
echo "Once:  \"$APP/Contents/MacOS/Notiful\" --once"
echo ""
echo "NOTE: Grant Notiful Full Disk Access in System Settings → Privacy & Security."
