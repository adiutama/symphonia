# Keymap

Operator-facing keybind reference. **In-app cheatsheet (⌘⇧/) is live from code** (`KeymapBindings` + `CommandRegistry`); this file is the product default for docs/review. Decisions: [ADR 2026-07-25-0022-keyboard-keymap](adr/2026-07-25-0022-keyboard-keymap.md).

⌘⇧/ **toggles** the Keymap window.

Default Command **aliases are empty**. Sequences and chords below are defaults; Settings may override.

---

## Global

| Action | Key |
|--------|-----|
| Quit | ⌘Q |
| Hide Symphonia | ⌘H |
| Hide Others | ⌥⌘H |
| Minimize | ⌘M |
| Close Window | ⌘W |
| Settings | ⌘, |
| Command Center (Leader) | ⌘⇧P |
| Keymap | ⌘⇧/ |
| New Workspace | ⌘N |
| New Worktree | ⌘T |
| Next Workspace | ⌃⇥ |
| Previous Workspace | ⌃⇧⇥ |
| Next Worktree | ⌘] |
| Previous Worktree | ⌘[ |
| Focus Main | ⌘⇧M |
| Open Editor | ⌘E |
| Overlay Terminal | ⌘J |
| Overlay Switcher | ⌘⇧O |
| Toggle Overlay | ⌘⇧E |
| Reload CLI | ⌘R |

Worktree cycle includes **Main** (Main → Worktrees → wrap).

---

## Command Center chrome

Active only while Command Center is open (PTY blocked).

| Key | Action |
|-----|--------|
| ⇧Tab | Toggle Normal ↔ Input |
| Esc | Clear filter → leave nest → dismiss |
| Leader again | Dismiss |
| ↑ / ↓ | Move selection |
| ⌃N / ⌃P | Move selection (both modes) |
| ↩ | Run selected |
| ⌫ | Delete last buffer char |
| j / k | Move selection (Normal only; reserved) |
| ⌃U | Clear buffer |

---

## Command Center–only chords

| Action | Key |
|--------|-----|
| Switch Workspace… | ⌘O |
| Switch Worktree… | ⌘⇧F |
| Rename Workspace | ⌘⇧R |
| Rename Worktree | ⌘⌥R |
| Remove Worktree | ⌘⇧⌫ |
| Remove Workspace | ⌘⌥⌫ |

---

## Sequences (Normal mode)

Min length 2; `j` / `k` reserved. Hot Commands use doubles; others use object + action.

### Hot

| Seq | Command |
|-----|---------|
| ww | Switch Workspace |
| tt | Switch Worktree |
| mm | Focus Main |
| ee | Open Editor |
| oo | Toggle Overlay |
| rr | Reload CLI |

### Cold

| Seq | Command |
|-----|---------|
| wn | New Workspace |
| wr | Rename Workspace |
| wd | Remove Workspace |
| tn | New Worktree |
| tr | Rename Worktree |
| td | Remove Worktree |
| ot | Overlay Terminal |
| os | Overlay Switcher |
| so | Settings |
| kh | Keymap |

Dismiss has **no** sequence (Esc / Leader). Hide Overlay is not a Command — use **Toggle Overlay**.
