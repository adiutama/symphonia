import Foundation
import Combine

/// Observable Agent list / create / focus / remove + focused session (Main Repo or Agent).
///
/// Main CLI PTYs persist per session (show/hide on focus); tear down only on remove / Workspace switch.
@MainActor
final class AgentController: ObservableObject {
    private let store: AgentStore
    private let preferences: PreferencesController
    private let workspaces: WorkspaceController
    private let secrets: SecretStoreController?
    private var cancellables = Set<AnyCancellable>()

    /// Non-archived Worktrees under the current Workspace (P1.3: archived are hidden by default).
    @Published private(set) var agents: [AgentSummary] = []
    /// Main Repo or Agent — drives which Main CLI surface is visible and Overlay scope.
    @Published private(set) var focusedSession: FocusedSession?
    /// Opened Main CLI surfaces (alive PTYs). Host mounts all; only focused is visible.
    @Published private(set) var openedMainCLISessions: [MainCLISurfaceSlot] = []
    /// Env snapshotted for the focused session (locale + secrets); used by chrome / respawn hints.
    @Published private(set) var focusedSpawnEnvironment: [(key: String, value: String)] = []
    @Published var lastError: String?

    /// Optional manual branch name on create; empty → Three-Word folder name (ADR 0018).
    @Published var draftBranchName: String = ""

    /// Editable folder/Three-Word Name on create (P1.4); empty → auto-generate at create time.
    /// The New Worktree sheet prefills this via `generateThreeWordName()` so Operator can accept
    /// or edit before creating.
    @Published var draftThreeWordName: String = ""

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
        spawnCommandValue()
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
                openedMainCLISessions = []
            }
            return
        }

        do {
            let all = try store.list(workspaceDataDir: current.dataDirURL)
            let archived = workspaces.archivedWorktreeNames(for: current)
            agents = all.filter { !archived.contains($0.threeWordName) }
            lastError = nil
            reconcileFocusedSession(workspace: current)
            pruneOpenedSessionsToLiveSet()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Non-archived Agents under any Workspace Data Dir (sidebar expansion, Command Center).
    func agents(in workspace: WorkspaceSummary) -> [AgentSummary] {
        if workspace.id == workspaces.current?.id {
            return agents
        }
        let archived = workspaces.archivedWorktreeNames(for: workspace)
        return allAgents(in: workspace).filter { !archived.contains($0.threeWordName) }
    }

    /// All Worktrees under a Workspace **including archived** — folder still exists on disk.
    func allAgents(in workspace: WorkspaceSummary) -> [AgentSummary] {
        (try? store.list(workspaceDataDir: workspace.dataDirURL)) ?? []
    }

    /// Archived Worktrees for the “Archived Worktrees…” sheet (P1.3).
    func archivedAgents(in workspace: WorkspaceSummary) -> [AgentSummary] {
        let archived = workspaces.archivedWorktreeNames(for: workspace)
        guard !archived.isEmpty else { return [] }
        return allAgents(in: workspace).filter { archived.contains($0.threeWordName) }
    }

    /// Generate a fresh unique Three-Word folder name for the current Workspace (P1.4 prefill /
    /// regenerate). Falls back to an unscoped unique name when no Workspace is selected yet.
    func generateThreeWordName() -> String {
        let existing = workspaces.current.flatMap { try? store.existingFolderNames(workspaceDataDir: $0.dataDirURL) } ?? []
        return (try? ThreeWordName.generateUnique(existing: existing)) ?? ""
    }

    /// Create Agent under the selected Workspace (P4.1–P4.4).
    ///
    /// Folder name comes from `draftThreeWordName` when non-empty (Operator-edited prefill from
    /// the New Worktree sheet, P1.4); otherwise a fresh unique Three-Word Name is generated.
    func createAgent() {
        guard let current = workspaces.current else {
            lastError = AgentStore.StoreError.noWorkspace.localizedDescription
            return
        }

        do {
            let manualName = draftThreeWordName.trimmingCharacters(in: .whitespacesAndNewlines)
            let threeWord: String
            if manualName.isEmpty {
                let existing = try store.existingFolderNames(workspaceDataDir: current.dataDirURL)
                threeWord = try ThreeWordName.generateUnique(existing: existing)
            } else {
                // Reuse Workspace Slug validation: folder name must be a single safe path
                // component (no traversal / separators) even when Operator-edited.
                switch WorkspaceSlug.validate(manualName) {
                case .success(let validated):
                    threeWord = validated
                case .failure(let error):
                    lastError = error.localizedDescription
                    return
                }
            }
            let manualBranch = draftBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
            let branch = manualBranch.isEmpty ? threeWord : manualBranch
            let baseRef = preferences.effective.baseRef

            let summary = try store.create(
                workspaceDataDir: current.dataDirURL,
                threeWordName: threeWord,
                branchName: branch,
                baseRef: baseRef
            )
            draftBranchName = ""
            draftThreeWordName = ""
            refresh()
            focus(summary)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Focus Main Repo for the given Workspace (cwd = `<workspace>/main/`).
    func focusMain(for workspace: WorkspaceSummary) {
        applyFocus(.mainRepo(for: workspace), forceRespawn: false)
    }

    func focus(_ agent: AgentSummary) {
        applyFocus(.agent(agent), forceRespawn: false)
    }

    /// Re-apply current Enabled Secret Store + locale by restarting the focused session CLI only.
    func respawnWithCurrentSecrets() {
        guard let focusedSession else { return }
        applyFocus(focusedSession, forceRespawn: true)
    }

    func clearFocus() {
        focusedSession = nil
        focusedSpawnEnvironment = []
    }

    /// Archive Worktree: soft flag only — folder + git worktree stay on disk (P1.3, ADR 0020
    /// spirit). Hides it from default lists; refocuses Main Repo if it was the focused session.
    /// Takes an `AgentSummary`, not a Workspace — Main can never be archived through this API
    /// (P1.5 protects Main structurally, not just via missing UI affordances).
    func archive(_ agent: AgentSummary) {
        guard let current = workspaces.current else { return }
        if focusedSession?.agent?.id == agent.id {
            focusMain(for: current)
        }
        workspaces.setWorktreeArchived(agent.threeWordName, archived: true, in: current)
        refresh()
    }

    /// Unarchive a Worktree by folder name (from the “Archived Worktrees…” sheet).
    func unarchive(threeWordName: String, in workspace: WorkspaceSummary) {
        workspaces.setWorktreeArchived(threeWordName, archived: false, in: workspace)
        if workspace.id == workspaces.current?.id {
            refresh()
        }
    }

    /// Begin Remove Agent confirm (ADR 0020). Takes an `AgentSummary`, not a Workspace — Main
    /// can never be removed through this API (P1.5 protects Main structurally).
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

        let removedSessionID = FocusedSession.agent(agent).id

        do {
            try store.remove(
                workspaceDataDir: current.dataDirURL,
                agent: agent,
                deleteBranch: pendingRemoveDeleteBranch
            )
            openedMainCLISessions.removeAll { $0.id == removedSessionID }
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

    private func spawnCommandValue() -> String? {
        let cmd = preferences.effective.mainCLICommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return cmd.isEmpty ? nil : cmd
    }

    private func currentSpawnEnvironment() -> [(key: String, value: String)] {
        CLISpawnEnvironment.mergingSecrets(secrets?.enabledEnvironment ?? [])
    }

    private func applyFocus(_ session: FocusedSession, forceRespawn: Bool) {
        focusedSession = session
        let env = currentSpawnEnvironment()
        focusedSpawnEnvironment = env
        lastError = nil

        if let idx = openedMainCLISessions.firstIndex(where: { $0.id == session.id }) {
            if forceRespawn {
                openedMainCLISessions[idx].spawnEnvironment = env
                openedMainCLISessions[idx].generation += 1
            }
            return
        }

        openedMainCLISessions.append(
            MainCLISurfaceSlot(
                id: session.id,
                workingDirectory: session.workingDirectory,
                command: spawnCommandValue(),
                spawnEnvironment: env,
                generation: 0
            )
        )
    }

    private func pruneOpenedSessionsToLiveSet() {
        let live = liveOverlaySessionIDs
        openedMainCLISessions.removeAll { !live.contains($0.id) }
    }

    private func reconcileFocusedSession(workspace: WorkspaceSummary) {
        switch focusedSession {
        case .none:
            focusMain(for: workspace)
        case .mainRepo(let workspaceId, _, _)?:
            if workspaceId != workspace.id {
                focusMain(for: workspace)
            } else {
                // Refresh main path / slug if Workspace moved; keep existing PTY if same id.
                let updated = FocusedSession.mainRepo(for: workspace)
                focusedSession = updated
                if !openedMainCLISessions.contains(where: { $0.id == updated.id }) {
                    applyFocus(updated, forceRespawn: false)
                }
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
        draftThreeWordName = ""
        // Drop Main CLI PTYs from the previous Workspace (cmux-style: sessions are per workspace).
        openedMainCLISessions = []
        guard let current = workspaces.current else {
            agents = []
            focusedSession = nil
            focusedSpawnEnvironment = []
            return
        }
        refresh()
        // Always land on Main Repo when switching Workspace (opens a fresh Main PTY for that workspace).
        focusMain(for: current)
    }
}
