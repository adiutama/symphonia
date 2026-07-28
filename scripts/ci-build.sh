#!/usr/bin/env bash
# Shared compile path for local checks and GitHub Actions.
# Builds GhosttyKit (if needed) then Symphonia Release. Does not bump versions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/build/DerivedData}"
MARKETING_VERSION="${MARKETING_VERSION:-}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-}"

if [[ ! -d "$ROOT/Terminal/GhosttyKit.xcframework" ]]; then
  echo "==> Building GhosttyKit.xcframework"
  ./Terminal/scripts/build-ghosttykit.sh
else
  echo "==> GhosttyKit.xcframework already present"
fi

if [[ ! -d "$ROOT/Terminal/Sparkle.framework" ]]; then
  echo "==> Installing Sparkle.framework"
  ./scripts/install-sparkle.sh
else
  echo "==> Sparkle.framework already present"
fi

echo "==> Building Symphonia ($CONFIGURATION)"
XCODEBUILD_ARGS=(
  -scheme Symphonia
  -configuration "$CONFIGURATION"
  -project Symphonia.xcodeproj
  -derivedDataPath "$DERIVED_DATA"
  -destination "platform=macOS"
  CODE_SIGN_IDENTITY="-"
  CODE_SIGNING_ALLOWED=YES
  build
)

if [[ -n "$MARKETING_VERSION" ]]; then
  XCODEBUILD_ARGS+=("MARKETING_VERSION=$MARKETING_VERSION")
fi
if [[ -n "$CURRENT_PROJECT_VERSION" ]]; then
  XCODEBUILD_ARGS+=("CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION")
fi

xcodebuild "${XCODEBUILD_ARGS[@]}"

APP="$(find "$DERIVED_DATA/Build/Products/$CONFIGURATION" -name 'Symphonia.app' -type d | head -n 1 || true)"
if [[ -z "$APP" ]]; then
  echo "error: Symphonia.app not found under $DERIVED_DATA/Build/Products/$CONFIGURATION" >&2
  exit 1
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "APP_PATH=$APP" >> "$GITHUB_OUTPUT"
fi
echo "$APP"
