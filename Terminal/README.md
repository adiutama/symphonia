# Terminal

AppKit terminal island for libghostty / GhosttyKit (ADR 0010, 0011).

| Path | Role |
|------|------|
| `TerminalSurfaceView.swift` | `NSViewRepresentable` + `TerminalSurfaceNSView` hosting a real Ghostty surface |
| `GhosttyKit.xcframework` | Local build artifact (gitignored) — run the script below |
| `scripts/build-ghosttykit.sh` | Fetch pinned ghostty + Zig-build native GhosttyKit |
| `libghostty-plan.md` | Phase 1 options and status |

## Build GhosttyKit (required once)

Prerequisites:

- Zig **0.16.x** (Ghostty tip pins this in `build.zig.zon`). Optional: unpack into `.tools/zig/`
- Xcode with **Metal Toolchain**: `xcodebuild -downloadComponent MetalToolchain`
- Network (first clone of ghostty)

```bash
# From repo root
./Terminal/scripts/build-ghosttykit.sh
```

Pin is `Vendor/ghostty.pin` (commit SHA). Checkout lives in gitignored `Vendor/ghostty/`.

## Build / run Symphonia

```bash
xcodebuild -scheme Symphonia -configuration Debug \
  -project Symphonia.xcodeproj \
  -derivedDataPath build/DerivedData \
  build
```

Or open `Symphonia.xcodeproj` and run the **Symphonia** scheme.

The **Copy Ghostty Resources** build phase installs `terminfo` + `ghostty/themes` into
`Symphonia.app/Contents/Resources` (from `Vendor/ghostty/zig-out/share`, or Ghostty.app).
Without that, `theme = …` in `~/.config/ghostty/config` cannot resolve and surfaces fall
back to the default near-black palette.

## Status

GhosttyKit is linked. Surfaces spawn configured commands (or a shell), take keyboard/mouse input, and embed via SwiftUI `NSViewRepresentable`. See [`libghostty-plan.md`](libghostty-plan.md) for how GhosttyKit was chosen and how to rebuild it.
