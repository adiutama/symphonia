# Vision

Symphonia helps a solo Operator run multiple local coding agents without drowning in terminals, worktrees, and ad-hoc scripts.

## Positioning

**Same problem space as** [cmux](https://github.com/manaflow-ai/cmux) and [Supacode](https://github.com/supabitapp/supacode): a solo Operator running several CLI coding agents at once needs a native macOS home on libghostty — real terminals, parallel sessions, and a way to stay oriented — without Symphonia becoming the agent itself.

**Symphonia’s twist** is less “fancy terminal with tabs” and less “generic worktree IDE,” more a **managed Worktree lifecycle / control plane**:

- **Workspace** as the project unit; **Worktree** as the checkout + session unit
- **Main CLI** as home; craft **Activities** via Activity Manager (Glance) — **Overlay** peek or **External** GUI escape (hide ≠ kill for Overlay only)
- **Workspace Secret Store** injects env into Worktree CLIs (no per-Worktree `.env` copy)
- **Keyboard-first Command Center** (Leader) so app chords do not fight the PTY

libghostty is the canvas; Symphonia owns organization, secrets, and session control.

## Problem

Coding agents need real terminals, isolated checkouts, and background processes. Today that means juggling bare terminals, manual worktrees, and remembering which shell is the coding agent vs a server.

Multiple Worktrees also force a bad secrets workflow: copy `.env` on every new Worktree, then chase updates by hand. Workarounds like mise/direnv at the parent folder help, but stay outside the app.

## Approach

- **Multi-workspace** — self-contained Workspace dirs under a global Workspaces Root (`~/.symphonia/workspaces` by default); per-Workspace Prefix override allowed. `main/` and Worktree checkouts are **flat siblings** inside that dir (no `worktrees/` parent); `main/` is protected (never removed/archived) and healed on open.
- **Worktree-native** — Workspace Data Dir holds config, secrets, `main/`, and sibling Worktree folders. New Worktrees get an auto three-word **folder** name (e.g. `blue-frog-knight`); default starting branch matches that name unless the Operator supplies one; created from a configurable Base Ref (Effective Setting). The folder name stays put if the checked-out branch changes.
- **Main-CLI-centric** — Main CLI is home; craft surfaces are **Activities** (shells, editors, …) opened via a mini launcher and tracked in the **Activity Manager** (Glance). **Overlay** Presentation peeks over Main CLI (hide ≠ kill); **External** Presentation launches GUI apps with Focus/End only (ADR 2026-07-31-0023-activity-manager-overlay-presentation).
- **Split CLIs** — Main CLI runs a configured coding-agent command (global default, Workspace override); many freeform shell Activities as Overlays, not permanent panes.
- **Workspace Secret Store** — Env Vars (and Groups) live in the Workspace data dir as plaintext with tight file permissions; Enabled toggles inject into Worktree CLIs when a CLI starts.
- **Keyboard-first** — Leader (`⌘⇧P` by default, configurable) enters Command Center so app chords do not fight the PTY; mouse is secondary.
- **Attention Inbox** — for parallel internal CLIs/TUIs (Main CLI + Overlay), capture “needs you / done” in chronological order and jump to the surface (Ghostty signals + optional Notify CLI). External GUI agents are not in this inbox (ADR 2026-08-02-0100-attention-inbox-internal-cli).
- **Workspace overrides global** — Workspace settings win over app-wide defaults (Effective Setting).
- **Native macOS** — SwiftUI chrome + AppKit libghostty terminal views.

## Non-goals

- Multi-user / team fleet management
- Embedding Symphonia as a library in other products
- Replacing the coding agent itself (Symphonia manages Worktrees and their CLIs; it is not a coding agent)
- Building a full IDE (Editor is an Activity — Overlay TUI or External GUI escape — not a custom editor)
- Tracking arbitrary Mac processes unrelated to Symphonia Open/adopt
- Attention / task-done inbox for External GUI apps (e.g. Cursor) — Operator uses those apps’ own notifications
- Cross-platform desktop (macOS-native host)
- Multiple local clones of the same project as separate Workspaces (use Worktrees instead)
