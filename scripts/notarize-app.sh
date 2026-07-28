#!/usr/bin/env bash
# Optional Developer ID sign + notarize + staple for Symphonia.app.
# Invoked by release.yml when Apple secrets are present.
#
# Required env:
#   MACOS_CERTIFICATE          — base64-encoded .p12 (Developer ID Application)
#   MACOS_CERTIFICATE_PASSWORD — p12 password
#   APPLE_API_KEY              — App Store Connect API key (.p8) contents
#   APPLE_API_KEY_ID           — key id
#   APPLE_API_ISSUER           — issuer UUID
#
# Usage: ./scripts/notarize-app.sh /path/to/Symphonia.app
set -euo pipefail

APP_PATH="${1:?usage: notarize-app.sh /path/to/Symphonia.app}"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: not an app bundle: $APP_PATH" >&2
  exit 1
fi

for var in MACOS_CERTIFICATE MACOS_CERTIFICATE_PASSWORD APPLE_API_KEY APPLE_API_KEY_ID APPLE_API_ISSUER; do
  if [[ -z "${!var:-}" ]]; then
    echo "error: missing env $var" >&2
    exit 1
  fi
done

KEYCHAIN="symphonia-signing.keychain-db"
KEYCHAIN_PW="$(openssl rand -base64 24)"
CERT_PATH="$(mktemp).p12"
API_KEY_PATH="$(mktemp).p8"
cleanup() {
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  rm -f "$CERT_PATH" "$API_KEY_PATH"
}
trap cleanup EXIT

echo "==> Import Developer ID certificate"
echo "$MACOS_CERTIFICATE" | base64 --decode > "$CERT_PATH"
security create-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PW" "$KEYCHAIN"
security import "$CERT_PATH" -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security list-keychain -d user -s "$KEYCHAIN" $(security list-keychain -d user | sed -e s/\"//g)
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PW" "$KEYCHAIN"

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | grep 'Developer ID Application' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
if [[ -z "$IDENTITY" ]]; then
  echo "error: Developer ID Application identity not found in keychain" >&2
  security find-identity -v -p codesigning "$KEYCHAIN" || true
  exit 1
fi
echo "==> Signing with: $IDENTITY"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Notarize"
printf '%s' "$APPLE_API_KEY" > "$API_KEY_PATH"
ZIP="$(mktemp).zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP"
xcrun notarytool submit "$ZIP" \
  --key "$API_KEY_PATH" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER" \
  --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
echo "==> Notarization complete"
