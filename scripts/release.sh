#!/bin/bash
# One-command release: build + notarize, cut a GitHub release, and update the Homebrew tap.
# Usage: scripts/release.sh <version>   e.g. scripts/release.sh 1.0.7
#
# Prerequisites:
#   - A Developer ID Application identity + a stored notarytool profile ("notiful-notary").
#   - `gh` authenticated for the ptrinh/Notiful and ptrinh/homebrew-notiful repos.
#   - Your release commit already pushed to main (the git tag is cut from remote HEAD).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: scripts/release.sh <version>   e.g. scripts/release.sh 1.0.7" >&2
  exit 1
fi
TAG="v${VERSION}"
ZIP="Notiful.zip"
TAP_REPO="ptrinh/homebrew-notiful"

echo "==> Building + notarizing Notiful.app $VERSION (release)"
# NOTARIZE=1 makes build-app.sh notarize and staple the .app (needs a Developer ID identity and a
# stored notarytool keychain profile). Set NOTARIZE=0 to skip (e.g. a self-signed test release).
# VERSION is exported so the embedded bundle version matches the release/tag/cask.
VERSION="$VERSION" NOTARIZE="${NOTARIZE:-1}" ./scripts/build-app.sh

echo "==> Zipping -> $ZIP"
rm -f "$ZIP"
# The .app is already stapled, so this distribution zip carries the notarization ticket offline.
ditto -c -k --sequesterRsrc --keepParent Notiful.app "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo ""
echo "version : $VERSION"
echo "zip     : $ZIP ($(ls -lh "$ZIP" | awk '{print $5}'))"
echo "sha256  : $SHA"
echo ""

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Create the release manually, then bump the tap cask:"
  echo "  1. https://github.com/ptrinh/Notiful/releases/new?tag=$TAG  (upload $(pwd)/$ZIP)"
  echo "  2. https://github.com/$TAP_REPO/blob/main/Casks/notiful.rb  (version $VERSION, sha256 $SHA)"
  exit 0
fi

echo "==> Creating GitHub release $TAG and uploading $ZIP"
gh release create "$TAG" "$ZIP" \
  --title "Notiful $VERSION" \
  --notes "Notiful $VERSION — install with \`brew install ptrinh/notiful/notiful\`. See the README for details." \
  --repo ptrinh/Notiful

echo "==> Updating Homebrew tap ($TAP_REPO)"
# Clone the tap, bump version + sha256 in the cask, and push — so `brew upgrade` sees the new release.
TAP_DIR="$(mktemp -d)"
gh repo clone "$TAP_REPO" "$TAP_DIR" -- --depth 1 >/dev/null 2>&1
CASK="$TAP_DIR/Casks/notiful.rb"
sed -i '' -E "s/^  version \"[^\"]*\"/  version \"$VERSION\"/" "$CASK"
sed -i '' -E "s/^  sha256 \"[^\"]*\"/  sha256 \"$SHA\"/" "$CASK"
if git -C "$TAP_DIR" diff --quiet; then
  echo "    cask already at $VERSION / $SHA — nothing to push."
else
  git -C "$TAP_DIR" add Casks/notiful.rb
  git -C "$TAP_DIR" -c user.name="Phil Trinh" -c user.email="phuc@blockchain.vn" \
    commit -q -m "notiful $VERSION"
  git -C "$TAP_DIR" push -q
  echo "    pushed cask bump to $TAP_REPO (version $VERSION)."
fi

echo ""
echo "Released $TAG. Verify: brew update && brew upgrade --cask notiful"
