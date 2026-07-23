import Foundation

/// Operator-wide Global Setting persisted at `~/.symphonia/preferences.json` (ADR 0012).
///
/// Workspace Setting may override these per project; see ``EffectiveSettings`` (ADR 0016).
struct GlobalPreferences: Codable, Equatable, Sendable {
    /// Default Main CLI command (coding agent). Workspace may override (ADR 0005).
    var mainCLICommand: String

    /// Leader key binding that enters Command Mode. Default `ctrl+p` (ADR 0009).
    /// Stored as a binding string; Command Mode UI is Phase 7.
    var leaderKey: String

    /// Global Workspaces Root (default parent for Workspace containers). ADR 0015.
    /// May use `~` for the Operator home directory.
    var workspacesRoot: String

    /// Default Base Ref for new Agent branches (ADR 0019).
    var baseRef: String

    /// Sensible Global Setting defaults when `preferences.json` is missing.
    static let `default` = GlobalPreferences(
        mainCLICommand: "claude",
        leaderKey: "ctrl+p",
        workspacesRoot: "~/.symphonia/workspaces",
        baseRef: "main"
    )
}
