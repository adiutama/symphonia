# Symphonia docs

Product and architecture docs for Symphonia — a solo-developer macOS app for managing local coding agents (libghostty for terminals; Symphonia for management).

| Doc | Purpose |
|-----|---------|
| [../CONTEXT.md](../CONTEXT.md) | Ubiquitous language (glossary only) |
| [vision.md](vision.md) | Problem, approach, non-goals |
| [keymap.md](keymap.md) | Operator keybind cheatsheet (globals, CC, sequences) |
| [release.md](release.md) | Versioning, CI vs ship, unsigned GitHub Releases |
| [../CHANGELOG.md](../CHANGELOG.md) | Per-version history |
| [../LICENSE](../LICENSE) | MIT license |
| [adr/](adr/) | Architecture Decision Records |
| [templates/](templates/) | Seed files for machine-local implementation process |

## Local implementation artifacts

Personal task status, runbook tweaks, and session progress live in **`.local/`** at the repo root (gitignored).

Bootstrap once:

```bash
mkdir -p .local/spikes
cp docs/templates/local-README.md .local/README.md
cp docs/templates/tasks.md .local/tasks.md
cp docs/templates/runbook.md .local/runbook.md
cp docs/templates/progress.md .local/progress.md
```

Committed templates stay in sync with the product; your `.local/` copies hold durable day-to-day state.

## ADRs

| ADR | Decision |
|-----|----------|
| [0001](adr/0001-workspace-secret-store.md) | In-app Workspace Secret Store |
| [0002](adr/0002-secret-injection-spawn-then-direnv.md) | Inject secrets when CLI starts |
| [0003](adr/0003-workspace-git-managed-worktrees.md) | Workspace = git repo; managed Worktrees |
| [0004](adr/0004-worktree-root-symphonia-home.md) | Historical Worktree root (superseded; see 0014/0015) |
| [0005](adr/0005-main-cli-command-config.md) | Main CLI: global default + Workspace override |
| [0006](adr/0006-editor-overlay-hide-not-quit.md) | Editor Overlay: hide, don't quit |
| [0007](adr/0007-background-cli-peek-overlays.md) | Many Background CLIs as peek Overlays |
| [0008](adr/0008-overlay-switcher-editor-weight.md) | Overlay Switcher; Editor > Background attention |
| [0009](adr/0009-leader-command-mode.md) | Leader `⌘⇧P` → Command Center |
| [0010](adr/0010-native-macos-first.md) | Native macOS host first |
| [0011](adr/0011-swiftui-chrome-appkit-terminal.md) | SwiftUI chrome + AppKit terminal |
| [0012](adr/0012-workspace-data-dir-plaintext.md) | Per-Workspace data dir; plaintext secrets v1 |
| [0013](adr/0013-workspace-slug-no-multi-clone.md) | Slug id; no multi-clone Workspaces |
| [0014](adr/0014-main-repo-dir-and-external-clone.md) | Main flat sibling of Worktrees; protected + healed on open |
| [0015](adr/0015-workspace-prefix-self-contained.md) | Global root + per-Workspace prefix; self-contained |
| [0016](adr/0016-settings-workspace-overrides-global.md) | Workspace settings override global |
| [0017](adr/0017-agent-branch-three-word-auto.md) | Auto three-word Worktree folder names; manual branch optional |
| [0018](adr/0018-agent-folder-auto-branch-independent.md) | Auto folder name; branch independent |
| [0019](adr/0019-agent-branch-base-setting.md) | Worktree branch Base Ref is Effective Setting |
| [0020](adr/0020-remove-agent-keep-branch-default.md) | Remove Worktree: confirm; default keep branch |
| [0021](adr/0021-command-center-registry.md) | Command Center registry; configurable aliases |
| [0022](adr/0022-keyboard-keymap.md) | Keymap decisions (see [keymap.md](keymap.md) for tables) |
| [0023](adr/0023-activity-manager-overlay-presentation.md) | Activity Manager; Overlay is a Presentation; TUI-first, GUI escape |
