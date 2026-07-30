#!/usr/bin/env bash
# Build an unsigned UDZO DMG with Symphonia.app + Applications symlink.
# Usage: ./scripts/package-dmg.sh /path/to/Symphonia.app [version]
# Writes Symphonia-<version>.dmg to the current directory; prints the path.
set -euo pipefail

APP_PATH="${1:?usage: package-dmg.sh /path/to/Symphonia.app [version]}"
VERSION="${2:-}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: not an app bundle: $APP_PATH" >&2
  exit 1
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.0.0")"
fi

APP_NAME="$(basename "$APP_PATH")"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/symphonia-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

ditto "$APP_PATH" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"

DMG="Symphonia-${VERSION}.dmg"
rm -f "$DMG"
# hdiutil prints "created: …" on stdout — keep that off the captured path.
hdiutil create \
  -volname "Symphonia" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >&2

echo "$DMG"
