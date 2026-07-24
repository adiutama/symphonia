import Foundation

/// One row in the Command Mode palette.
struct CommandModeItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    /// Single-key chord shown on the row (root items); matched when filter is empty.
    let keybind: String?
    let action: CommandModeAction

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        keybind: String? = nil,
        action: CommandModeAction
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keybind = keybind
        self.action = action
    }
}

/// Actions runnable from Command Mode (ADR 0009).
enum CommandModeAction: Equatable {
    case dismiss
    case back
    case openSettings
    case switchWorkspace(id: String)
    case focusMainRepo
    case focusAgent(id: String)
    case newAgent
    case removeFocusedAgent
    case removeCurrentWorkspace
    case openEditor
    case createBackground
    case peekBackground(id: UUID)
    case hideOverlay

    /// Drill into a picker list (Workspace / Agent / Background).
    case showWorkspacePicker
    case showAgentPicker
    case showBackgroundPicker
}

/// Nested palette phase after Leader (root list or a picker).
enum CommandModePhase: Equatable {
    case root
    case pickWorkspace
    case pickAgent
    case pickBackground
}
