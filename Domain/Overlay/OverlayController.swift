import AppKit
import Combine
import Foundation

/// Overlay peek/hide host lifecycle (Phase 6 / ADR 0006–0008).
///
/// - One visible Overlay at a time (`visibleOverlayID`); nil = Main CLI.
/// - Hide / Switch Worktree does not remove the session → PTY stays alive until Close.
/// - Editor Overlay is first-class; Background CLIs are many freeform peeks.
/// - Peek UI is scoped to the focused session; processes may span sessions.
@MainActor
final class OverlayController: ObservableObject {
    private let preferences: PreferencesController
    private let agents: WorktreeController
    private let secrets: SecretStoreController
    private var cancellables = Set<AnyCancellable>()

    /// All live Overlay PTYs (may span Worktrees). Host keeps surfaces mounted until Close.
    @Published private(set) var sessions: [OverlaySession] = []
    /// Currently peeked Overlay; nil shows Main CLI.
    @Published private(set) var visibleOverlayID: UUID?
    /// Last peeked Overlay (Toggle Overlay restore); must belong to focused session to restore.
    private var lastPeekedOverlayID: UUID?
    @Published var lastError: String?

    /// Draft freeform command for Create Background CLI (empty = bare shell).
    @Published var draftBackgroundCommand: String = ""

    init(
        preferences: PreferencesController,
        agents: WorktreeController,
        secrets: SecretStoreController
    ) {
        self.preferences = preferences
        self.agents = agents
        self.secrets = secrets

        agents.$focusedSession
            .receive(on: DispatchQueue.main)
            .sink { [weak self] focused in
                DispatchQueue.main.async { [weak self] in
                    self?.onFocusedSessionChanged(focused)
                }
            }
            .store(in: &cancellables)
    }

    /// Overlay PTYs for the focused session (Switcher / Toggle restore).
    var focusedSessions: [OverlaySession] {
        guard let focused = agents.focusedSession else { return [] }
        return sessions.filter { $0.sessionId == focused.id }
    }

    var visibleSession: OverlaySession? {
        guard let visibleOverlayID else { return nil }
        return sessions.first { $0.id == visibleOverlayID }
    }

    /// Editor Overlay for the focused session, if any.
    var focusedEditor: OverlaySession? {
        focusedSessions.first { $0.kind == .editor }
    }

    var isShowingOverlay: Bool {
        visibleOverlayID != nil
    }

    // MARK: - Peek / hide / toggle

    /// Return to Main CLI without quitting Overlay processes (ADR 0006/0007).
    func hide() {
        if let visibleOverlayID {
            lastPeekedOverlayID = visibleOverlayID
        }
        visibleOverlayID = nil
        lastError = nil
    }

    /// Peek one Overlay over Main CLI (hides any other).
    func peek(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        visibleOverlayID = id
        lastPeekedOverlayID = id
        lastError = nil
    }

    /// Show or hide Overlay (ADR 0022). Visible → hide; hidden → last peeked, else Overlay Editor.
    /// Does not open External Editors — Toggle Overlay stays Overlay-scoped (ADR 0023).
    func toggle() {
        if isShowingOverlay {
            hide()
            return
        }
        if let id = lastPeekedOverlayID,
           focusedSessions.contains(where: { $0.id == id })
        {
            peek(id)
            return
        }
        if let editor = focusedEditor {
            peek(editor.id)
            return
        }
        // Only spawn when Editor Presentation is Overlay; External is Open Editor / Glance.
        if preferences.effective.editorPresentation == .terminalOverlay {
            openEditorOverlay()
        }
    }

    /// Explicit teardown (kills PTY when the host drops the surface).
    func close(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if lastPeekedOverlayID == id {
            lastPeekedOverlayID = nil
        }
        if visibleOverlayID == id {
            visibleOverlayID = nil
        }
    }

    /// Local Glance / Switcher label — does not change the running command.
    func rename(_ id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = sessions.firstIndex(where: { $0.id == id })
        else { return }
        sessions[index].title = trimmed
    }

    /// Overlay PTY exited (`:q`, `exit`, …): hide back to Main and drop the dead session.
    func handleProcessExit(_ id: UUID) {
        close(id)
        lastError = nil
    }

    // MARK: - Editor (P6.2)

    /// Open Effective Editor as Overlay PTY (Activity Manager delegates External).
    func openEditorOverlay() {
        guard let session = agents.focusedSession else {
            lastError = "Focus Main Repo or a Worktree before opening the Editor."
            return
        }

        let command = preferences.effective.editorCommand
        let cwd = session.workingDirectory
        let env = CLISpawnEnvironment.mergingSecrets(secrets.enabledEnvironment)

        if let existing = sessions.first(where: {
            $0.kind == .editor && $0.sessionId == session.id
        }) {
            peek(existing.id)
            lastError = nil
            return
        }

        let overlay = OverlaySession(
            id: UUID(),
            kind: .editor,
            sessionId: session.id,
            title: shortCommand(command),
            command: GhosttySpawnCommand.wrap(command),
            workingDirectory: cwd,
            spawnEnvironment: env
        )
        sessions.append(overlay)
        peek(overlay.id)
        lastError = nil
    }

    /// Open File manager as Overlay PTY when Presentation is Overlay/TUI.
    func openFileManagerOverlay(command configuredCommand: String) {
        guard let session = agents.focusedSession else {
            lastError = "Focus Main Repo or a Worktree before opening Files."
            return
        }

        let trimmed = configuredCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let command: String? = trimmed.isEmpty ? nil : trimmed
        let title = command.map(shortCommand) ?? "files"
        let cwd = session.workingDirectory
        let env = CLISpawnEnvironment.mergingSecrets(secrets.enabledEnvironment)

        if let existing = sessions.first(where: {
            $0.kind == .files && $0.sessionId == session.id
        }) {
            peek(existing.id)
            lastError = nil
            return
        }

        let overlay = OverlaySession(
            id: UUID(),
            kind: .files,
            sessionId: session.id,
            title: title,
            command: GhosttySpawnCommand.wrap(command),
            workingDirectory: cwd,
            spawnEnvironment: env
        )
        sessions.append(overlay)
        peek(overlay.id)
        lastError = nil
    }

    /// Legacy entry — prefer ``ActivityManager/openEditor()``.
    func openEditor() {
        openEditorOverlay()
    }

    // MARK: - Background CLI (P6.3–P6.4)

    /// Create a Shell Activity Overlay and peek it.
    /// Empty draft → Effective `shellCommand`, else login shell.
    func createBackgroundCLI() {
        guard let session = agents.focusedSession else {
            lastError = "Focus Main Repo or a Worktree before creating a Background CLI."
            return
        }

        let trimmed = draftBackgroundCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredDefault = preferences.effective.shellCommand
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let command: String?
        if !trimmed.isEmpty {
            command = trimmed
        } else if !configuredDefault.isEmpty {
            command = configuredDefault
        } else {
            command = nil
        }
        // Plain title — Glance / Switcher categorize via kind (shell vs editor), not a prefix.
        let title = command.map(shortCommand) ?? "shell"

        let overlay = OverlaySession(
            id: UUID(),
            kind: .background,
            sessionId: session.id,
            title: title,
            command: GhosttySpawnCommand.wrap(command),
            workingDirectory: session.workingDirectory,
            spawnEnvironment: CLISpawnEnvironment.mergingSecrets(secrets.enabledEnvironment)
        )
        sessions.append(overlay)
        draftBackgroundCommand = ""
        peek(overlay.id)
        lastError = nil
    }

    // MARK: - Internals

    private func onFocusedSessionChanged(_ focused: FocusedSession?) {
        // Leaving a Worktree only hides the peek; surfaces stay mounted until Close / owner gone.
        if let visibleOverlayID,
           let overlay = sessions.first(where: { $0.id == visibleOverlayID }),
           overlay.sessionId != focused?.id
        {
            lastPeekedOverlayID = visibleOverlayID
            self.visibleOverlayID = nil
        }
        // Tear down only when the owning Main / Worktree is gone (remove / Workspace switch).
        let liveIDs = agents.liveOverlaySessionIDs
        let kept = sessions.filter { liveIDs.contains($0.sessionId) }
        if kept.count != sessions.count {
            sessions = kept
        }
        if let lastPeekedOverlayID,
           !sessions.contains(where: { $0.id == lastPeekedOverlayID })
        {
            self.lastPeekedOverlayID = nil
        }
        if let visibleOverlayID,
           !sessions.contains(where: { $0.id == visibleOverlayID })
        {
            self.visibleOverlayID = nil
        }
    }

    private func shortCommand(_ command: String) -> String {
        let first = command.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? command
        return URL(fileURLWithPath: first).lastPathComponent
    }
}
