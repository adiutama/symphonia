import Foundation

/// Craft-surface kind tracked by Activity Manager (ADR 2026-07-31-0023-activity-manager-overlay-presentation).
enum ActivityKind: String, Equatable, Sendable, Codable {
    case shell
    case editor
    case files
}

/// Overlay vs External Presentation for an Activity (ADR 2026-07-31-0023-activity-manager-overlay-presentation).
typealias ActivityPresentation = EditorPresentation

/// One External Presentation Activity (GUI outside Symphonia).
struct ExternalActivity: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: ActivityKind
    /// `FocusedSession.id` this Activity belongs to.
    let sessionId: String
    let bundleID: String
    /// App display name from Launch Services (stable).
    let displayName: String
    /// Operator-facing Glance label; defaults to ``displayName``, renamable locally.
    var label: String
    let workingDirectory: String
    /// Process id from launch when known — preferred liveness signal over bundle id alone.
    var processIdentifier: pid_t?

    init(
        id: UUID,
        kind: ActivityKind,
        sessionId: String,
        bundleID: String,
        displayName: String,
        label: String? = nil,
        workingDirectory: String,
        processIdentifier: pid_t? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sessionId = sessionId
        self.bundleID = bundleID
        self.displayName = displayName
        self.label = label ?? displayName
        self.workingDirectory = workingDirectory
        self.processIdentifier = processIdentifier
    }
}

/// Stable defaults for stock macOS tools (ADR 2026-07-31-0023-activity-manager-overlay-presentation).
enum ActivityDefaults {
    static let editorBundleID = "com.apple.TextEdit"
    static let fileManagerBundleID = "com.apple.finder"
    static let fileManagerPresentation: ActivityPresentation = .externalApp
    static let editorPresentation: ActivityPresentation = .terminalOverlay
}
