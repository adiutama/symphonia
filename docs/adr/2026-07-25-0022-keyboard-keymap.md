# Keyboard keymap: globals, Command Center chrome, sequences

Symphonia is keyboard-first. Most domain actions stay behind Leader → Command Center so chords do not fight the PTY (ADR 0009). A small set of **global** macOS-style chords covers high-frequency navigation and create. Command Center has fixed chrome keys plus **Normal-mode sequences**.

**Lookup tables:** in-app cheatsheet (⌘⇧/, toggle) is built live from `KeymapBindings` + `CommandRegistry`. [docs/keymap.md](../keymap.md) is the written product default for review. This ADR records *why*.

Amends ADR 0021: **default Command aliases are empty** (Operator may add free text; `/` optional). Amends the Hide-first Overlay habit (ADR 0006/0007): primary Command is **Toggle Overlay**, not a separate Hide.

## Naming

| Target | Verb | Why |
|--------|------|-----|
| Workspace (picker + cycle) | **Switch** | Change among peer projects |
| Worktree (picker + cycle) | **Switch** | Change among peer trees (includes Main in the cycle) |
| Main (explicit home) | **Focus** | One reserved home session — not “pick a peer” |

Prefer **Switch** over Select for Command titles (fits cycle language). Select may appear in empty-state microcopy only.

**Dismiss** needs no sequence — Esc and Leader-again already dismiss. Optional palette row without a chord is fine; do not spend a sequence on it.

## Design rules

1. **Globals** are ⌘/⌃ chords for create, cycle, Editor, Overlay Terminal, Overlay Switcher, Toggle Overlay, Reload, **Keymap (⌘⇧/)**, plus macOS window life. No Toggle Sidebar. Every global is also a Command (ADR 0021); register `workspace.new` if missing.
2. **Worktree cycle** includes **Main** (Main → Worktrees → wrap).
3. **Command Center chrome** includes ↑↓, **⌃N/⌃P** (both modes), j/k (Normal only), ⇧Tab, Esc, ⌃U. Held: ⌃J/K, ⌃W, ⌃A/E, Tab-to-run.
4. **CC-only chords** (⌘O, discard/rename, …) stay off the global map so they do not fight the PTY when CC is closed.
5. **Sequences:** min 2; `j`/`k` reserved. Hot path = doubles (`ww`, `tt`, `mm`, `ee`, `oo`, `rr`). Cold path = object + action (`wn`, `ot`, `os`, …). See keymap for the full table.
6. **Toggle Overlay:** visible → hide (process alive); hidden → show last Overlay. First use with nothing open: restore Editor (or no-op — settle at implement time). `ee` / `ot` / `os` remain explicit open/create/pick.

## libghostty keybinds (not Ghostty.app)

Symphonia embeds **libghostty** and loads `ghostty_config_new` → `load_default_files` → `finalize`. That installs the **same default keybind table** as Ghostty’s Config (plus `~/.config/ghostty` if present). It is not Ghostty.app’s menus.

- **Surface** binds (copy/paste, font zoom, search, scroll-to-selection, …) still run and can conflict with Symphonia globals (**⌘E**, **⌘J**, …).
- **App** binds (new window/tab, goto split, command palette, …) often no-op because Symphonia’s `action_cb` returns false, but `ghostty_surface_key_is_binding` may still **swallow** the key.

**Consequence:** for Symphonia globals to work with a focused PTY, unbind or intercept conflicting libghostty defaults (same pattern as today’s ⌘, yield and Leader monitor). Keep wanted surface binds (⌘C/V, zoom).

## Consequences

- Keep [docs/keymap.md](../keymap.md) in sync when defaults change; do not duplicate full tables elsewhere.
- Rename Commands to match the cheatsheet (Switch Workspace / Switch Worktree, Open Editor, Overlay Terminal, Toggle Overlay, Overlay Switcher).
- Replace title-derived sequences with the cheatsheet table; Settings still allow **sequence** overrides. **Hotkeys are fixed** in `KeymapBindings` (Settings Hotkey column is read-only display).
- Default aliases `[]`; alias UI removed (title/subtitle filter only).
- Implement cycle ±1 Commands; Worktree cycle includes Main.
- Embedded Ghostty config: unbind Symphonia-owned chords.
