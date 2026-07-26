#!/usr/bin/env bash
# Install Zig 0.16.x onto PATH (CI helper). Idempotent if zig already matches.
set -euo pipefail

ZIG_VERSION="${ZIG_VERSION:-0.16.0}"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64) ZIG_TRIPLE=aarch64-macos ;;
  x86_64) ZIG_TRIPLE=x86_64-macos ;;
  *)
    echo "unsupported arch: $ARCH" >&2
    exit 1
    ;;
esac

if command -v zig >/dev/null 2>&1; then
  case "$(zig version)" in
    "${ZIG_VERSION}"*) echo "Zig $(zig version) already on PATH"; exit 0 ;;
  esac
fi

URL="https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_TRIPLE}-${ZIG_VERSION}.tar.xz"
echo "Downloading $URL"
curl -fsSL "$URL" -o /tmp/zig.tar.xz
PREFIX="${ZIG_PREFIX:-/usr/local/zig}"
sudo mkdir -p "$PREFIX"
sudo tar -xJf /tmp/zig.tar.xz -C "$PREFIX" --strip-components=1
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$PREFIX" >> "$GITHUB_PATH"
fi
export PATH="$PREFIX:$PATH"
zig version
