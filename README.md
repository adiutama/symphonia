# Symphonia

Native macOS host for managing local coding agents. Product docs live in [`CONTEXT.md`](CONTEXT.md) and [`docs/`](docs/).

**License:** [MIT](LICENSE). Symphonia’s own code is MIT. Upstream [Ghostty](https://github.com/ghostty-org/ghostty) / libghostty remains under its own MIT license — we vendor a pinned build of GhosttyKit; we do not re-license upstream.

**Status:** Early public MVP (`0.x`). Expect bugs and gaps. Prefer **build from source**; GitHub Release DMGs are unsigned convenience builds (macOS may warn — see [docs/release.md](docs/release.md)).

## Requirements

- macOS 14+
- Xcode 15+ (tested with Xcode 26)
- Zig 0.16.x (to build GhosttyKit)
- Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`)

## First-time setup (GhosttyKit)

GhosttyKit is **not** committed (large binary). Build it once:

```bash
./Terminal/scripts/build-ghosttykit.sh
```

This clones [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) at the SHA in `Vendor/ghostty.pin`, builds a **native-arch** `GhosttyKit.xcframework`, and installs it to `Terminal/GhosttyKit.xcframework`.

## Open

```bash
open Symphonia.xcodeproj
```

## Build

From the repo root (after GhosttyKit exists):

```bash
xcodebuild -scheme Symphonia -configuration Debug \
  -project Symphonia.xcodeproj \
  -derivedDataPath build/DerivedData \
  build
```

Or build and run from Xcode (⌘R) with the **Symphonia** scheme.

Shared Release compile helper (same path CI uses):

```bash
./scripts/ci-build.sh
```

## Releases & changelog

- [CHANGELOG.md](CHANGELOG.md) — what changed per version  
- [docs/release.md](docs/release.md) — how shipping works (check ≠ ship, unsigned DMGs, GitHub setup)

## Layout

| Path | Role |
|------|------|
| `App/` | SwiftUI chrome and app entry |
| `Terminal/` | AppKit / GhosttyKit terminal island |
| `Domain/` | Workspace / Worktree / Overlay / Command Center logic |
| `Vendor/ghostty.pin` | Pinned upstream Ghostty commit |
| `Symphonia.xcodeproj/` | Checked-in Xcode project |
| `docs/` | Vision, ADRs, templates |
| `scripts/` | CI / release helpers |
