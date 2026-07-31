import Foundation

/// Optional Workspace Setting values that override Global Setting (ADR 0016).
///
/// Persisted on the selected Workspace as `config.toml` fields (T.2).
/// `workspacesRoot` here is the product **Prefix** override (ADR 0015).
struct WorkspaceSettingOverrides: Equatable, Sendable {
    /// Workspace override for Main CLI command (ADR 0005). Empty string is a valid
    /// override (bare shell); use `nil` to inherit Global.
    var mainCLICommand: String?

    /// Workspace override for Editor command (ADR 0006). Empty = use `$EDITOR` at resolve.
    var editorCommand: String?

    /// Workspace override for Shell Activity default command. Empty = login shell; `nil` inherits.
    var shellCommand: String?

    /// Workspace override for Editor Presentation. `nil` inherits Global / legacy inference.
    var editorPresentation: EditorPresentation?

    /// Workspace override for External Editor bundle id.
    var editorBundleID: String?

    /// Workspace override for File manager Presentation.
    var fileManagerPresentation: EditorPresentation?

    /// Workspace override for Overlay file manager command.
    var fileManagerCommand: String?

    /// Workspace override for External file manager bundle id.
    var fileManagerBundleID: String?

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
        shellCommand: String? = nil,
        editorPresentation: EditorPresentation? = nil,
        editorBundleID: String? = nil,
        fileManagerPresentation: EditorPresentation? = nil,
        fileManagerCommand: String? = nil,
        fileManagerBundleID: String? = nil,
        leaderKey: String? = nil,
        workspacesRoot: String? = nil,
        baseRef: String? = nil
    ) {
        self.mainCLICommand = mainCLICommand
        self.editorCommand = editorCommand
        self.shellCommand = shellCommand
        self.editorPresentation = editorPresentation
        self.editorBundleID = editorBundleID
        self.fileManagerPresentation = fileManagerPresentation
        self.fileManagerCommand = fileManagerCommand
        self.fileManagerBundleID = fileManagerBundleID
        self.leaderKey = leaderKey
        self.workspacesRoot = workspacesRoot
        self.baseRef = baseRef
    }
}
