import Foundation

/// Operator-wide Global Setting persisted at `~/.symphonia/preferences.toml` (T.1).
///
/// Workspace Setting may override these per Workspace; see ``EffectiveSettings`` (ADR 2026-07-23-0016-settings-workspace-overrides-global).
struct GlobalPreferences: Codable, Equatable, Sendable {
    /// Default Main CLI command (coding agent). Empty = bare shell / login CLI (ADR 2026-07-23-0005-main-cli-command-config).
    /// Workspace may override with a concrete agent command.
    var mainCLICommand: String

    /// Editor command for Overlay Presentation (ADR 2026-07-23-0006-editor-overlay-hide-not-quit).
    /// Empty = resolve `$EDITOR` at Effective Setting time. Prefer TUI editors for Overlay;
    /// GUI editors use External Presentation.
    var editorCommand: String

    /// Default command for Shell Activities (Overlay Terminal / Glance Open Shell).
    /// Empty = login shell in the Worktree.
    var shellCommand: String

    /// Explicit Editor Presentation. `nil` = infer from command (legacy).
    var editorPresentation: EditorPresentation?

    /// Bundle id for External Editor (default TextEdit when External and empty).
    var editorBundleID: String

    /// File manager Presentation (default External / Finder).
    var fileManagerPresentation: EditorPresentation

    /// Overlay file manager command (TUI). Empty = bare shell in Overlay.
    var fileManagerCommand: String

    /// Bundle id for External file manager (default Finder).
    var fileManagerBundleID: String

    /// One-time reminder shown when Operator picks GUI Editor.
    var hasSeenExternalEditorReminder: Bool

    /// Leader key binding that enters Command Center. Default `cmd+shift+p`
    /// (VS Code / Cursor Command Palette). Parsed by ``LeaderKeyBinding``.
    var leaderKey: String

    /// Mode applied when Leader opens Command Center (`normal` | `input`).
    var commandCenterPreferredMode: CommandCenterMode

    /// Global Workspaces Root (default parent for Workspace containers). ADR 2026-07-23-0015-workspace-prefix-self-contained.
    /// May use `~` for the Operator home directory.
    var workspacesRoot: String

    /// Default Base Ref for new Worktree branches (ADR 2026-07-23-0019-agent-branch-base-setting).
    var baseRef: String

    /// Operator overrides for Command sequences, keyed by stable Command `id`
    /// (e.g. `"overlay.openEditor"`, ADR 2026-07-24-0021-command-center-registry CC.3 / ADR 2026-07-25-0022-keyboard-keymap). Missing id → Command defaults.
    /// Aliases are no longer used.
    var commandBindings: [String: CommandBindingOverride]

    /// First-launch sheet dismissed. Missing file → `false`; existing TOML without key → `true`.
    var onboardingCompleted: Bool

    /// Frosted glass sidebar + light window blur. Missing key → `true`.
    var chromeGlass: Bool

    /// Sparkle update channel (Stable vs Nightly). Missing key → Stable.
    var updateChannel: UpdateChannel

    /// Sensible Global Setting defaults when `preferences.toml` is missing.
    static let `default` = GlobalPreferences(
        mainCLICommand: "",
        editorCommand: "",
        shellCommand: "",
        editorPresentation: nil,
        editorBundleID: ActivityDefaults.editorBundleID,
        fileManagerPresentation: ActivityDefaults.fileManagerPresentation,
        fileManagerCommand: "",
        fileManagerBundleID: ActivityDefaults.fileManagerBundleID,
        hasSeenExternalEditorReminder: false,
        leaderKey: "cmd+shift+p",
        commandCenterPreferredMode: .input,
        workspacesRoot: "~/.symphonia/workspaces",
        baseRef: "main",
        commandBindings: [:],
        onboardingCompleted: false,
        chromeGlass: true,
        updateChannel: .stable
    )

    enum CodingKeys: String, CodingKey {
        case mainCLICommand, editorCommand, shellCommand, editorPresentation, editorBundleID
        case fileManagerPresentation, fileManagerCommand, fileManagerBundleID
        case hasSeenExternalEditorReminder
        case leaderKey, commandCenterPreferredMode
        case workspacesRoot, baseRef, commandBindings, onboardingCompleted, chromeGlass
        case updateChannel
    }

    init(
        mainCLICommand: String,
        editorCommand: String,
        shellCommand: String = "",
        editorPresentation: EditorPresentation? = nil,
        editorBundleID: String = ActivityDefaults.editorBundleID,
        fileManagerPresentation: EditorPresentation = ActivityDefaults.fileManagerPresentation,
        fileManagerCommand: String = "",
        fileManagerBundleID: String = ActivityDefaults.fileManagerBundleID,
        hasSeenExternalEditorReminder: Bool = false,
        leaderKey: String,
        commandCenterPreferredMode: CommandCenterMode = .input,
        workspacesRoot: String,
        baseRef: String,
        commandBindings: [String: CommandBindingOverride] = [:],
        onboardingCompleted: Bool = false,
        chromeGlass: Bool = true,
        updateChannel: UpdateChannel = .stable
    ) {
        self.mainCLICommand = mainCLICommand
        self.editorCommand = editorCommand
        self.shellCommand = shellCommand
        self.editorPresentation = editorPresentation
        self.editorBundleID = editorBundleID
        self.fileManagerPresentation = fileManagerPresentation
        self.fileManagerCommand = fileManagerCommand
        self.fileManagerBundleID = fileManagerBundleID
        self.hasSeenExternalEditorReminder = hasSeenExternalEditorReminder
        self.leaderKey = leaderKey
        self.commandCenterPreferredMode = commandCenterPreferredMode
        self.workspacesRoot = workspacesRoot
        self.baseRef = baseRef
        self.commandBindings = commandBindings
        self.onboardingCompleted = onboardingCompleted
        self.chromeGlass = chromeGlass
        self.updateChannel = updateChannel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mainCLICommand = try container.decodeIfPresent(String.self, forKey: .mainCLICommand) ?? ""
        editorCommand = try container.decodeIfPresent(String.self, forKey: .editorCommand) ?? ""
        shellCommand = try container.decodeIfPresent(String.self, forKey: .shellCommand) ?? ""
        editorPresentation = try container.decodeIfPresent(EditorPresentation.self, forKey: .editorPresentation)
        editorBundleID = try container.decodeIfPresent(String.self, forKey: .editorBundleID)
            ?? ActivityDefaults.editorBundleID
        fileManagerPresentation = try container.decodeIfPresent(
            EditorPresentation.self,
            forKey: .fileManagerPresentation
        ) ?? ActivityDefaults.fileManagerPresentation
        fileManagerCommand = try container.decodeIfPresent(String.self, forKey: .fileManagerCommand) ?? ""
        fileManagerBundleID = try container.decodeIfPresent(String.self, forKey: .fileManagerBundleID)
            ?? ActivityDefaults.fileManagerBundleID
        hasSeenExternalEditorReminder = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasSeenExternalEditorReminder
        ) ?? false
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
        chromeGlass = try container.decodeIfPresent(Bool.self, forKey: .chromeGlass) ?? true
        updateChannel = try container.decodeIfPresent(UpdateChannel.self, forKey: .updateChannel) ?? .stable
    }
}
