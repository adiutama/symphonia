import Foundation

/// Effective Setting: Workspace Setting if present, otherwise Global Setting (ADR 2026-07-23-0016-settings-workspace-overrides-global).
struct EffectiveSettings: Equatable, Sendable {
    /// Resolved Main CLI command (ADR 2026-07-23-0005-main-cli-command-config). Empty means bare shell / default login CLI.
    var mainCLICommand: String

    /// Resolved Shell Activity default command. Empty = login shell Overlay.
    var shellCommand: String

    /// Resolved Editor command after applying `$EDITOR` when Global/Workspace value is empty.
    var editorCommand: String

    /// Resolved Editor Presentation (explicit or legacy heuristic).
    var editorPresentation: EditorPresentation

    /// Resolved External Editor bundle id.
    var editorBundleID: String

    /// Resolved File manager Presentation.
    var fileManagerPresentation: EditorPresentation

    /// Resolved Overlay file manager command.
    var fileManagerCommand: String

    /// Resolved External file manager bundle id.
    var fileManagerBundleID: String

    /// Resolved Leader binding (ADR 2026-07-23-0009-leader-command-mode).
    var leaderKey: String

    /// Resolved Workspaces Root path string as configured (may still contain `~`).
    var workspacesRoot: String

    /// Resolved Workspaces Root as an absolute directory URL.
    var workspacesRootURL: URL

    /// Resolved Base Ref for new Worktree branches (ADR 2026-07-23-0019-agent-branch-base-setting).
    var baseRef: String

    /// Resolve Effective Setting from Global Setting + optional Workspace overrides.
    static func resolve(
        global: GlobalPreferences,
        workspace: WorkspaceSettingOverrides? = nil
    ) -> EffectiveSettings {
        let overrides = workspace ?? .none
        let workspacesRoot = overrides.workspacesRoot ?? global.workspacesRoot
        let configuredEditor = overrides.editorCommand ?? global.editorCommand
        let editorCommand = EditorCommandResolver.resolveCommand(configured: configuredEditor)

        let explicitPresentation = overrides.editorPresentation ?? global.editorPresentation
        let editorPresentation: EditorPresentation
        if let explicitPresentation {
            editorPresentation = explicitPresentation
        } else {
            editorPresentation = EditorCommandResolver.presentation(forCommand: editorCommand)
        }

        let editorBundleID = overrides.editorBundleID ?? global.editorBundleID
        let fileManagerPresentation = overrides.fileManagerPresentation ?? global.fileManagerPresentation
        let fileManagerCommand = overrides.fileManagerCommand ?? global.fileManagerCommand
        let fileManagerBundleID = overrides.fileManagerBundleID ?? global.fileManagerBundleID

        return EffectiveSettings(
            mainCLICommand: overrides.mainCLICommand ?? global.mainCLICommand,
            shellCommand: overrides.shellCommand ?? global.shellCommand,
            editorCommand: editorCommand,
            editorPresentation: editorPresentation,
            editorBundleID: editorBundleID,
            fileManagerPresentation: fileManagerPresentation,
            fileManagerCommand: fileManagerCommand,
            fileManagerBundleID: fileManagerBundleID,
            leaderKey: Self.resolvedLeaderKey(global: global.leaderKey, workspace: overrides.leaderKey),
            workspacesRoot: workspacesRoot,
            workspacesRootURL: SymphoniaPaths.expandingTildeInPath(workspacesRoot),
            baseRef: overrides.baseRef ?? global.baseRef
        )
    }

    /// Prefer Workspace Leader when set; ignore the old stock `ctrl+p` override so Global
    /// `cmd+shift+p` can take over after the default Leader change.
    private static func resolvedLeaderKey(global: String, workspace: String?) -> String {
        guard let raw = workspace?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return global }
        let normalized = raw.lowercased()
        if normalized == "ctrl+p" || normalized == "control+p" || normalized == "⌃p" {
            return global
        }
        return raw
    }
}
