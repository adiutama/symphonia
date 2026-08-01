# Keyboard: leader enters Command Center

Primary control uses a **leader key** that enters Command Center (Switch Workspace / Worktree, Editor, Overlay Switcher, secrets, New Worktree, etc.). While Command Center is active, keys are handled by Symphonia — not the focused PTY — so chords do not fight vim or the coding agent.

**Default Leader:** `⌘⇧P` (`cmd+shift+p`, VS Code / Cursor Command Palette convention). The binding is configurable so the Operator can overwrite it.

Product UI name is **Command Center**. Commands themselves and sequences are defined in [0021](0021-command-center-registry.md) / [0022](0022-keyboard-keymap.md).
