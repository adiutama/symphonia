import Foundation

/// Operator-wide Global Setting persisted at `~/.symphonia/preferences.toml` (T.1).
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

    /// Leader key binding that enters Command Center. Default `cmd+shift+p`
    /// (VS Code / Cursor Command Palette). Parsed by ``LeaderKeyBinding``.
    var leaderKey: String

    /// Mode applied when Leader opens Command Center (`normal` | `input`). Path B.
    var commandCenterPreferredMode: CommandCenterMode

    /// Global Workspaces Root (default parent for Workspace containers). ADR 0015.
    /// May use `~` for the Operator home directory.
    var workspacesRoot: String

    /// Default Base Ref for new Worktree branches (ADR 0019).
    var baseRef: String

    /// Operator overrides for Command sequences, keyed by stable Command `id`
    /// (e.g. `"overlay.openEditor"`, ADR 0021 CC.3 / Path B). Missing id → Command defaults.
    /// Aliases are no longer used.
    var commandBindings: [String: CommandBindingOverride]

    /// First-launch sheet dismissed. Missing file → `false`; existing TOML without key → `true`.
    var onboardingCompleted: Bool

    /// Sensible Global Setting defaults when `preferences.toml` is missing.
    static let `default` = GlobalPreferences(
        mainCLICommand: "",
        editorCommand: "",
        leaderKey: "cmd+shift+p",
        commandCenterPreferredMode: .input,
        workspacesRoot: "~/.symphonia/workspaces",
        baseRef: "main",
        commandBindings: [:],
        onboardingCompleted: false
    )

    enum CodingKeys: String, CodingKey {
        case mainCLICommand, editorCommand, leaderKey, commandCenterPreferredMode
        case workspacesRoot, baseRef, commandBindings, onboardingCompleted
    }

    init(
        mainCLICommand: String,
        editorCommand: String,
        leaderKey: String,
        commandCenterPreferredMode: CommandCenterMode = .input,
        workspacesRoot: String,
        baseRef: String,
        commandBindings: [String: CommandBindingOverride] = [:],
        onboardingCompleted: Bool = false
    ) {
        self.mainCLICommand = mainCLICommand
        self.editorCommand = editorCommand
        self.leaderKey = leaderKey
        self.commandCenterPreferredMode = commandCenterPreferredMode
        self.workspacesRoot = workspacesRoot
        self.baseRef = baseRef
        self.commandBindings = commandBindings
        self.onboardingCompleted = onboardingCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mainCLICommand = try container.decodeIfPresent(String.self, forKey: .mainCLICommand) ?? ""
        editorCommand = try container.decodeIfPresent(String.self, forKey: .editorCommand) ?? ""
        leaderKey = try container.decodeIfPresent(String.self, forKey: .leaderKey) ?? Self.default.leaderKey
        commandCenterPreferredMode = try container.decodeIfPresent(
            CommandCenterMode.self,
            forKey: .commandCenterPreferredMode
        ) ?? Self.default.commandCenterPreferredMode
        workspacesRoot = try container.decodeIfPresent(String.self, forKey: .workspacesRoot)
            ?? Self.default.workspacesRoot
        baseRef = try container.decodeIfPresent(String.self, forKey: .baseRef) ?? Self.default.baseRef
        commandBindings = try container.decodeIfPresent(
            [String: CommandBindingOverride].self,
            forKey: .commandBindings
        ) ?? [:]
        // Existing installs (key absent) skip the sheet; brand-new defaults use `false`.
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? true
    }
}
