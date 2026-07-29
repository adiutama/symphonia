#!/usr/bin/env bash
# Fast static checks for local + PR CI (no Xcode / GhosttyKit compile).
# Usage: ./scripts/lint.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SWIFTLINT_VERSION="${SWIFTLINT_VERSION:-0.65.0}"
ACTIONLINT_VERSION="${ACTIONLINT_VERSION:-1.7.12}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: '$1' not found. Install it, or run this script in GitHub Actions." >&2
    exit 1
  fi
}

if [[ "${INSTALL_LINT_TOOLS:-}" == "1" ]]; then
  echo "==> Installing lint tools (CI)"
  sudo apt-get update -qq
  sudo apt-get install -y -qq shellcheck curl ca-certificates unzip >/dev/null

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  curl -fsSL --retry 5 \
    "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
    -o "$tmp/actionlint.tgz"
  tar -xzf "$tmp/actionlint.tgz" -C "$tmp" actionlint
  sudo install -m 755 "$tmp/actionlint" /usr/local/bin/actionlint

  curl -fsSL --retry 5 \
    "https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/swiftlint_linux_amd64.zip" \
    -o "$tmp/swiftlint.zip"
  unzip -q -o "$tmp/swiftlint.zip" -d "$tmp/swiftlint"
  sudo install -m 755 "$tmp/swiftlint/swiftlint" /usr/local/bin/swiftlint
fi

need shellcheck
need actionlint
need swiftlint

echo "==> ShellCheck"
shellcheck -x scripts/*.sh Terminal/scripts/*.sh

echo "==> actionlint"
actionlint

echo "==> SwiftLint $(swiftlint version)"
mkdir -p "$ROOT/build/swiftlint-cache"
# Warnings (e.g. force_unwrapping) print but do not fail; severity=error rules do.
swiftlint lint --quiet --cache-path "$ROOT/build/swiftlint-cache"
echo "OK"
