import Foundation
import Combine

/// Observable Workspace list / create / switch for chrome scaffolding (P3.6).
@MainActor
final class WorkspaceController: ObservableObject {
    private let store: WorkspaceStore
    private let preferences: PreferencesController

    @Published private(set) var workspaces: [WorkspaceSummary] = []
    @Published private(set) var current: WorkspaceSummary?
    @Published private(set) var currentConfig: WorkspaceConfig?
    @Published var lastError: String?

    /// Scaffold create fields.
    @Published var draftSlug: String = ""
    @Published var draftPrefix: String = ""
    /// Optional clone source for Main (P1.4). Empty → `git init` as before.
    @Published var draftCloneURL: String = ""

    /// Pending Workspace remove for confirm UI (deletes Data Dir + index entry).
    @Published var pendingRemoveWorkspace: WorkspaceSummary?

    /// Pending Workspace rename sheet target + draft slug.
    @Published var pendingRenameWorkspace: WorkspaceSummary?
    @Published var draftRenameSlug: String = ""

    init(
        preferences: PreferencesController,
        store: WorkspaceStore = WorkspaceStore()
    ) {
        self.preferences = preferences
        self.store = store
        refresh()
        restoreLastSelection()
    }

    /// Effective Workspaces Root from Global Setting (listing parent; Prefix overrides are per-Workspace).
    var workspacesRoot: String {
        preferences.preferences.workspacesRoot
    }

    /// Re-list Workspaces and, if one is selected, re-`open` it — which also heals `main/`
    /// (P1.5) when it went missing or stopped being a git repo. Cheap / idempotent when Main is
    /// already a valid git repo (heal only touches disk in the unhealthy case).
    func refresh() {
        do {
            workspaces = try store.list(workspacesRoot: workspacesRoot)
            lastError = nil
            if let current {
                do {
                    let opened = try store.open(at: current.dataDirURL)
                    self.current = opened
                    if let idx = workspaces.firstIndex(where: { $0.id == opened.id }) {
                        workspaces[idx] = opened
                    } else {
                        workspaces.append(opened)
                        workspaces.sort { $0.slug.localizedCaseInsensitiveCompare($1.slug) == .orderedAscending }
                    }
                } catch {
                    lastError = error.localizedDescription
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Create Workspace under optional Prefix (empty → Workspaces Root), then select it.
    /// When `draftCloneURL` is non-empty, Main is cloned from that URL instead of `git init`.
    func createWorkspace() {
        do {
            let summary = try store.create(
                slug: draftSlug,
                prefix: draftPrefix.isEmpty ? nil : draftPrefix,
                workspacesRoot: workspacesRoot,
                cloneURL: draftCloneURL.isEmpty ? nil : draftCloneURL
            )
            draftSlug = ""
            draftPrefix = ""
            draftCloneURL = ""
            refresh()
            select(summary)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Switch current Workspace; loads `config.toml` into Effective Setting overrides. Opening
    /// also heals `main/` (P1.5) via `WorkspaceStore.open(at:)` when it's missing or not a git repo.
    func select(_ summary: WorkspaceSummary) {
        do {
            let opened = try store.open(at: summary.dataDirURL)
            let config = try store.loadConfig(from: opened.dataDirURL)
            current = opened
            currentConfig = config
            preferences.workspaceOverrides = config.asOverrides
            try store.setLastSelectedSlug(opened.slug)
            lastError = nil
            objectWillChange.send()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Clear current Workspace selection (Effective Setting falls back to Global only).
    func clearSelection() {
        current = nil
        currentConfig = nil
        preferences.workspaceOverrides = .none
        try? store.setLastSelectedSlug(nil)
    }

    /// Persist chrome Workspace Setting edits into the selected Workspace’s `config.toml`.
    func saveCurrentWorkspaceSettings() {
        guard let current else { return }
        do {
            var config = try store.loadConfig(from: current.dataDirURL)
            config.apply(overrides: preferences.workspaceOverrides)
            config.slug = current.slug
            try store.writeConfig(config, to: current.dataDirURL)
            currentConfig = config
            // Refresh list so Prefix shown in rows matches config.
            refresh()
            if let updated = workspaces.first(where: { $0.id == current.id }) {
                self.current = updated
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Rename Workspace

    func beginRename(_ summary: WorkspaceSummary) {
        pendingRenameWorkspace = summary
        draftRenameSlug = summary.slug
        lastError = nil
    }

    func cancelRename() {
        pendingRenameWorkspace = nil
        draftRenameSlug = ""
    }

    /// Rename slug + move Workspace Data Dir; re-select when this was the current Workspace.
    func renameWorkspace() {
        guard let target = pendingRenameWorkspace else { return }
        let wasCurrent = current?.id == target.id
        do {
            let updated = try store.rename(
                summary: target,
                newSlug: draftRenameSlug,
                workspacesRoot: workspacesRoot
            )
            pendingRenameWorkspace = nil
            draftRenameSlug = ""
            refresh()
            if wasCurrent {
                select(updated)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Remove Workspace

    /// Ask chrome to confirm permanent removal of this Workspace (disk + index).
    func requestRemove(_ summary: WorkspaceSummary) {
        pendingRemoveWorkspace = summary
    }

    func cancelRemove() {
        pendingRemoveWorkspace = nil
    }

    /// Delete the Workspace Data Dir and unregister it. Clears selection if it was current
    /// so Main CLI / Overlay / Secret Store release that Workspace first.
    func confirmRemove() {
        guard let target = pendingRemoveWorkspace else { return }
        let wasCurrent = current?.id == target.id
        if wasCurrent {
            clearSelection()
        }
        do {
            try store.remove(target, workspacesRoot: workspacesRoot)
            pendingRemoveWorkspace = nil
            refresh()
            lastError = nil
        } catch {
            pendingRemoveWorkspace = nil
            lastError = error.localizedDescription
            refresh()
        }
    }

    // MARK: - Archive (P1.3)

    /// Three-Word names archived under `workspace` (soft flag in `config.toml`; ADR 0020 spirit).
    func archivedWorktreeNames(for workspace: WorkspaceSummary) -> Set<String> {
        let config = workspace.id == current?.id
            ? currentConfig
            : try? store.loadConfig(from: workspace.dataDirURL)
        return Set(config?.archivedThreeWordNames ?? [])
    }

    /// Flip the archived flag for one Worktree folder name; persists to `config.toml` only —
    /// never touches the Worktree folder or git registration.
    func setWorktreeArchived(_ threeWordName: String, archived: Bool, in workspace: WorkspaceSummary) {
        do {
            var config = try store.loadConfig(from: workspace.dataDirURL)
            var names = Set(config.archivedThreeWordNames ?? [])
            if archived {
                names.insert(threeWordName)
            } else {
                names.remove(threeWordName)
            }
            config.archivedThreeWordNames = names.sorted()
            try store.writeConfig(config, to: workspace.dataDirURL)
            if workspace.id == current?.id {
                currentConfig = config
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Heal Main (P1.5 / C.3)

    /// Repair `main/` when it is missing or not a git repo — re-clone from persisted remote or
    /// `git init`. No-op when Main is already healthy. Refreshes the Workspace list so
    /// `mainIsGitRepo` reflects disk. Returns whether disk was changed.
    @discardableResult
    func healMain(for summary: WorkspaceSummary) -> Bool {
        do {
            let config = try store.loadConfig(from: summary.dataDirURL)
            let healed = try store.healMainIfNeeded(at: summary.dataDirURL, config: config)
            refresh()
            lastError = nil
            return healed
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// When a Worktree folder is renamed, migrate its archived flag entry (if any).
    func renameArchivedWorktreeName(
        from oldName: String,
        to newName: String,
        in workspace: WorkspaceSummary
    ) {
        guard oldName != newName else { return }
        do {
            var config = try store.loadConfig(from: workspace.dataDirURL)
            guard var names = config.archivedThreeWordNames,
                  let index = names.firstIndex(of: oldName)
            else { return }
            names[index] = newName
            config.archivedThreeWordNames = names.sorted()
            try store.writeConfig(config, to: workspace.dataDirURL)
            if workspace.id == current?.id {
                currentConfig = config
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func restoreLastSelection() {
        guard let slug = store.lastSelectedSlug() else { return }
        if let match = workspaces.first(where: { $0.slug == slug }) {
            select(match)
        }
    }
}
