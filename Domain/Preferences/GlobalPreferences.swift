import Foundation

/// Operator-wide Global Setting persisted at `~/.symphonia/preferences.json` (ADR 0012).
///
/// Workspace Setting may override these per project; see ``EffectiveSettings`` (ADR 0016).
struct GlobalPreferences: Codable, Equatable, Sendable {
    /// Default Main CLI command (coding agent). Empty = bare shell / login CLI (ADR 0005).
    /// Workspace may override with a concrete agent command.
    var mainCLICommand: String

    /// Editor command for the Editor Overlay (ADR 0006).
    /// Empty = resolve `$EDITOR` at Effective Setting time. Prefer TUI editors for Overlay;
    /// GUI editors need external launch (see ``EditorPresentation``).
    var editorCommand: String

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
        mainCLICommand: "",
        editorCommand: "",
        leaderKey: "ctrl+p",
        workspacesRoot: "~/.symphonia/workspaces",
        baseRef: "main"
    )

    enum CodingKeys: String, CodingKey {
        case mainCLICommand, editorCommand, leaderKey, workspacesRoot, baseRef
    }

    init(
        mainCLICommand: String,
        editorCommand: String,
        leaderKey: String,
        workspacesRoot: String,
        baseRef: String
    ) {
        self.mainCLICommand = mainCLICommand
        self.editorCommand = editorCommand
        self.leaderKey = leaderKey
        self.workspacesRoot = workspacesRoot
        self.baseRef = baseRef
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mainCLICommand = try container.decodeIfPresent(String.self, forKey: .mainCLICommand) ?? ""
        editorCommand = try container.decodeIfPresent(String.self, forKey: .editorCommand) ?? ""
        leaderKey = try container.decodeIfPresent(String.self, forKey: .leaderKey) ?? Self.default.leaderKey
        workspacesRoot = try container.decodeIfPresent(String.self, forKey: .workspacesRoot)
            ?? Self.default.workspacesRoot
        baseRef = try container.decodeIfPresent(String.self, forKey: .baseRef) ?? Self.default.baseRef
    }
}
