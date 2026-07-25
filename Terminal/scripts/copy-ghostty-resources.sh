#!/usr/bin/env bash
# Copy Ghostty share resources into Symphonia.app so `theme = …` resolves.
# Layout matches Ghostty.app: Contents/Resources/{terminfo,ghostty/themes}.
set -euo pipefail

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
DEST="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"

# Prefer the GhosttyKit build output; fall back to the installed Ghostty.app.
CANDIDATES=(
  "$ROOT/Vendor/ghostty/zig-out/share"
  "/Applications/Ghostty.app/Contents/Resources"
)

SHARE=""
for candidate in "${CANDIDATES[@]}"; do
  if [[ -d "$candidate/terminfo/78" || -d "$candidate/ghostty/themes" ]]; then
    SHARE="$candidate"
    break
  fi
done

if [[ -z "$SHARE" ]]; then
  echo "warning: Ghostty share resources not found — themes will not load" >&2
  echo "  tried: ${CANDIDATES[*]}" >&2
  echo "  run ./Terminal/scripts/build-ghosttykit.sh or install Ghostty.app" >&2
  exit 0
fi

echo "Copying Ghostty resources from $SHARE → $DEST"

# Sentinel Ghostty uses to discover Contents/Resources/ghostty (resourcesdir.zig).
if [[ -d "$SHARE/terminfo" ]]; then
  mkdir -p "$DEST/terminfo"
  rsync -a --delete "$SHARE/terminfo/" "$DEST/terminfo/"
fi

mkdir -p "$DEST/ghostty"
if [[ -d "$SHARE/ghostty/themes" ]]; then
  rsync -a --delete "$SHARE/ghostty/themes/" "$DEST/ghostty/themes/"
elif [[ -d "$SHARE/themes" ]]; then
  # Ghostty.app lays themes under Resources/ghostty/themes; zig-out under share/ghostty/themes.
  rsync -a --delete "$SHARE/themes/" "$DEST/ghostty/themes/"
fi

# Shell integration helps PTYs; optional but small.
if [[ -d "$SHARE/ghostty/shell-integration" ]]; then
  rsync -a --delete "$SHARE/ghostty/shell-integration/" "$DEST/ghostty/shell-integration/"
elif [[ -d "$SHARE/shell-integration" ]]; then
  rsync -a --delete "$SHARE/shell-integration/" "$DEST/ghostty/shell-integration/"
fi

echo "Ghostty themes: $(find "$DEST/ghostty/themes" -type f 2>/dev/null | wc -l | tr -d ' ') files"
