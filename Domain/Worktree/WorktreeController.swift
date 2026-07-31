import Foundation
import Combine

/// Observable Worktree list / create / focus / remove + focused session (Main Repo or Worktree).
///
/// Main CLI PTYs persist per session (show/hide on focus); tear down only on remove / Workspace switch.
@MainActor
final class WorktreeController: ObservableObject {
    private let store: WorktreeStore
    private let preferences: PreferencesController
    private let workspaces: WorkspaceController
    private let secrets: SecretStoreController?
    private var cancellables = Set<AnyCancellable>()
    /// Watches each Worktree's git `HEAD` (read-only) so sidebar branch labels update after checkout.
    private let branchWatcher = WorktreeBranchWatcher()

    /// Non-archived Worktrees under the current Workspace (P1.3: archived are hidden by default).
    @Published private(set) var worktrees: [WorktreeSummary] = []
    /// Bumped when any watched HEAD changes so sidebar re-queries Worktrees in non-current Workspaces.
    @Published private(set) var branchDiskGeneration: UInt64 = 0
    /// Main Repo or Worktree — drives which Main CLI surface is visible and Overlay scope.
    @Published private(set) var focusedSession: FocusedSession?
    /// Opened Main CLI surfaces (alive PTYs). Host mounts all; only focused is visible.
    @Published private(set) var openedMainCLISessions: [MainCLISurfaceSlot] = []
    /// Env snapshotted for the focused session (locale + secrets); used by chrome / respawn hints.
    @Published private(set) var focusedSpawnEnvironment: [(key: String, value: String)] = []
    @Published var lastError: String?

    /// Pending remove target for confirm UI (ADR 0020).
    @Published var pendingRemove: WorktreeSummary?

    /// When confirming remove, optionally also delete the branch (default keep).
    @Published var pendingRemoveDeleteBranch: Bool = false

    /// Pending rename target (branch primary, folder secondary — ADR 0018).
    @Published var pendingRename: WorktreeSummary?

    /// New Worktree sheet (sidebar + Command Center parity).
    @Published var pendingCreateWorktree = false

    /// Recent Main CLI process-exit timestamps per session id (crash-loop guard).
    private var recentMainCLIExitTimestamps: [String: [Date]] = [:]
    private let mainCLICrashLoopWindow: TimeInterval = 2
    private let mainCLICrashLoopThreshold = 3
    /// Disk list cache for non-current Workspaces (filled by `syncBranchWatchers`).
    private var worktreesByWorkspaceID: [String: [WorktreeSummary]] = [:]

    init(
        preferences: PreferencesController,
        workspaces: WorkspaceController,
        secrets: SecretStoreController? = nil,
        store: WorktreeStore = WorktreeStore()
    ) {
        self.preferences = preferences
        self.workspaces = workspaces
        self.secrets = secrets
        self.store = store

        workspaces.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // `receive(on:)` can still deliver inside SwiftUI's AttributeGraph
                // pass — nest another async hop so @Published writes land after.
                DispatchQueue.main.async { [weak self] in
                    self?.onWorkspaceChanged()
                }
            }
            .store(in: &cancellables)

        workspaces.$workspaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.syncBranchWatchers()
                }
            }
            .store(in: &cancellables)

        branchWatcher.onChange = { [weak self] in
            self?.onWatchedHEADChanged()
        }
    }

    /// Focused Worktree when session is a Worktree; nil for Main Repo.
    var focused: WorktreeSummary? {
        focusedSession?.worktree
    }

    /// Effective Main CLI command for the focused session's terminal spawn (empty = bare shell).
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

    /// Session ids whose Overlay PTYs should stay alive (current Workspace Main + Worktrees).
    var liveOverlaySessionIDs: Set<String> {
        var ids = Set(worktrees.map { FocusedSession.worktree($0).id })
        if let current = workspaces.current {
            ids.insert(FocusedSession.mainRepo(for: current).id)
        }
        return ids
    }

    func refresh() {
        guard let current = workspaces.current else {
            if !worktrees.isEmpty { worktrees = [] }
            branchWatcher.stopAll()
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
            worktrees = all.filter { !archived.contains($0.threeWordName) }
            lastError = nil
            reconcileFocusedSession(workspace: current)
            pruneOpenedSessionsToLiveSet()
            syncBranchWatchers()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Non-archived Worktrees under any Workspace Data Dir (sidebar expansion, Command Center).
    /// Never hits git for non-current workspaces during view evaluation — uses the cache
    /// filled by `syncBranchWatchers`.
    func worktrees(in workspace: WorkspaceSummary) -> [WorktreeSummary] {
        _ = branchDiskGeneration
        if workspace.id == workspaces.current?.id {
            return worktrees
        }
        let archived = workspaces.archivedWorktreeNames(for: workspace)
        return (worktreesByWorkspaceID[workspace.id] ?? []).filter {
            !archived.contains($0.threeWordName)
        }
    }

    /// All Worktrees under a Workspace **including archived** — folder still exists on disk.
    func allWorktrees(in workspace: WorkspaceSummary) -> [WorktreeSummary] {
        if let cached = worktreesByWorkspaceID[workspace.id] {
            return cached
        }
        return (try? store.list(workspaceDataDir: workspace.dataDirURL)) ?? []
    }

    /// Archived Worktrees for the “Archived Worktrees…” sheet (P1.3).
    func archivedWorktrees(in workspace: WorkspaceSummary) -> [WorktreeSummary] {
        let archived = workspaces.archivedWorktreeNames(for: workspace)
        guard !archived.isEmpty else { return [] }
        return allWorktrees(in: workspace).filter { archived.contains($0.threeWordName) }
    }

    /// Generate a fresh unique Three-Word folder name for the current Workspace (P1.4 prefill /
    /// regenerate). Falls back to an unscoped unique name when no Workspace is selected yet.
    func generateThreeWordName() -> String {
        let existing = workspaces.current.flatMap { try? store.existingFolderNames(workspaceDataDir: $0.dataDirURL) } ?? []
        return (try? ThreeWordName.generateUnique(existing: existing)) ?? ""
    }

    /// Create Worktree under the selected Workspace (P4.1–P4.4).
    ///
    /// `folder` is the on-disk Three-Word Name. Empty `branch` uses the folder name.
    func createWorktree(branch: String, folder: String) {
        guard let current = workspaces.current else {
            lastError = WorktreeStore.StoreError.noWorkspace.localizedDescription
            return
        }

        do {
            let manualName = folder.trimmingCharacters(in: .whitespacesAndNewlines)
            let threeWord: String
            if manualName.isEmpty {
                let existing = try store.existingFolderNames(workspaceDataDir: current.dataDirURL)
                threeWord = try ThreeWordName.generateUnique(existing: existing)
            } else {
                switch WorkspaceSlug.validate(manualName) {
                case .success(let validated):
                    threeWord = validated
                case .failure(let error):
                    lastError = error.localizedDescription
                    return
                }
            }
            let manualBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            let branchName = manualBranch.isEmpty ? threeWord : manualBranch
            let baseRef = preferences.effective.baseRef

            let summary = try store.create(
                workspaceDataDir: current.dataDirURL,
                threeWordName: threeWord,
                branchName: branchName,
                baseRef: baseRef
            )
            pendingCreateWorktree = false
            refresh()
            focus(summary)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Create Worktree

    /// Open the New Worktree sheet.
    func beginCreateWorktree() {
        lastError = nil
        pendingCreateWorktree = true
    }

    func cancelCreateWorktree() {
        if pendingCreateWorktree { pendingCreateWorktree = false }
        if lastError != nil { lastError = nil }
    }

    /// Focus Main Repo for the given Workspace (cwd = `<workspace>/main/`).
    func focusMain(for workspace: WorkspaceSummary) {
        applyFocus(.mainRepo(for: workspace), forceRespawn: false)
    }

    func focus(_ wt: WorktreeSummary) {
        applyFocus(.worktree(wt), forceRespawn: false)
    }

    /// Cycle Main + Worktrees by `delta` (±1), wrapping (ADR 0022). Requires a current Workspace.
    func cycleWorktree(delta: Int) {
        guard let current = workspaces.current else {
            lastError = "Select a Workspace first"
            return
        }
        // Order: Main, then Worktrees in list order.
        struct Slot {
            let isMain: Bool
            let worktree: WorktreeSummary?
        }
        var slots: [Slot] = [Slot(isMain: true, worktree: nil)]
        slots.append(contentsOf: worktrees.map { Slot(isMain: false, worktree: $0) })
        guard !slots.isEmpty else { return }

        let index: Int
        switch focusedSession {
        case .some(.mainRepo):
            index = 0
        case .some(.worktree(let wt)):
            index = slots.firstIndex(where: { $0.worktree?.id == wt.id }) ?? 0
        case .none:
            index = delta > 0 ? -1 : 0
        }

        let count = slots.count
        let next = ((index + delta) % count + count) % count
        let slot = slots[next]
        if slot.isMain {
            focusMain(for: current)
        } else if let wt = slot.worktree {
            focus(wt)
        }
        lastError = nil
    }

    /// Focus Main Repo and respawn its CLI with current secrets, locale, and cwd.
    func reloadMainCLI(for workspace: WorkspaceSummary) {
        applyFocus(.mainRepo(for: workspace), forceRespawn: true)
    }

    /// Focus a Worktree and respawn its CLI with current secrets, locale, and cwd.
    func reloadCLI(for wt: WorktreeSummary) {
        applyFocus(.worktree(wt), forceRespawn: true)
    }

    /// Re-apply current Enabled Secret Store + locale by restarting the focused session CLI only.
    func respawnWithCurrentSecrets() {
        guard let focusedSession else {
            lastError = "No focused session to reload"
            return
        }
        applyFocus(focusedSession, forceRespawn: true)
    }

    /// Ghostty reported the Main CLI PTY exited (`exit`, agent quit, …).
    /// Auto-reloads unless exits are looping; then marks the slot dead for Reload CLI.
    func handleMainCLIProcessExit(sessionId: String) {
        guard openedMainCLISessions.contains(where: { $0.id == sessionId }) else { return }

        let now = Date()
        var times = (recentMainCLIExitTimestamps[sessionId] ?? []).filter {
            now.timeIntervalSince($0) < mainCLICrashLoopWindow
        }
        times.append(now)
        recentMainCLIExitTimestamps[sessionId] = times

        if times.count >= mainCLICrashLoopThreshold {
            markMainCLIProcessExited(sessionId: sessionId)
            return
        }

        reloadOpenedMainCLI(sessionId: sessionId)
    }

    /// Respawn an opened Main CLI slot (Operator Reload after crash-loop, or auto-reload).
    func reloadOpenedMainCLI(sessionId: String) {
        recentMainCLIExitTimestamps[sessionId] = []
        guard let idx = openedMainCLISessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let existing = openedMainCLISessions[idx]
        let env = currentSpawnEnvironment()
        if focusedSession?.id == sessionId {
            focusedSpawnEnvironment = env
        }
        lastError = nil
        openedMainCLISessions[idx] = MainCLISurfaceSlot(
            id: existing.id,
            workingDirectory: existing.workingDirectory,
            command: existing.command,
            spawnEnvironment: env,
            generation: existing.generation + 1,
            processExited: false
        )
    }

    func clearFocus() {
        focusedSession = nil
        focusedSpawnEnvironment = []
    }

    /// Archive Worktree: soft flag only — folder + git worktree stay on disk (P1.3, ADR 0020
    /// spirit). Hides it from default lists; refocuses Main Repo if it was the focused session.
    /// Takes a `WorktreeSummary`, not a Workspace — Main can never be archived through this API
    /// (P1.5 protects Main structurally, not just via missing UI affordances).
    func archive(_ wt: WorktreeSummary) {
        guard let current = workspaces.current else { return }
        if focusedSession?.worktree?.id == wt.id {
            focusMain(for: current)
        }
        workspaces.setWorktreeArchived(wt.threeWordName, archived: true, in: current)
        refresh()
    }

    /// Unarchive a Worktree by folder name (from the “Archived Worktrees…” sheet).
    func unarchive(threeWordName: String, in workspace: WorkspaceSummary) {
        workspaces.setWorktreeArchived(threeWordName, archived: false, in: workspace)
        if workspace.id == workspaces.current?.id {
            refresh()
        }
    }

    /// Begin Remove Worktree confirm (ADR 0020). Takes a `WorktreeSummary`, not a Workspace — Main
    /// can never be removed through this API (P1.5 protects Main structurally).
    func requestRemove(_ wt: WorktreeSummary) {
        pendingRemoveDeleteBranch = false
        pendingRemove = wt
    }

    func cancelRemove() {
        if pendingRemove != nil { pendingRemove = nil }
        if pendingRemoveDeleteBranch { pendingRemoveDeleteBranch = false }
    }

    // MARK: - Rename Worktree

    func beginRename(_ wt: WorktreeSummary) {
        pendingRename = wt
        lastError = nil
    }

    func cancelRename() {
        if pendingRename != nil { pendingRename = nil }
    }

    /// Rename branch and/or folder; refresh list and re-focus when this Worktree was focused.
    func renameWorktree(branch: String, folder: String) {
        guard let current = workspaces.current,
              let wt = pendingRename
        else { return }

        let wasFocused = focusedSession?.worktree?.id == wt.id

        do {
            let updated = try store.rename(
                workspaceDataDir: current.dataDirURL,
                agent: wt,
                newBranchName: branch,
                newFolderName: folder
            )

            if updated.threeWordName != wt.threeWordName {
                workspaces.renameArchivedWorktreeName(
                    from: wt.threeWordName,
                    to: updated.threeWordName,
                    in: current
                )
            }

            if updated.worktreeURL != wt.worktreeURL {
                migrateOpenedSession(from: wt, to: updated)
            }

            pendingRename = nil
            refresh()
            if wasFocused {
                focus(updated)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Confirm Remove Worktree: unregister worktree + delete folder; keep branch unless opted in.
    func confirmRemove() {
        guard let current = workspaces.current,
              let wt = pendingRemove
        else {
            pendingRemove = nil
            return
        }

        let removedSessionID = FocusedSession.worktree(wt).id

        do {
            try store.remove(
                workspaceDataDir: current.dataDirURL,
                agent: wt,
                deleteBranch: pendingRemoveDeleteBranch
            )
            openedMainCLISessions.removeAll { $0.id == removedSessionID }
            if focusedSession?.worktree?.id == wt.id {
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
        let session = refreshedSession(for: session)
        focusedSession = session
        let env = currentSpawnEnvironment()
        focusedSpawnEnvironment = env
        let command = spawnCommandValue()
        lastError = nil

        if let idx = openedMainCLISessions.firstIndex(where: { $0.id == session.id }) {
            if forceRespawn {
                recentMainCLIExitTimestamps[session.id] = []
                let generation = openedMainCLISessions[idx].generation + 1
                openedMainCLISessions[idx] = MainCLISurfaceSlot(
                    id: session.id,
                    workingDirectory: session.workingDirectory,
                    command: command,
                    spawnEnvironment: env,
                    generation: generation,
                    processExited: false
                )
            }
            return
        }

        openedMainCLISessions.append(
            MainCLISurfaceSlot(
                id: session.id,
                workingDirectory: session.workingDirectory,
                command: command,
                spawnEnvironment: env,
                generation: 0,
                processExited: false
            )
        )
    }

    private func markMainCLIProcessExited(sessionId: String) {
        guard let idx = openedMainCLISessions.firstIndex(where: { $0.id == sessionId }) else { return }
        var slot = openedMainCLISessions[idx]
        slot.processExited = true
        openedMainCLISessions[idx] = slot
    }

    /// Resolve latest cwd / slug from live Workspace + Worktree state (rename, heal, refresh).
    private func refreshedSession(for session: FocusedSession) -> FocusedSession {
        switch session {
        case .mainRepo(let workspaceId, _, _):
            if let workspace = workspaces.workspaces.first(where: { $0.id == workspaceId })
                ?? (workspaces.current?.id == workspaceId ? workspaces.current : nil)
            {
                return .mainRepo(for: workspace)
            }
            return session
        case .worktree(let wt):
            if let updated = worktrees.first(where: { $0.id == wt.id })
                ?? worktrees.first(where: { $0.threeWordName == wt.threeWordName })
            {
                return .worktree(updated)
            }
            return session
        }
    }

    private func pruneOpenedSessionsToLiveSet() {
        let live = liveOverlaySessionIDs
        openedMainCLISessions.removeAll { !live.contains($0.id) }
        recentMainCLIExitTimestamps = recentMainCLIExitTimestamps.filter { live.contains($0.key) }
    }

    private func reconcileFocusedSession(workspace: WorkspaceSummary) {
        switch focusedSession {
        case .none:
            focusMain(for: workspace)
        case .mainRepo(let workspaceId, _, _)?:
            if workspaceId != workspace.id {
                focusMain(for: workspace)
            } else {
                let updated = FocusedSession.mainRepo(for: workspace)
                focusedSession = updated
                if !openedMainCLISessions.contains(where: { $0.id == updated.id }) {
                    applyFocus(updated, forceRespawn: false)
                }
            }
        case .worktree(let wt)?:
            if let updated = worktrees.first(where: { $0.worktreeURL == wt.worktreeURL })
                ?? worktrees.first(where: { $0.threeWordName == wt.threeWordName })
            {
                focusedSession = .worktree(updated)
                if updated.worktreeURL != wt.worktreeURL {
                    migrateOpenedSession(from: wt, to: updated)
                }
            } else {
                focusMain(for: workspace)
            }
        }
    }

    private func migrateOpenedSession(from old: WorktreeSummary, to updated: WorktreeSummary) {
        let oldID = FocusedSession.worktree(old).id
        let newID = FocusedSession.worktree(updated).id
        guard oldID != newID,
              let index = openedMainCLISessions.firstIndex(where: { $0.id == oldID })
        else { return }

        let slot = openedMainCLISessions[index]
        openedMainCLISessions[index] = MainCLISurfaceSlot(
            id: newID,
            workingDirectory: updated.worktreeURL.path,
            command: slot.command,
            spawnEnvironment: slot.spawnEnvironment,
            generation: slot.generation,
            processExited: slot.processExited
        )
        if let times = recentMainCLIExitTimestamps.removeValue(forKey: oldID) {
            recentMainCLIExitTimestamps[newID] = times
        }
    }

    private func onWorkspaceChanged() {
        if pendingRemove != nil { pendingRemove = nil }
        if pendingRemoveDeleteBranch { pendingRemoveDeleteBranch = false }
        if pendingRename != nil { pendingRename = nil }
        if pendingCreateWorktree { pendingCreateWorktree = false }
        if !openedMainCLISessions.isEmpty { openedMainCLISessions = [] }
        if !recentMainCLIExitTimestamps.isEmpty { recentMainCLIExitTimestamps = [:] }
        guard let current = workspaces.current else {
            if !worktrees.isEmpty { worktrees = [] }
            branchWatcher.stopAll()
            if focusedSession != nil {
                focusedSession = nil
                focusedSpawnEnvironment = []
            }
            return
        }
        refresh()
        focusMain(for: current)
    }

    /// Re-read branch names after a watched `HEAD` change (no repo writes — read-only).
    private func onWatchedHEADChanged() {
        refreshBranchLabels()
        branchDiskGeneration &+= 1
        syncBranchWatchers()
    }

    /// Patch `branchName` on current Worktrees + focused session without tearing down PTYs.
    private func refreshBranchLabels() {
        var changed = false
        let updated: [WorktreeSummary] = worktrees.map { wt in
            let branch = store.readCurrentBranch(at: wt.worktreeURL)
            if branch != wt.branchName {
                changed = true
                return WorktreeSummary(
                    threeWordName: wt.threeWordName,
                    worktreeURL: wt.worktreeURL,
                    branchName: branch
                )
            }
            return wt
        }
        guard changed else { return }
        worktrees = updated
        if case .worktree(let focused)? = focusedSession,
           let refreshed = updated.first(where: { $0.id == focused.id })
        {
            focusedSession = .worktree(refreshed)
        }
    }

    /// Watch HEAD for every known Worktree (current + others) so expanded sidebar rows stay live.
    private func syncBranchWatchers() {
        var checkouts: [URL] = []
        var cache: [String: [WorktreeSummary]] = [:]
        for workspace in workspaces.workspaces {
            let listed = (try? store.list(workspaceDataDir: workspace.dataDirURL)) ?? []
            cache[workspace.id] = listed
            checkouts.append(contentsOf: listed.map(\.worktreeURL))
        }
        let cacheChanged = cache != worktreesByWorkspaceID
        worktreesByWorkspaceID = cache
        branchWatcher.watch(checkouts: checkouts)
        // Sidebar reads non-current lists from cache — bump so expanded rows refresh.
        if cacheChanged {
            branchDiskGeneration &+= 1
        }
    }
}
