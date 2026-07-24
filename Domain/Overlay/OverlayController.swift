import AppKit
import Combine
import Foundation

/// Overlay peek/hide host lifecycle (Phase 6 / ADR 0006–0008).
///
/// - One visible Overlay at a time (`visibleOverlayID`); nil = Main CLI.
/// - Hide does not remove the session → PTY stays alive while the surface stays mounted.
/// - Editor Overlay is first-class; Background CLIs are many freeform peeks.
/// - Scoped to the focused session (Main Repo or Agent).
@MainActor
final class OverlayController: ObservableObject {
    private let preferences: PreferencesController
    private let agents: AgentController
    private let secrets: SecretStoreController
    private var cancellables = Set<AnyCancellable>()

    /// All live Overlay PTYs (may span sessions; host filters by focused session).
    @Published private(set) var sessions: [OverlaySession] = []
    /// Currently peeked Overlay; nil shows Main CLI.
    @Published private(set) var visibleOverlayID: UUID?
    @Published var lastError: String?
    @Published var lastInfo: String?

    /// Draft freeform command for Create Background CLI (empty = bare shell).
    @Published var draftBackgroundCommand: String = ""

    init(
        preferences: PreferencesController,
        agents: AgentController,
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

    /// Overlay PTYs for the focused session (switcher + host).
    var focusedSessions: [OverlaySession] {
        guard let focused = agents.focusedSession else { return [] }
        return sessions.filter { $0.sessionId == focused.id }
    }

    var visibleSession: OverlaySession? {
        guard let visibleOverlayID else { return nil }
        return sessions.first { $0.id == visibleOverlayID }
    }

    /// Background CLIs for the focused session (Status Cue).
    var focusedBackgroundCount: Int {
        focusedSessions.filter { $0.kind == .background }.count
    }

    var isShowingOverlay: Bool {
        visibleOverlayID != nil
    }

    // MARK: - Peek / hide

    /// Return to Main CLI without quitting Overlay processes (ADR 0006/0007).
    func hide() {
        visibleOverlayID = nil
        lastError = nil
    }

    /// Peek one Overlay over Main CLI (hides any other).
    func peek(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        visibleOverlayID = id
        lastError = nil
    }

    /// Explicit teardown (kills PTY when the host drops the surface).
    func close(_ id: UUID) {
        sessions.removeAll { $0.id == id }
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
                lastInfo = "Launched external editor: \(command)"
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }

        case .terminalOverlay:
            if let existing = sessions.first(where: {
                $0.kind == .editor && $0.sessionId == session.id
            }) {
                peek(existing.id)
                lastInfo = "Peeking existing Editor Overlay"
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
            lastInfo = "Editor Overlay: \(command)"
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
        lastInfo = "Background CLI created"
        lastError = nil
    }

    // MARK: - Internals

    private func onFocusedSessionChanged(_ focused: FocusedSession?) {
        // Hide when leaving a session; keep other sessions' Overlay PTYs alive for return.
        if let visibleOverlayID,
           let overlay = sessions.first(where: { $0.id == visibleOverlayID }),
           overlay.sessionId != focused?.id
        {
            self.visibleOverlayID = nil
        }
        // Drop sessions whose owner is gone (removed Agent / closed Workspace).
        let liveIDs = agents.liveOverlaySessionIDs
        sessions.removeAll { !liveIDs.contains($0.sessionId) }
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
