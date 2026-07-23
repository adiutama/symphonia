import Foundation
import Combine

/// Observable Agent list / create / focus / remove for chrome scaffolding (P4.7).
@MainActor
final class AgentController: ObservableObject {
    private let store: AgentStore
    private let preferences: PreferencesController
    private let workspaces: WorkspaceController
    private let secrets: SecretStoreController?
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var agents: [AgentSummary] = []
    @Published private(set) var focused: AgentSummary?
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

    /// Effective Main CLI command for the focused Agent’s terminal spawn (empty = bare shell).
    var focusedMainCLICommand: String {
        preferences.effective.mainCLICommand
    }

    /// Worktree cwd for Ghostty surface when an Agent is focused; nil otherwise.
    var focusedWorkingDirectory: String? {
        focused?.worktreeURL.path
    }

    /// Non-empty Main CLI command for surface `command`, or nil for Ghostty default shell.
    var focusedSpawnCommand: String? {
        let cmd = focusedMainCLICommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return cmd.isEmpty ? nil : cmd
    }

    func refresh() {
        guard let current = workspaces.current else {
            agents = []
            if focused != nil { focused = nil }
            focusedSpawnEnvironment = []
            return
        }

        do {
            agents = try store.list(workspaceDataDir: current.dataDirURL)
            lastError = nil
            if let focused,
               let updated = agents.first(where: { $0.id == focused.id })
            {
                self.focused = updated
            } else if let focused,
                      !agents.contains(where: { $0.id == focused.id })
            {
                self.focused = nil
                focusedSpawnEnvironment = []
            }
        } catch {
            lastError = error.localizedDescription
        }
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

    func focus(_ agent: AgentSummary) {
        focused = agent
        // Spawn-time inject: snapshot Enabled set now; live Secret Store edits do not rewrite this shell.
        focusedSpawnEnvironment = secrets?.enabledEnvironment ?? []
        lastError = nil
    }

    /// Re-apply current Enabled Secret Store set by restarting the focused Agent CLI (scaffold helper).
    func respawnWithCurrentSecrets() {
        guard let focused else { return }
        focus(focused)
    }

    func clearFocus() {
        focused = nil
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
            if focused?.id == agent.id {
                focused = nil
                focusedSpawnEnvironment = []
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

    private func onWorkspaceChanged() {
        focused = nil
        focusedSpawnEnvironment = []
        pendingRemove = nil
        pendingRemoveDeleteBranch = false
        draftBranchName = ""
        refresh()
    }
}
