import Foundation

/// One row in the Command Mode palette (P7.2 scaffold).
struct CommandModeItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let action: CommandModeAction

    init(id: String, title: String, subtitle: String? = nil, action: CommandModeAction) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }
}

/// Actions runnable from Command Mode (ADR 0009).
enum CommandModeAction: Equatable {
    case dismiss
    case back
    case toggleScaffolds
    case showScaffolds
    case hideScaffolds
    case openSecretStorePanel
    case switchWorkspace(id: String)
    case focusAgent(id: String)
    case newAgent
    case removeFocusedAgent
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
