# Implementation task map (Symphonia v0 → v1)

Status legend: `todo` · `doing` · `done` · `blocked`

Update statuses only in **your** `.local/tasks.md` copy (gitignored). This template tracks shipped phases for the current app.

---

## Phase 0 — Repo & toolchain

| ID | Task | ADR / docs | Status |
|----|------|------------|--------|
| P0.1 | Xcode / Swift macOS app target in repo | 0010, 0011 | done |
| P0.2 | Project layout (`App/`, `Terminal/`, `Domain/`, …) | — | done |
| P0.3 | Build GhosttyKit into the app | 0010, 0011 | done |
| P0.4 | Minimal CI or `README` build instructions | — | done |

---

## Phase 1 — Terminal spike (prove the island)

| ID | Task | ADR / docs | Status |
|----|------|------------|--------|
| P1.1 | AppKit terminal view hosting libghostty render state | 0011 | done |
| P1.2 | PTY: spawn shell, bytes ↔ terminal | 0011 | done |
| P1.3 | Keyboard/mouse input into PTY | 0011 | done |
| P1.4 | Embed that view in SwiftUI via representable | 0011 | done |
| P1.5 | Spike write-up in `.local/spikes/` (what broke, what’s next) | runbook | done (optional archive) |

**Exit:** You can open the app, get a working shell, type, see output. — met.

---

## Phase 2 — App shell & Effective Settings

| ID | Task | ADR / docs | Status |
|----|------|------------|--------|
| P2.1 | Global preferences store (`~/.symphonia/preferences.toml`) | 0012, 0016 | done |
| P2.2 | Effective Setting resolver (Workspace overrides global) | 0016 | done |
| P2.3 | Settings: default Main CLI command | 0005 | done |
| P2.4 | Settings: Leader key (default `⌘⇧P`) | 0009 | done |
| P2.5 | Settings: Workspaces Root + default Base Ref | 0015, 0019 | done |
| P2.6 | SwiftUI chrome scaffold (no real domain yet) | 0011 | done |

---

## Phase 3 — Workspace container

| ID | Task | ADR / docs | Status |
|----|------|------------|--------|
| P3.1 | Create Workspace (slug) → Workspace Data Dir | 0013, 0015 | done |
| P3.2 | Layout: `config.toml`, `secrets.toml`, `main/`, flat Worktree siblings | 0012, 0014, 0015 | done |
| P3.3 | Prefix override per Workspace | 0015, 0016 | done |
| P3.4 | Init or clone into `main/` | 0014 | done (git init; clone-later documented) |
| P3.5 | Open existing: ensure CLI-prepared `main/` works | 0014 | done |
| P3.6 | List / switch Workspaces in UI | vision | done |

---

## Phase 4 — Worktree lifecycle

| ID | Task | ADR / docs | Status |
|----|------|------------|--------|
| P4.1 | Three-Word Name generator + collision check | 0017, 0018 | done |
| P4.2 | Create Worktree: `git worktree add` as sibling of `main/` | 0003, 0018 | done |
| P4.3 | Default branch = folder name; optional manual branch | 0017, 0018 | done |
| P4.4 | Branch from Effective Base Ref | 0019 | done |
| P4.5 | Spawn Main CLI in Worktree cwd (configured command) | 0005 | done |
| P4.6 | Remove Worktree: confirm; default keep branch | 0020 | done |
| P4.7 | List / Switch Worktrees within a Workspace | vision | done |

---

## Phase 5 — Secret Store (spawn inject)

| ID | Task | ADR / docs | Status |
|----|------|------------|--------|
| P5.1 | Persist Env Vars + Groups in Workspace Data Dir (0600) | 0001, 0012 | done |
| P5.2 | Enabled toggles for var and group | 0001 | done |
| P5.3 | Inject Enabled set when Main/Background CLI starts | 0002 | done |
| P5.4 | Secret Store UI (Postman-like, SwiftUI) | 0001 | done |
| P5.5 | Never write secrets into Worktree checkouts | 0001, 0012 | done |

---

## Phase 6 — Overlays (peek, don’t tile)

| ID | Task | ADR / docs | Status |
|----|------|------------|--------|
| P6.1 | Overlay host: one visible surface over Main CLI | 0008 | done |
| P6.2 | Editor Overlay: `$EDITOR` / configured; hide ≠ quit | 0006 | done |
| P6.3 | Background CLI: create many freeform PTYs | 0007 | done |
| P6.4 | Peek/hide and Switch Worktree keep Overlay PTYs alive until Close | 0006, 0007 | done |
| P6.5 | Overlay Switcher | 0008 | done |
| P6.6 | Editor vs Background UI weight | 0008 | done |

---

## Phase 7 — Command Center

| ID | Task | ADR / docs | Status |
|----|------|------------|--------|
| P7.1 | Leader `⌘⇧P` enters Command Center (PTY does not get keys) | 0009 | done |
| P7.2 | Commands: Switch Workspace/Worktree, Editor, Overlay Terminal / Switcher, secrets, New/Remove Worktree | 0009 | done |
| P7.3 | Leader binding configurable | 0009, 0016 | done |

---

## Out of scope

- Multi-user / team fleet
- Cross-platform host
- Embedding Symphonia as a library
- Building a custom IDE editor
- Multi-clone Workspaces for one project
