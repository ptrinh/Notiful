#!/bin/bash
# Build a release artifact and (if `gh` is available) cut a GitHub release.
# Usage: scripts/release.sh [version]   e.g. scripts/release.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
TAG="v${VERSION}"
ZIP="Notiful.zip"

echo "==> Building Notiful.app (release)"
./scripts/build-app.sh >/dev/null

echo "==> Zipping -> $ZIP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent Notiful.app "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo ""
echo "version : $VERSION"
echo "zip     : $ZIP ($(ls -lh "$ZIP" | awk '{print $5}'))"
echo "sha256  : $SHA"
echo ""
echo "Put this sha256 in Casks/notiful.rb (and bump its version)."
echo ""

if command -v gh >/dev/null 2>&1; then
  echo "==> Creating GitHub release $TAG and uploading $ZIP"
  gh release create "$TAG" "$ZIP" \
    --title "Notiful $VERSION" \
    --notes "Notiful $VERSION — see README for install instructions." \
    --repo ptrinh/Notiful
else
  echo "gh CLI not found. Create the release manually:"
  echo "  1. https://github.com/ptrinh/Notiful/releases/new?tag=$TAG"
  echo "  2. Upload the file: $(pwd)/$ZIP"
fi
