#!/usr/bin/env bash
# Sign a DMG with Sparkle EdDSA and write appcast.xml for GitHub Releases.
# Usage: ./scripts/sparkle-generate-appcast.sh /path/to/Symphonia-VERSION.dmg [version]
#
# Env:
#   SPARKLE_ED_PRIVATE_KEY — private key contents (CI secret), or
#   SPARKLE_ED_PRIVATE_KEY_FILE — path to private key file
#   SPARKLE_DOWNLOAD_URL — full enclosure URL for the DMG
#   GITHUB_REPOSITORY — owner/repo (used to default download URL when unset)
#   CURRENT_PROJECT_VERSION — CFBundleVersion for the enclosure (optional)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${1:?usage: sparkle-generate-appcast.sh /path/to/Symphonia-VERSION.dmg [version]}"
VERSION="${2:-}"
TOOLS="$ROOT/.local/sparkle"
OUT_DIR="${SPARKLE_APPCAST_DIR:-$ROOT/build/sparkle}"

if [[ ! -f "$DMG" ]]; then
  echo "error: DMG not found: $DMG" >&2
  exit 1
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(basename "$DMG" | sed -n 's/^Symphonia-\(.*\)\.dmg$/\1/p')"
fi
if [[ -z "$VERSION" ]]; then
  echo "error: could not infer version; pass it as arg 2" >&2
  exit 1
fi

if [[ -z "${SPARKLE_ED_PRIVATE_KEY:-}" && -z "${SPARKLE_ED_PRIVATE_KEY_FILE:-}" ]]; then
  if [[ -f "$ROOT/.local/sparkle/ed-private.key" ]]; then
    SPARKLE_ED_PRIVATE_KEY_FILE="$ROOT/.local/sparkle/ed-private.key"
  else
    echo "error: set SPARKLE_ED_PRIVATE_KEY or SPARKLE_ED_PRIVATE_KEY_FILE (run scripts/sparkle-setup-keys.sh)" >&2
    exit 1
  fi
fi

mkdir -p "$TOOLS" "$OUT_DIR"
if [[ ! -x "$TOOLS/bin/generate_appcast" ]]; then
  echo "==> Downloading Sparkle tools"
  TMP="$(mktemp -d)"
  curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz" \
    -o "$TMP/Sparkle.tar.xz"
  tar -xf "$TMP/Sparkle.tar.xz" -C "$TOOLS"
  rm -rf "$TMP"
fi

KEY_FILE="$(mktemp)"
cleanup() { rm -f "$KEY_FILE"; }
trap cleanup EXIT

if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" > "$KEY_FILE"
else
  cp "$SPARKLE_ED_PRIVATE_KEY_FILE" "$KEY_FILE"
fi
chmod 600 "$KEY_FILE"

DOWNLOAD_URL="${SPARKLE_DOWNLOAD_URL:-}"
if [[ -z "$DOWNLOAD_URL" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  DOWNLOAD_URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/v${VERSION}/$(basename "$DMG")"
fi
if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "error: set SPARKLE_DOWNLOAD_URL or GITHUB_REPOSITORY" >&2
  exit 1
fi

# Prefix = enclosure URL without the filename (generate_appcast appends the archive name).
DOWNLOAD_PREFIX="${DOWNLOAD_URL%/*}/"

STAGE="$OUT_DIR/updates"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$DMG" "$STAGE/"

echo "==> generate_appcast"
"$TOOLS/bin/generate_appcast" \
  --ed-key-file "$KEY_FILE" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  "$STAGE"

APPCAST="$(find "$STAGE" -name 'appcast.xml' -type f | head -n 1 || true)"
if [[ -z "$APPCAST" ]]; then
  echo "error: generate_appcast did not produce appcast.xml" >&2
  exit 1
fi

cp "$APPCAST" "$OUT_DIR/appcast.xml"
echo "$OUT_DIR/appcast.xml"
