#!/usr/bin/env bash
# Build upstream GhosttyKit.xcframework (native host arch) for Symphonia.
# Requires: Zig 0.16.x (matching Vendor/ghostty/build.zig.zon), Xcode, Metal Toolchain.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PIN_FILE="$ROOT/Vendor/ghostty.pin"
SRC="$ROOT/Vendor/ghostty"
OUT_DIR="$ROOT/Terminal"
OUT_XCFW="$OUT_DIR/GhosttyKit.xcframework"
REPO_URL="https://github.com/ghostty-org/ghostty.git"

if [[ ! -f "$PIN_FILE" ]]; then
  echo "error: missing pin file: $PIN_FILE" >&2
  exit 1
fi

PIN="$(tr -d '[:space:]' <"$PIN_FILE" | grep -E '^[0-9a-f]{40}$' || true)"
if [[ -z "$PIN" ]]; then
  echo "error: Vendor/ghostty.pin must contain a 40-char commit SHA" >&2
  exit 1
fi

# Prefer workspace Zig (.tools/zig) then PATH.
if [[ -x "$ROOT/.tools/zig/zig" ]]; then
  export PATH="$ROOT/.tools/zig:$PATH"
elif ! command -v zig >/dev/null 2>&1; then
  echo "error: zig not found. Install Zig 0.16.x (e.g. brew install zig)" >&2
  echo "  or unpack into $ROOT/.tools/zig/" >&2
  exit 1
fi

ZIG_VER="$(zig version)"
echo "Using zig $ZIG_VER"
case "$ZIG_VER" in
  0.16.*) ;;
  *)
    echo "warning: Ghostty tip expects Zig 0.16.x; found $ZIG_VER" >&2
    ;;
esac

if ! xcrun -sdk macosx metal --version >/dev/null 2>&1; then
  echo "error: Metal Toolchain missing. Run:" >&2
  echo "  xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

mkdir -p "$ROOT/Vendor"
if [[ ! -d "$SRC/.git" ]]; then
  echo "Cloning ghostty @ $PIN ..."
  git clone --filter=blob:none "$REPO_URL" "$SRC"
fi

cd "$SRC"
git fetch --depth 1 origin "$PIN"
git checkout --detach "$PIN"

echo "Building GhosttyKit.xcframework (native arch, Debug) ..."
# Native-only cuts iOS/universal slices; skip the Ghostty.app Xcode build.
zig build \
  -Demit-xcframework=true \
  -Dxcframework-target=native \
  -Demit-macos-app=false \
  -Doptimize=Debug

BUILT="$SRC/macos/GhosttyKit.xcframework"
if [[ ! -d "$BUILT" ]]; then
  echo "error: expected artifact missing: $BUILT" >&2
  exit 1
fi

rm -rf "$OUT_XCFW"
cp -R "$BUILT" "$OUT_XCFW"
echo "Installed: $OUT_XCFW"
echo "Done. Build Symphonia with:"
echo "  xcodebuild -scheme Symphonia -configuration Debug -project Symphonia.xcodeproj -derivedDataPath build/DerivedData build"
