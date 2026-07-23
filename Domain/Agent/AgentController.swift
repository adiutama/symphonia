import Foundation
import Combine

/// Observable Agent list / create / focus / remove + focused session (Main Repo or Agent).
@MainActor
final class AgentController: ObservableObject {
    private let store: AgentStore
    private let preferences: PreferencesController
    private let workspaces: WorkspaceController
    private let secrets: SecretStoreController?
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var agents: [AgentSummary] = []
    /// Main Repo or Agent — drives Main CLI cwd and Overlay scope.
    @Published private(set) var focusedSession: FocusedSession?
    /// Enabled Secret Store env snapshotted at focus / create (ADR 0002 spawn-only).
    @Published private(set) var focusedSpawnEnvironment: [(key: String, value: String)] = []
    @Published var lastError: String?

    /// Optional manual branch name on create; empty → Three-Word folder name (ADR 0018).
    @Published var draftBranchName: String = ""

    /// Pending remove target for confirm UI (ADR 0020).
    @Published var pendingRemove: AgentSummary?

    /// When confirming remove, optionally also delete the branch (default keep).
    @Published var pendingRemoveDeleteBranch: Bool = false

    init(
        preferences: PreferencesController,
        workspaces: WorkspaceController,
        secrets: SecretStoreController? = nil,
        store: AgentStore = AgentStore()
    ) {
        self.preferences = preferences
        self.workspaces = workspaces
        self.secrets = secrets
        self.store = store

        workspaces.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.onWorkspaceChanged()
            }
            .store(in: &cancellables)
    }

    /// Focused Agent when session is an Agent; nil for Main Repo.
    var focused: AgentSummary? {
        focusedSession?.agent
    }

    /// Effective Main CLI command for the focused session’s terminal spawn (empty = bare shell).
    var focusedMainCLICommand: String {
        preferences.effective.mainCLICommand
    }

    /// Cwd for Ghostty surface when a session is focused; nil otherwise.
    var focusedWorkingDirectory: String? {
        focusedSession?.workingDirectory
    }

    /// Non-empty Main CLI command for surface `command`, or nil for Ghostty default shell.
    var focusedSpawnCommand: String? {
        let cmd = focusedMainCLICommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return cmd.isEmpty ? nil : cmd
    }

    /// Session ids whose Overlay PTYs should stay alive (current Workspace Main + Agents).
    var liveOverlaySessionIDs: Set<String> {
        var ids = Set(agents.map { FocusedSession.agent($0).id })
        if let current = workspaces.current {
            ids.insert(FocusedSession.mainRepo(for: current).id)
        }
        return ids
    }

    func refresh() {
        guard let current = workspaces.current else {
            agents = []
            if focusedSession != nil {
                focusedSession = nil
                focusedSpawnEnvironment = []
            }
            return
        }

        do {
            agents = try store.list(workspaceDataDir: current.dataDirURL)
            lastError = nil
            reconcileFocusedSession(workspace: current)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Agents under any Workspace Data Dir (sidebar expansion).
    func agents(in workspace: WorkspaceSummary) -> [AgentSummary] {
        if workspace.id == workspaces.current?.id {
            return agents
        }
        return (try? store.list(workspaceDataDir: workspace.dataDirURL)) ?? []
    }

    /// Create Agent under the selected Workspace (P4.1–P4.4).
    func createAgent() {
        guard let current = workspaces.current else {
            lastError = AgentStore.StoreError.noWorkspace.localizedDescription
            return
        }

        do {
            let existing = try store.existingFolderNames(workspaceDataDir: current.dataDirURL)
            let threeWord = try ThreeWordName.generateUnique(existing: existing)
            let manual = draftBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
            let branch = manual.isEmpty ? threeWord : manual
            let baseRef = preferences.effective.baseRef

            let summary = try store.create(
                workspaceDataDir: current.dataDirURL,
                threeWordName: threeWord,
                branchName: branch,
                baseRef: baseRef
            )
            draftBranchName = ""
            refresh()
            focus(summary)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Focus Main Repo for the given Workspace (cwd = `<workspace>/main/`).
    func focusMain(for workspace: WorkspaceSummary) {
        applyFocus(.mainRepo(for: workspace))
    }

    func focus(_ agent: AgentSummary) {
        applyFocus(.agent(agent))
    }

    /// Re-apply current Enabled Secret Store set by restarting the focused session CLI.
    func respawnWithCurrentSecrets() {
        guard let focusedSession else { return }
        applyFocus(focusedSession)
    }

    func clearFocus() {
        focusedSession = nil
        focusedSpawnEnvironment = []
    }

    /// Begin Remove Agent confirm (ADR 0020).
    func requestRemove(_ agent: AgentSummary) {
        pendingRemoveDeleteBranch = false
        pendingRemove = agent
    }

    func cancelRemove() {
        pendingRemove = nil
        pendingRemoveDeleteBranch = false
    }

    /// Confirm Remove Agent: unregister worktree + delete folder; keep branch unless opted in.
    func confirmRemove() {
        guard let current = workspaces.current,
              let agent = pendingRemove
        else {
            pendingRemove = nil
            return
        }

        do {
            try store.remove(
                workspaceDataDir: current.dataDirURL,
                agent: agent,
                deleteBranch: pendingRemoveDeleteBranch
            )
            if focusedSession?.agent?.id == agent.id {
                focusMain(for: current)
            }
            pendingRemove = nil
            pendingRemoveDeleteBranch = false
            refresh()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            pendingRemove = nil
            pendingRemoveDeleteBranch = false
        }
    }

    // MARK: - Internals

    private func applyFocus(_ session: FocusedSession) {
        focusedSession = session
        // Spawn-time inject: snapshot Enabled set now; live Secret Store edits do not rewrite this shell.
        focusedSpawnEnvironment = secrets?.enabledEnvironment ?? []
        lastError = nil
    }

    private func reconcileFocusedSession(workspace: WorkspaceSummary) {
        switch focusedSession {
        case .none:
            focusMain(for: workspace)
        case .mainRepo(let workspaceId, _, _)?:
            if workspaceId != workspace.id {
                focusMain(for: workspace)
            } else {
                // Refresh main path / slug if Workspace moved.
                focusedSession = .mainRepo(for: workspace)
            }
        case .agent(let agent)?:
            if let updated = agents.first(where: { $0.id == agent.id }) {
                focusedSession = .agent(updated)
            } else {
                focusMain(for: workspace)
            }
        }
    }

    private func onWorkspaceChanged() {
        pendingRemove = nil
        pendingRemoveDeleteBranch = false
        draftBranchName = ""
        guard let current = workspaces.current else {
            agents = []
            focusedSession = nil
            focusedSpawnEnvironment = []
            return
        }
        refresh()
        // Always land on Main Repo when switching Workspace.
        focusMain(for: current)
    }
}
