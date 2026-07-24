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

    func refresh() {
        do {
            workspaces = try store.list(workspacesRoot: workspacesRoot)
            lastError = nil
            if let current,
               let updated = workspaces.first(where: { $0.id == current.id })
            {
                self.current = updated
            } else if let current,
                      !workspaces.contains(where: { $0.id == current.id })
            {
                // Current path vanished from list — keep selection if dir still valid.
                if let reopened = try? store.open(at: current.dataDirURL) {
                    self.current = reopened
                    if !workspaces.contains(where: { $0.id == reopened.id }) {
                        workspaces.append(reopened)
                        workspaces.sort { $0.slug.localizedCaseInsensitiveCompare($1.slug) == .orderedAscending }
                    }
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

    /// Switch current Workspace; loads `config.json` into Effective Setting overrides.
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

    /// Persist chrome Workspace Setting edits into the selected Workspace’s `config.json`.
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

    // MARK: - Archive (P1.3)

    /// Three-Word names archived under `workspace` (soft flag in `config.json`; ADR 0020 spirit).
    func archivedWorktreeNames(for workspace: WorkspaceSummary) -> Set<String> {
        let config = workspace.id == current?.id
            ? currentConfig
            : try? store.loadConfig(from: workspace.dataDirURL)
        return Set(config?.archivedThreeWordNames ?? [])
    }

    /// Flip the archived flag for one Worktree folder name; persists to `config.json` only —
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

    private func restoreLastSelection() {
        guard let slug = store.lastSelectedSlug() else { return }
        if let match = workspaces.first(where: { $0.slug == slug }) {
            select(match)
        }
    }
}
