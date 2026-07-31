import Foundation

/// Editor Overlay vs Background CLI Overlay vs Files Overlay (ADR 0006–0008, 0023).
enum OverlayKind: String, Equatable, Sendable {
    /// High-attention craft surface (Editor Overlay).
    case editor
    /// Lighter status peek (Background CLI).
    case background
    /// TUI file manager Overlay (when File manager Presentation is Overlay).
    case files
}

/// One live Overlay session. Hide peeks away without destroying the PTY (ADR 0006/0007).
struct OverlaySession: Identifiable, Equatable {
    let id: UUID
    let kind: OverlayKind
    /// FocusedSession.id this Overlay belongs to (Main Repo or Worktree).
    let sessionId: String
    /// Glance / Switcher label (Operator can rename locally).
    var title: String
    /// Ghostty `command`; nil = bare shell.
    let command: String?
    let workingDirectory: String
    /// Enabled Secret Store snapshot at spawn (ADR 0002).
    let spawnEnvironment: [(key: String, value: String)]

    static func == (lhs: OverlaySession, rhs: OverlaySession) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.sessionId == rhs.sessionId
            && lhs.title == rhs.title
            && lhs.command == rhs.command
            && lhs.workingDirectory == rhs.workingDirectory
            && environmentEqual(lhs.spawnEnvironment, rhs.spawnEnvironment)
    }

    /// Switcher / chrome label.
    var displayKindLabel: String {
        switch kind {
        case .editor: return "Editor"
        case .background: return "Shell"
        case .files: return "Files"
        }
    }

    private static func environmentEqual(
        _ lhs: [(key: String, value: String)],
        _ rhs: [(key: String, value: String)]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (a, b) in zip(lhs, rhs) {
            if a.key != b.key || a.value != b.value { return false }
        }
        return true
    }
}
