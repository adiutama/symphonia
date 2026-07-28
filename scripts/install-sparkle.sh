#!/usr/bin/env bash
# Download Sparkle.framework into Terminal/ (not committed — large binary).
# Usage: ./scripts/install-sparkle.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Terminal/Sparkle.framework"
VERSION="${SPARKLE_VERSION:-2.9.4}"
URL="https://github.com/sparkle-project/Sparkle/releases/download/${VERSION}/Sparkle-${VERSION}.tar.xz"

if [[ -d "$DEST" && "${FORCE:-}" != "1" ]]; then
  echo "==> Sparkle.framework already present at $DEST"
  exit 0
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "==> Downloading Sparkle $VERSION"
curl -sL "$URL" -o "$TMP/Sparkle.tar.xz"
tar -xf "$TMP/Sparkle.tar.xz" -C "$TMP"
rm -rf "$DEST"
ditto "$TMP/Sparkle.framework" "$DEST"
echo "==> Installed $DEST"
