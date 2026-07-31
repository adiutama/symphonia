import AppKit
import Combine
import Foundation

/// Activity Manager — Open · Focus · End for Overlay and External Presentations (ADR 0023).
@MainActor
final class ActivityManager: ObservableObject {
    private let preferences: PreferencesController
    private let worktrees: WorktreeController
    private let overlays: OverlayController
    private let launcher: ExternalAppLaunching
    private var cancellables = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []

    /// External Presentation inventory (Glance / Focus / End).
    @Published private(set) var externalActivities: [ExternalActivity] = []
    @Published var lastError: String?

    init(
        preferences: PreferencesController,
        worktrees: WorktreeController,
        overlays: OverlayController,
        launcher: ExternalAppLaunching = NSWorkspaceExternalAppLauncher()
    ) {
        self.preferences = preferences
        self.worktrees = worktrees
        self.overlays = overlays
        self.launcher = launcher

        worktrees.$focusedSession
            .receive(on: DispatchQueue.main)
            .sink { [weak self] focused in
                DispatchQueue.main.async { [weak self] in
                    self?.onFocusedSessionChanged(focused)
                }
            }
            .store(in: &cancellables)

        startExternalLifecycleObservation()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
    }

    // MARK: - Inventory

    func externalActivities(for sessionId: String, kind: ActivityKind) -> [ExternalActivity] {
        externalActivities.filter { $0.sessionId == sessionId && $0.kind == kind }
    }

    func isExternalFocused(_ activity: ExternalActivity) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return front == activity.bundleID
    }

    /// Drop External rows whose app quit (or Finder window closed).
    func refreshExternalInventory() {
        pruneStaleExternalActivities()
    }

    // MARK: - Open

    func openEditor() {
        guard let session = worktrees.focusedSession else {
            lastError = "Focus Main Repo or a Worktree before opening the Editor."
            return
        }

        let effective = preferences.effective
        switch effective.editorPresentation {
        case .terminalOverlay:
            overlays.openEditorOverlay()
            lastError = overlays.lastError

        case .externalApp:
            let bundleID = BundleIDResolver.resolve(
                effective.editorBundleID.isEmpty
                    ? ActivityDefaults.editorBundleID
                    : effective.editorBundleID
            )
            openExternal(
                kind: .editor,
                bundleID: bundleID,
                session: session
            )
        }
    }

    func openFiles() {
        guard let session = worktrees.focusedSession else {
            lastError = "Focus Main Repo or a Worktree before opening Files."
            return
        }

        let effective = preferences.effective
        switch effective.fileManagerPresentation {
        case .externalApp:
            let bundleID = BundleIDResolver.resolve(
                effective.fileManagerBundleID.isEmpty
                    ? ActivityDefaults.fileManagerBundleID
                    : effective.fileManagerBundleID
            )
            openExternal(
                kind: .files,
                bundleID: bundleID,
                session: session
            )

        case .terminalOverlay:
            overlays.openFileManagerOverlay(command: effective.fileManagerCommand)
            lastError = overlays.lastError
        }
    }

    // MARK: - Focus

    func focusExternal(_ id: UUID) {
        guard let activity = externalActivities.first(where: { $0.id == id }) else { return }
        let cwd = URL(fileURLWithPath: activity.workingDirectory)

        // Finder Focus: re-reveal the folder (activate alone may show unrelated windows).
        if activity.bundleID == ActivityDefaults.fileManagerBundleID {
            Task { @MainActor in
                do {
                    let result = try await launcher.open(
                        bundleID: activity.bundleID,
                        workingDirectory: cwd
                    )
                    updateProcessIdentifier(id: id, pid: result.processIdentifier)
                    lastError = nil
                } catch {
                    lastError = error.localizedDescription
                }
            }
            return
        }

        if launcher.activate(bundleID: activity.bundleID) {
            lastError = nil
            return
        }
        let bundleID = activity.bundleID
        Task { @MainActor in
            do {
                let result = try await launcher.open(bundleID: bundleID, workingDirectory: cwd)
                updateProcessIdentifier(id: id, pid: result.processIdentifier)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func focusOverlay(_ id: UUID) {
        overlays.peek(id)
        lastError = overlays.lastError
    }

    // MARK: - End

    func endExternal(_ id: UUID) {
        guard let index = externalActivities.firstIndex(where: { $0.id == id }) else { return }
        let activity = externalActivities[index]
        let cwd = URL(fileURLWithPath: activity.workingDirectory)
        launcher.end(bundleID: activity.bundleID, workingDirectory: cwd)
        externalActivities.remove(at: index)
        lastError = nil
    }

    func endOverlay(_ id: UUID) {
        overlays.close(id)
        lastError = overlays.lastError
    }

    /// Local Glance label for an External Activity (does not rename the app).
    func renameExternal(_ id: UUID, label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = externalActivities.firstIndex(where: { $0.id == id })
        else { return }
        externalActivities[index].label = trimmed
    }

    /// Local Glance / Switcher label for an Overlay Activity.
    func renameOverlay(_ id: UUID, title: String) {
        overlays.rename(id, title: title)
    }

    // MARK: - Internals

    private func openExternal(
        kind: ActivityKind,
        bundleID: String,
        session: FocusedSession
    ) {
        let resolvedBundle = BundleIDResolver.resolve(bundleID)
        guard !resolvedBundle.isEmpty else {
            lastError = "Bundle id is required for External Presentation."
            return
        }

        let cwd = URL(fileURLWithPath: session.workingDirectory)
        if let existing = externalActivities.first(where: {
            $0.kind == kind && $0.sessionId == session.id && $0.bundleID == resolvedBundle
        }) {
            focusExternal(existing.id)
            return
        }

        let sessionId = session.id
        let workingDirectory = session.workingDirectory
        Task { @MainActor in
            do {
                let result = try await launcher.open(bundleID: resolvedBundle, workingDirectory: cwd)
                let displayName = launcher.displayName(forBundleID: resolvedBundle)
                if let index = externalActivities.firstIndex(where: {
                    $0.kind == kind && $0.sessionId == sessionId && $0.bundleID == resolvedBundle
                }) {
                    if let pid = result.processIdentifier {
                        externalActivities[index].processIdentifier = pid
                    }
                } else {
                    externalActivities.append(
                        ExternalActivity(
                            id: UUID(),
                            kind: kind,
                            sessionId: sessionId,
                            bundleID: resolvedBundle,
                            displayName: displayName,
                            workingDirectory: workingDirectory,
                            processIdentifier: result.processIdentifier
                        )
                    )
                }
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func updateProcessIdentifier(id: UUID, pid: pid_t?) {
        guard let pid,
              let index = externalActivities.firstIndex(where: { $0.id == id })
        else { return }
        externalActivities[index].processIdentifier = pid
    }

    private func onFocusedSessionChanged(_ focused: FocusedSession?) {
        let liveIDs = worktrees.liveOverlaySessionIDs
        externalActivities.removeAll { !liveIDs.contains($0.sessionId) }
        pruneStaleExternalActivities()
    }

    private func startExternalLifecycleObservation() {
        let center = NSWorkspace.shared.notificationCenter

        let terminated = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                ?? note.userInfo?["NSWorkspaceApplicationKey"] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let pid = app?.processIdentifier
            Task { @MainActor in
                self?.handleApplicationTerminated(bundleID: bundleID, pid: pid)
            }
        }

        // Symphonia becomes active → re-check Finder windows / dead apps.
        let activated = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                ?? note.userInfo?["NSWorkspaceApplicationKey"] as? NSRunningApplication
            guard app?.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in
                self?.pruneStaleExternalActivities()
            }
        }

        workspaceObservers = [terminated, activated]

        // Finder never terminates; poll while External rows exist.
        Timer.publish(every: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.externalActivities.isEmpty else { return }
                self.pruneStaleExternalActivities()
            }
            .store(in: &cancellables)
    }

    private func handleApplicationTerminated(bundleID: String?, pid: pid_t?) {
        if let pid {
            externalActivities.removeAll { $0.processIdentifier == pid }
        }
        guard let bundleID else {
            pruneStaleExternalActivities()
            return
        }
        // Finder stays alive as a process — window probe handles it.
        if bundleID == ActivityDefaults.fileManagerBundleID {
            pruneStaleExternalActivities()
            return
        }
        // Drop rows for this bundle that have no pid, or whose pid is gone.
        externalActivities.removeAll { activity in
            guard activity.bundleID == bundleID else { return false }
            if let tracked = activity.processIdentifier {
                return !launcher.isProcessRunning(pid: tracked)
            }
            return !launcher.isRunning(bundleID: bundleID)
        }
    }

    private func pruneStaleExternalActivities() {
        externalActivities.removeAll { activity in
            let cwd = URL(fileURLWithPath: activity.workingDirectory)
            return !launcher.isAlive(
                bundleID: activity.bundleID,
                processIdentifier: activity.processIdentifier,
                workingDirectory: cwd
            )
        }
    }
}
