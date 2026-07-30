# Terminal

AppKit terminal island for libghostty / GhosttyKit (ADR 0010, 0011).

| Path | Role |
|------|------|
| `TerminalSurfaceView.swift` | `NSViewRepresentable` + `TerminalSurfaceNSView` core (focus + keyboard) |
| `TerminalSurface+Mouse.swift` | Mouse report path + click-to-focus monitor (C.6) |
| `TerminalSurface+Clipboard.swift` | Context menu + Ghostty ↔ pasteboard callbacks (C.5) |
| `TerminalSurface+Lifecycle.swift` | Ghostty start/teardown, geometry, screen observers |
| `GhosttyInput.swift` | Key/mouse mod helpers + `NSEvent` → Ghostty key events |
| `GhosttyPasteboard.swift` | Selection / standard clipboard helpers (C.5) |
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

Chrome and terminals load the Operator’s Ghostty config (`~/.config/ghostty`, etc.).
Theme files resolve from, in order:

1. `GHOSTTY_RESOURCES_DIR` if already set  
2. Optional bundled `Symphonia.app/Contents/Resources/ghostty` (Copy Ghostty Resources build phase)  
3. Installed **Ghostty.app** (`Contents/Resources/ghostty`)

Nightly/Release DMGs do **not** need to ship themes — installing Ghostty.app (or pointing
`GHOSTTY_RESOURCES_DIR` at a themes root) is enough for `theme = …` to resolve.
Without any of those, surfaces fall back to the default near-black palette.

## Status

GhosttyKit is linked. Surfaces spawn configured commands (or a shell), take keyboard/mouse input, and embed via SwiftUI `NSViewRepresentable`. See [`libghostty-plan.md`](libghostty-plan.md) for how GhosttyKit was chosen and how to rebuild it.
