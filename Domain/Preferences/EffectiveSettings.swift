import Foundation

/// Effective Setting: Workspace Setting if present, otherwise Global Setting (ADR 0016).
struct EffectiveSettings: Equatable, Sendable {
    /// Resolved Main CLI command (ADR 0005). Empty means bare shell / default login CLI.
    var mainCLICommand: String

    /// Resolved Editor command after applying `$EDITOR` when Global/Workspace value is empty.
    var editorCommand: String

    /// Best-effort: Overlay TUI vs external GUI (Phase 6 will branch on this).
    var editorPresentation: EditorPresentation

    /// Resolved Leader binding (ADR 0009).
    var leaderKey: String

    /// Resolved Workspaces Root path string as configured (may still contain `~`).
    var workspacesRoot: String

    /// Resolved Workspaces Root as an absolute directory URL.
    var workspacesRootURL: URL

    /// Resolved Base Ref for new Worktree branches (ADR 0019).
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

        return EffectiveSettings(
            mainCLICommand: overrides.mainCLICommand ?? global.mainCLICommand,
            editorCommand: editorCommand,
            editorPresentation: EditorCommandResolver.presentation(forCommand: editorCommand),
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
