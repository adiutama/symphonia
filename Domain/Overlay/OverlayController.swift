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
            .receive(on: RunLoop.main)
            .sink { [weak self] focused in
                self?.onFocusedSessionChanged(focused)
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

    /// Show or hide Overlay (ADR 0022). Visible → hide; hidden → last peeked, else Editor.
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
        openEditor()
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

    // MARK: - Editor (P6.2)

    /// Open Effective Editor: TUI → Overlay PTY; GUI → external launch (no Overlay trap).
    func openEditor() {
        guard let session = agents.focusedSession else {
            lastError = "Focus Main Repo or a Worktree before opening the Editor."
            return
        }

        let command = preferences.effective.editorCommand
        let presentation = preferences.effective.editorPresentation
        let cwd = session.workingDirectory
        let env = CLISpawnEnvironment.mergingSecrets(secrets.enabledEnvironment)

        switch presentation {
        case .externalApp:
            do {
                try launchExternal(command: command, workingDirectory: cwd, environment: env)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }

        case .terminalOverlay:
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
                title: "Editor: \(shortCommand(command))",
                command: command,
                workingDirectory: cwd,
                spawnEnvironment: env
            )
            sessions.append(overlay)
            peek(overlay.id)
            lastError = nil
        }
    }

    // MARK: - Background CLI (P6.3–P6.4)

    /// Create a Background CLI Overlay and peek it. Empty draft → bare shell.
    func createBackgroundCLI() {
        guard let session = agents.focusedSession else {
            lastError = "Focus Main Repo or a Worktree before creating a Background CLI."
            return
        }

        let trimmed = draftBackgroundCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let command: String? = trimmed.isEmpty ? nil : trimmed
        let title: String
        if let command {
            title = "BG: \(shortCommand(command))"
        } else {
            title = "BG: shell"
        }

        let overlay = OverlaySession(
            id: UUID(),
            kind: .background,
            sessionId: session.id,
            title: title,
            command: command,
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
        sessions.removeAll { !liveIDs.contains($0.sessionId) }
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

    /// Launch GUI / external editor outside the Overlay host.
    private func launchExternal(
        command: String,
        workingDirectory: String,
        environment: [(key: String, value: String)]
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        var env = ProcessInfo.processInfo.environment
        for pair in CLISpawnEnvironment.mergingSecrets(environment) {
            env[pair.key] = pair.value
        }
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
