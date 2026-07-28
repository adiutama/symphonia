#!/usr/bin/env bash
# Install Zig 0.16.x onto PATH (CI helper). Idempotent if zig already matches.
# Defaults to <repo>/.tools/zig so the install is cacheable without sudo.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIG_VERSION="${ZIG_VERSION:-0.16.0}"
PREFIX="${ZIG_PREFIX:-$ROOT/.tools/zig}"

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) ZIG_TRIPLE=aarch64-macos ;;
  x86_64) ZIG_TRIPLE=x86_64-macos ;;
  *)
    echo "unsupported arch: $ARCH" >&2
    exit 1
    ;;
esac

add_to_path() {
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$PREFIX" >> "$GITHUB_PATH"
  fi
  export PATH="$PREFIX:$PATH"
}

if [[ -x "$PREFIX/zig" ]]; then
  case "$("$PREFIX/zig" version)" in
    "${ZIG_VERSION}"*)
      echo "Zig $("$PREFIX/zig" version) already at $PREFIX"
      add_to_path
      exit 0
      ;;
  esac
fi

if command -v zig >/dev/null 2>&1; then
  case "$(zig version)" in
    "${ZIG_VERSION}"*)
      echo "Zig $(zig version) already on PATH"
      exit 0
      ;;
  esac
fi

URL="https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_TRIPLE}-${ZIG_VERSION}.tar.xz"
echo "Downloading $URL"
curl -fsSL "$URL" -o /tmp/zig.tar.xz

if mkdir -p "$PREFIX" 2>/dev/null && [[ -w "$PREFIX" ]]; then
  tar -xJf /tmp/zig.tar.xz -C "$PREFIX" --strip-components=1
else
  sudo mkdir -p "$PREFIX"
  sudo tar -xJf /tmp/zig.tar.xz -C "$PREFIX" --strip-components=1
fi

add_to_path
zig version
