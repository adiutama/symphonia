# libghostty / GhosttyKit (how Symphonia embeds the terminal)

## Chosen approach

Embed Ghostty via upstream **GhosttyKit.xcframework** (clone [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) at the pin in `Vendor/ghostty.pin`, Zig-build native xcframework). Linked from Xcode like Ghostty’s own macOS app (ADR 0010, 0011).

Other options considered during the spike (community SPM, libghostty-vt only, raw `libghostty.a`) were not chosen for the app surface.

## Current layout

| Item | Location |
|------|----------|
| Pin | `Vendor/ghostty.pin` |
| Fetch + build script | `Terminal/scripts/build-ghosttykit.sh` |
| Checkout (gitignored) | `Vendor/ghostty/` |
| Artifact (gitignored) | `Terminal/GhosttyKit.xcframework` |
| Host | `Terminal/TerminalSurfaceView.swift` (`ghostty_app` + `ghostty_surface`, macOS nsview) |

### Build

```bash
# Prerequisites: Zig 0.16.x; xcodebuild -downloadComponent MetalToolchain
./Terminal/scripts/build-ghosttykit.sh

xcodebuild -scheme Symphonia -configuration Debug \
  -project Symphonia.xcodeproj \
  -derivedDataPath build/DerivedData \
  build
```

Ghostty’s C header is pinned, not treated as a stable public API — bump the pin deliberately when upgrading.
