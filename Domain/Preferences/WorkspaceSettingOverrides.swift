import Foundation

/// Optional Workspace Setting values that override Global Setting (ADR 0016).
///
/// Phase 2 keeps this as an in-memory / test struct. Persistence under each
/// Workspace’s `config.json` arrives with Workspace create (Phase 3).
struct WorkspaceSettingOverrides: Equatable, Sendable {
    /// Workspace override for Main CLI command (ADR 0005). Empty string is a valid
    /// override (bare shell); use `nil` to inherit Global.
    var mainCLICommand: String?

    /// Workspace override for Editor command (ADR 0006). Empty = use `$EDITOR` at resolve.
    var editorCommand: String?

    /// Workspace override for Leader (if ever per-Workspace; ADR 0009 / 0016).
    var leaderKey: String?

    /// Workspace override for Workspaces Root / Prefix parent (ADR 0015).
    /// Product term for the per-Workspace parent is Prefix; included here so
    /// Effective Setting resolution is real before Workspace disk I/O exists.
    var workspacesRoot: String?

    /// Workspace override for Base Ref (ADR 0019).
    var baseRef: String?

    static let none = WorkspaceSettingOverrides()

    init(
        mainCLICommand: String? = nil,
        editorCommand: String? = nil,
        leaderKey: String? = nil,
        workspacesRoot: String? = nil,
        baseRef: String? = nil
    ) {
        self.mainCLICommand = mainCLICommand
        self.editorCommand = editorCommand
        self.leaderKey = leaderKey
        self.workspacesRoot = workspacesRoot
        self.baseRef = baseRef
    }
}
