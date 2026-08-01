# Architecture Decision Records

Filenames are `YYYY-MM-DD-HHMM-slug.md` (UTC) so parallel design PRs do not collide and same-day order stays clear. See [2026-08-02-0200-date-based-adr-ids](2026-08-02-0200-date-based-adr-ids.md).

**How to use:** match your topic to a row below, then open that file. Do not read every ADR unless you are doing a docs audit.

| ADR | Decision |
|-----|----------|
| [2026-08-02-0200-date-based-adr-ids](2026-08-02-0200-date-based-adr-ids.md) | Date-based ADR filenames for parallel PRs |
| [2026-08-02-0100-attention-inbox-internal-cli](2026-08-02-0100-attention-inbox-internal-cli.md) | Attention Inbox for internal Main CLI / Overlay PTYs; Notify CLI; External out of scope |
| [2026-07-31-0023-activity-manager-overlay-presentation](2026-07-31-0023-activity-manager-overlay-presentation.md) | Activity Manager; Overlay is a Presentation; TUI-first, GUI escape |
| [2026-07-25-0022-keyboard-keymap](2026-07-25-0022-keyboard-keymap.md) | Keymap decisions (see [../keymap.md](../keymap.md) for tables) |
| [2026-07-24-0021-command-center-registry](2026-07-24-0021-command-center-registry.md) | Command Center registry; configurable aliases |
| [2026-07-23-0020-remove-agent-keep-branch-default](2026-07-23-0020-remove-agent-keep-branch-default.md) | Remove Worktree: confirm; default keep branch |
| [2026-07-23-0019-agent-branch-base-setting](2026-07-23-0019-agent-branch-base-setting.md) | Worktree branch Base Ref is Effective Setting |
| [2026-07-23-0018-agent-folder-auto-branch-independent](2026-07-23-0018-agent-folder-auto-branch-independent.md) | Auto folder name; branch independent |
| [2026-07-23-0017-agent-branch-three-word-auto](2026-07-23-0017-agent-branch-three-word-auto.md) | Auto three-word Worktree folder names; manual branch optional |
| [2026-07-23-0016-settings-workspace-overrides-global](2026-07-23-0016-settings-workspace-overrides-global.md) | Workspace settings override global |
| [2026-07-23-0015-workspace-prefix-self-contained](2026-07-23-0015-workspace-prefix-self-contained.md) | Global root + per-Workspace prefix; self-contained |
| [2026-07-23-0014-main-repo-dir-and-external-clone](2026-07-23-0014-main-repo-dir-and-external-clone.md) | Main flat sibling of Worktrees; protected + healed on open |
| [2026-07-23-0013-workspace-slug-no-multi-clone](2026-07-23-0013-workspace-slug-no-multi-clone.md) | Slug id; no multi-clone Workspaces |
| [2026-07-23-0012-workspace-data-dir-plaintext](2026-07-23-0012-workspace-data-dir-plaintext.md) | Per-Workspace data dir; plaintext secrets v1 |
| [2026-07-23-0011-swiftui-chrome-appkit-terminal](2026-07-23-0011-swiftui-chrome-appkit-terminal.md) | SwiftUI chrome + AppKit terminal |
| [2026-07-23-0010-native-macos-first](2026-07-23-0010-native-macos-first.md) | Native macOS host first |
| [2026-07-23-0009-leader-command-mode](2026-07-23-0009-leader-command-mode.md) | Leader `⌘⇧P` → Command Center |
| [2026-07-23-0008-overlay-switcher-editor-weight](2026-07-23-0008-overlay-switcher-editor-weight.md) | Overlay Switcher; Editor > Background attention |
| [2026-07-23-0007-background-cli-peek-overlays](2026-07-23-0007-background-cli-peek-overlays.md) | Many Background CLIs as peek Overlays |
| [2026-07-23-0006-editor-overlay-hide-not-quit](2026-07-23-0006-editor-overlay-hide-not-quit.md) | Editor Overlay: hide, don't quit |
| [2026-07-23-0005-main-cli-command-config](2026-07-23-0005-main-cli-command-config.md) | Main CLI: global default + Workspace override |
| [2026-07-23-0004-worktree-root-symphonia-home](2026-07-23-0004-worktree-root-symphonia-home.md) | Historical Worktree root (superseded; see 2026-07-23-0014-main-repo-dir-and-external-clone / 2026-07-23-0015-workspace-prefix-self-contained) |
| [2026-07-23-0003-workspace-git-managed-worktrees](2026-07-23-0003-workspace-git-managed-worktrees.md) | Workspace = git repo; managed Worktrees |
| [2026-07-23-0002-secret-injection-spawn-then-direnv](2026-07-23-0002-secret-injection-spawn-then-direnv.md) | Inject secrets when CLI starts |
| [2026-07-23-0001-workspace-secret-store](2026-07-23-0001-workspace-secret-store.md) | In-app Workspace Secret Store |
