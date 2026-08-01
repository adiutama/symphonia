#!/usr/bin/env bash
# One-time Sparkle EdDSA key setup for Symphonia maintainers.
#
# Writes the public key to App/SUPublicEDKey.txt (commit this file).
# Exports the private key to .scratch/sparkle/ed-private.key (gitignored).
# Add the private key contents as GitHub Actions secret SPARKLE_ED_PRIVATE_KEY.
#
# Requires Sparkle tools. Downloads them into .scratch/sparkle/ if missing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.scratch/sparkle"
ACCOUNT="xyz.adiutama.symphonia"
PUBLIC_OUT="$ROOT/App/SUPublicEDKey.txt"
PRIVATE_OUT="$TOOLS/ed-private.key"

mkdir -p "$TOOLS"
if [[ ! -x "$TOOLS/bin/generate_keys" ]]; then
  echo "==> Downloading Sparkle tools"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz" \
    -o "$TMP/Sparkle.tar.xz"
  tar -xf "$TMP/Sparkle.tar.xz" -C "$TOOLS"
fi

echo "==> Generating / looking up EdDSA keys (account: $ACCOUNT)"
echo "    macOS Keychain may prompt — allow access."
OUT="$("$TOOLS/bin/generate_keys" --account "$ACCOUNT")"
PUB="$(printf '%s\n' "$OUT" | sed -n 's/.*<string>\([^<]\{40,\}\)<\/string>.*/\1/p' | head -1)"
if [[ -z "$PUB" ]]; then
  echo "error: could not parse public key from generate_keys output" >&2
  printf '%s\n' "$OUT" >&2
  exit 1
fi

printf '%s\n' "$PUB" > "$PUBLIC_OUT"
echo "==> Wrote public key to $PUBLIC_OUT (commit this file)"

INFO_PLIST="$ROOT/App/Info.plist"
if [[ -f "$INFO_PLIST" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUB" "$INFO_PLIST" \
    || /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $PUB" "$INFO_PLIST"
  echo "==> Updated SUPublicEDKey in App/Info.plist (commit this file)"
fi

"$TOOLS/bin/generate_keys" --account "$ACCOUNT" -x "$PRIVATE_OUT"
chmod 600 "$PRIVATE_OUT"
echo "==> Exported private key to $PRIVATE_OUT (gitignored — do not commit)"
echo
echo "Next:"
echo "  1. Commit App/SUPublicEDKey.txt and App/Info.plist"
echo "  2. GitHub → Settings → Secrets → SPARKLE_ED_PRIVATE_KEY = contents of $PRIVATE_OUT"
echo "  3. Optional Apple trust: MACOS_CERTIFICATE / NOTARY_* secrets (see docs/release.md)"
