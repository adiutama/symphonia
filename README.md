# Symphonia

**Conduct the agent ensemble.**

A native macOS stage where you and your coding agents compose one symphony. Product docs live in [`CONTEXT.md`](CONTEXT.md) and [`docs/`](docs/).

**License:** [MIT](LICENSE). Symphonia’s own code is MIT. Upstream [Ghostty](https://github.com/ghostty-org/ghostty) / libghostty remains under its own MIT license — we vendor a pinned build of GhosttyKit; we do not re-license upstream.

**Status:** Early public MVP (`0.x`). Expect bugs and gaps. Prefer **build from source**; GitHub Release DMGs are convenience builds (unsigned unless notarization secrets are set — see [docs/release.md](docs/release.md)).

## Requirements

- macOS 26+
- Xcode 15+ (tested with Xcode 26)
- Zig 0.16.x (to build GhosttyKit)
- Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`)

## First-time setup (GhosttyKit + Sparkle)

GhosttyKit and Sparkle are **not** committed (large binaries). Install once:

```bash
./Terminal/scripts/build-ghosttykit.sh
./scripts/install-sparkle.sh
```

GhosttyKit clones [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) at the SHA in `Vendor/ghostty.pin`. Sparkle downloads the framework from the Sparkle GitHub release.

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
- [docs/release.md](docs/release.md) — how shipping works (check ≠ ship, Sparkle updates, optional notarization, GitHub setup)

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
