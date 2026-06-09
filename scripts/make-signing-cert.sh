#!/bin/bash
# Create a STABLE self-signed code-signing identity so macOS TCC grants (Full Disk Access,
# Accessibility) persist across rebuilds. Ad-hoc signing has no stable identity, so every rebuild
# changes the binary hash and invalidates those grants; a fixed certificate gives the signed app a
# stable "designated requirement" (identifier + cert hash) that TCC keeps honoring.
#
# Runs non-interactively by using a DEDICATED keychain with an empty password (so we never need your
# login keychain password). Idempotent: re-running is a no-op once the identity exists.
set -euo pipefail

IDENTITY="Notiful Self-Signed"
KEYCHAIN="notiful-codesign.keychain"
KC_PATH="$HOME/Library/Keychains/${KEYCHAIN}-db"
KC_PW=""   # empty — lets us set the key partition list without prompting

if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "Signing identity '$IDENTITY' already present — nothing to do."
  exit 0
fi

echo "==> Generating self-signed code-signing certificate"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# Use the system LibreSSL: its PKCS#12 MAC is compatible with macOS `security import`
# (Homebrew's OpenSSL 3.x writes a MAC that fails with "MAC verification failed").
SSL=/usr/bin/openssl
"$SSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" >/dev/null 2>&1
"$SSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$IDENTITY" -out "$TMP/id.p12" -passout pass:notiful >/dev/null 2>&1

echo "==> Importing into dedicated keychain ($KEYCHAIN)"
security create-keychain -p "$KC_PW" "$KEYCHAIN" 2>/dev/null || true
security set-keychain-settings "$KC_PATH"          # no auto-lock
security unlock-keychain -p "$KC_PW" "$KC_PATH"
security import "$TMP/id.p12" -k "$KC_PATH" -P notiful -A -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PW" "$KC_PATH" >/dev/null 2>&1

echo "==> Adding keychain to the user search list (preserving existing)"
EXISTING="$(security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/"//g')"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KC_PATH" $EXISTING

echo ""
echo "Done. Code-signing identities now available:"
security find-identity -p codesigning | grep "$IDENTITY" || security find-identity -p codesigning | tail -3
echo ""
echo "To undo later: security delete-keychain \"$KC_PATH\""
