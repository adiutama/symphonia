# Vision

Symphonia helps a solo Operator run multiple local coding agents without drowning in terminals, worktrees, and ad-hoc scripts.

## Positioning

**Same problem space as** [cmux](https://github.com/manaflow-ai/cmux) and [Supacode](https://github.com/supabitapp/supacode): a solo Operator running several CLI coding agents at once needs a native macOS home on libghostty — real terminals, parallel sessions, and a way to stay oriented — without Symphonia becoming the agent itself.

**Symphonia’s twist** is less “fancy terminal with tabs” and less “generic worktree IDE,” more a **managed Worktree lifecycle / control plane**:

- **Workspace** as the project unit; **Worktree** as the checkout + session unit
- **Main CLI** as home; **Editor / Background CLIs** as peek Overlays (hide ≠ kill), not permanent tiles
- **Workspace Secret Store** injects env into Worktree CLIs (no per-Worktree `.env` copy)
- **Keyboard-first Command Center** (Leader) so app chords do not fight the PTY

libghostty is the canvas; Symphonia owns organization, secrets, and session control.

## Problem

Coding agents need real terminals, isolated checkouts, and background processes. Today that means juggling bare terminals, manual worktrees, and remembering which shell is the coding agent vs a server.

Multiple Worktrees also force a bad secrets workflow: copy `.env` on every new Worktree, then chase updates by hand. Workarounds like mise/direnv at the parent folder help, but stay outside the app.

## Approach

- **Multi-workspace** — self-contained Workspace dirs under a global Workspaces Root (`~/.symphonia/workspaces` by default); per-Workspace Prefix override allowed. `main/` and Worktree checkouts are **flat siblings** inside that dir (no `worktrees/` parent); `main/` is protected (never removed/archived) and healed on open.
- **Worktree-native** — Workspace Data Dir holds config, secrets, `main/`, and sibling Worktree folders. New Worktrees get an auto three-word **folder** name (e.g. `blue-frog-knight`); default starting branch matches that name unless the Operator supplies one; created from a configurable Base Ref (Effective Setting). The folder name stays put if the checked-out branch changes.
- **Main-CLI-centric** — Main CLI is home; Editor and Background CLIs peek as Overlays (hide ≠ kill), one visible at a time via the Overlay Switcher; Editor gets higher UI attention than backgrounds.
- **Split CLIs** — Main CLI runs a configured coding-agent command (global default, Workspace override); many freeform Background CLIs peeked as Overlays, not permanent panes.
- **Workspace Secret Store** — Env Vars (and Groups) live in the Workspace data dir as plaintext with tight file permissions; Enabled toggles inject into Worktree CLIs when a CLI starts.
- **Keyboard-first** — Leader (`⌘⇧P` by default, configurable) enters Command Center so app chords do not fight the PTY; mouse is secondary.
- **Workspace overrides global** — Workspace settings win over app-wide defaults (Effective Setting).
- **Native macOS** — SwiftUI chrome + AppKit libghostty terminal views.

## Non-goals

- Multi-user / team fleet management
- Embedding Symphonia as a library in other products
- Replacing the coding agent itself (Symphonia manages Worktrees and their CLIs; it is not a coding agent)
- Building a full IDE (Editor is a terminal overlay, not a custom editor)
- Cross-platform desktop (macOS-native host)
- Multiple local clones of the same project as separate Workspaces (use Worktrees instead)
