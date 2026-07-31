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

    /// Pending Workspace remove for confirm UI (deletes Data Dir + index entry).
    @Published var pendingRemoveWorkspace: WorkspaceSummary?

    /// Inline New Project canvas (sidebar / Command Center / ⌘⇧N) — B2 create flow.
    @Published var pendingCreateWorkspace = false

    /// Read-only git clone/init terminal after layout is created; cleared when done or cancelled.
    @Published private(set) var createBootstrap: CreateBootstrapSession?

    /// Draft fields for the inline create canvas (shared with sidebar Untitled row).
    @Published var createDraftSource: CreateProjectSource = .remote
    @Published var createDraftName = ""
    @Published var createDraftPrefix = ""
    @Published var createDraftCloneURL = ""

    /// Pending Workspace rename sheet target.
    @Published var pendingRenameWorkspace: WorkspaceSummary?

    /// When Prefix relocate changes the Workspace Data Dir path, Settings remounts selection.
    @Published private(set) var lastWorkspaceIdRemap: WorkspaceIdRemap?

    private var pendingWorkspaceSettingsSave: DispatchWorkItem?

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

    /// Form canvas or bootstrap terminal is covering Main.
    var isCreateFlowActive: Bool {
        pendingCreateWorkspace || createBootstrap != nil
    }

    /// Sidebar label for the in-progress create draft (`Untitled` until a name is typed).
    var createDraftSidebarTitle: String {
        let trimmed = createDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// Commit the inline create draft: write layout without git, then show a read-only
    /// progress terminal. On success the host selects the Project and spawns Main CLI.
    func confirmCreateWorkspace() {
        let cloneURL = createDraftSource == .remote
            ? createDraftCloneURL.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        beginCreateBootstrap(
            slug: createDraftName,
            prefix: createDraftPrefix,
            cloneURL: cloneURL
        )
    }

    /// Create dirs + config (no git), then enter the read-only bootstrap terminal.
    func beginCreateBootstrap(slug: String, prefix: String = "", cloneURL: String = "") {
        do {
            let summary = try store.create(
                slug: slug,
                prefix: prefix.isEmpty ? nil : prefix,
                workspacesRoot: workspacesRoot,
                cloneURL: cloneURL.isEmpty ? nil : cloneURL,
                deferGit: true
            )
            let trimmedClone = cloneURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let session: CreateBootstrapSession
            if trimmedClone.isEmpty {
                session = CreateBootstrapSession(
                    summary: summary,
                    workingDirectory: summary.dataDirURL.path,
                    command: Self.initBootstrapCommand(),
                    kind: .initRepo
                )
            } else {
                session = CreateBootstrapSession(
                    summary: summary,
                    workingDirectory: summary.dataDirURL.path,
                    command: Self.cloneBootstrapCommand(remoteURL: trimmedClone),
                    kind: .clone
                )
            }
            resetCreateDraft()
            pendingCreateWorkspace = false
            createBootstrap = session
            refresh()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Open the inline New Project canvas. Keeps current selection so open Main CLIs stay alive;
    /// chrome treats the draft row as selected while pending.
    func beginCreateWorkspace() {
        if createBootstrap != nil {
            cancelCreateWorkspace()
        }
        lastError = nil
        resetCreateDraft()
        pendingCreateWorkspace = true
    }

    func cancelCreateWorkspace() {
        if let bootstrap = createBootstrap {
            createBootstrap = nil
            try? store.remove(bootstrap.summary, workspacesRoot: workspacesRoot)
            refresh()
        }
        if pendingCreateWorkspace { pendingCreateWorkspace = false }
        if lastError != nil { lastError = nil }
        resetCreateDraft()
    }

    /// Git finished successfully — pause for “press any key” before opening Main CLI.
    func markCreateBootstrapReady() {
        guard var session = createBootstrap else { return }
        session.awaitingContinue = true
        session.failed = false
        createBootstrap = session
        lastError = nil
    }

    /// Git finished successfully — select the new Project (heal is a no-op).
    func finishCreateBootstrap() {
        guard let bootstrap = createBootstrap else { return }
        let summary = bootstrap.summary
        createBootstrap = nil
        pendingCreateWorkspace = false
        resetCreateDraft()
        refresh()
        select(summary)
        lastError = nil
    }

    /// Git failed — keep the terminal scrollback; Operator can Retry or Cancel.
    func markCreateBootstrapFailed(exitCode: UInt32) {
        guard var session = createBootstrap else { return }
        session.failed = true
        session.awaitingContinue = false
        session.exitCode = exitCode
        createBootstrap = session
        lastError = "Setup failed (exit \(exitCode))"
    }

    /// Wipe `main/` and respawn the bootstrap terminal command.
    func retryCreateBootstrap() {
        guard var session = createBootstrap else { return }
        do {
            try store.resetMainDirectory(at: session.summary.dataDirURL)
            session.generation += 1
            session.failed = false
            session.awaitingContinue = false
            session.exitCode = nil
            createBootstrap = session
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// POSIX single-quoted string for `/bin/sh -c` (Ghostty runs surface commands in a shell).
    private static func shellSingleQuoted(_ value: String) -> String {
        GhosttySpawnCommand.shellSingleQuoted(value)
    }

    /// Ghostty on macOS wraps shell commands as `exec -l <command>`, so the first
    /// token must be a real binary — not a shell builtin like `set`.
    private static func wrapBootstrapScript(_ script: String) -> String {
        GhosttySpawnCommand.wrapScript(script)
    }

    /// Visible setup script: `mkdir` → `cd` → `git init`.
    private static func initBootstrapCommand() -> String {
        wrapBootstrapScript("""
        set -e
        echo "→ mkdir -p main"
        mkdir -p main
        echo "→ cd main"
        cd main
        echo "→ git init"
        git init
        echo "✓ Main ready"
        """)
    }

    /// Visible setup script: `mkdir` → `cd` → `git clone <url> .`
    private static func cloneBootstrapCommand(remoteURL: String) -> String {
        let url = shellSingleQuoted(remoteURL)
        return wrapBootstrapScript("""
        set -e
        echo "→ mkdir -p main"
        mkdir -p main
        echo "→ cd main"
        cd main
        echo "→ git clone \(url) ."
        git clone --progress \(url) .
        echo "✓ Main ready"
        """)
    }

    private func resetCreateDraft() {
        if createDraftSource != .remote { createDraftSource = .remote }
        if !createDraftName.isEmpty { createDraftName = "" }
        if !createDraftPrefix.isEmpty { createDraftPrefix = "" }
        if !createDraftCloneURL.isEmpty { createDraftCloneURL = "" }
    }

    /// Cycle current Workspace by `delta` (±1), wrapping. No-op if empty.
    func cycleWorkspace(delta: Int) {
        guard !workspaces.isEmpty else { return }
        let ids = workspaces.map(\.id)
        let index: Int
        if let currentId = current?.id, let i = ids.firstIndex(of: currentId) {
            index = i
        } else {
            index = delta > 0 ? -1 : 0
        }
        let count = ids.count
        let next = ((index + delta) % count + count) % count
        select(workspaces[next])
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
            if lastError != nil { lastError = nil }
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
    /// Relocates the Data Dir + session index when Prefix parent changes.
    func saveCurrentWorkspaceSettings() {
        guard let current else { return }
        saveWorkspaceSettings(for: current, overrides: preferences.workspaceOverrides)
    }

    /// Debounced persist of the selected Workspace’s `config.toml` only. Does not write Global prefs.
    func scheduleSaveCurrentWorkspaceSettings(after seconds: TimeInterval = 0.35) {
        guard let current else { return }
        scheduleSaveWorkspaceSettings(
            for: current,
            overrides: preferences.workspaceOverrides,
            after: seconds
        )
    }

    /// Load `config.toml` overrides for a Workspace without changing Main selection / Effective Setting.
    func loadSettingsOverrides(for summary: WorkspaceSummary) -> WorkspaceSettingOverrides? {
        do {
            let config = try store.loadConfig(from: summary.dataDirURL)
            lastError = nil
            return config.asOverrides
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Persist Settings for a Workspace without requiring it to be Main’s current selection.
    /// When the target is current, keeps Effective Setting overrides in sync.
    @discardableResult
    func saveWorkspaceSettings(
        for summary: WorkspaceSummary,
        overrides: WorkspaceSettingOverrides
    ) -> WorkspaceSummary? {
        let oldId = summary.id
        do {
            let updated = try store.persistSettings(
                summary: summary,
                overrides: overrides,
                workspacesRoot: workspacesRoot
            )
            lastError = nil
            refresh()
            if updated.id != oldId {
                lastWorkspaceIdRemap = WorkspaceIdRemap(from: oldId, to: updated.id)
            }
            if current?.id == oldId || current?.id == updated.id {
                if updated.id != oldId {
                    select(updated)
                } else if let refreshed = workspaces.first(where: { $0.id == updated.id }) {
                    self.current = refreshed
                    preferences.workspaceOverrides = overrides
                    if let config = try? store.loadConfig(from: refreshed.dataDirURL) {
                        currentConfig = config
                    }
                } else {
                    select(updated)
                }
            }
            return updated
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Debounced persist for a specific Workspace’s Settings (Settings UI may edit non-current).
    func scheduleSaveWorkspaceSettings(
        for summary: WorkspaceSummary,
        overrides: WorkspaceSettingOverrides,
        after seconds: TimeInterval = 0.35
    ) {
        pendingWorkspaceSettingsSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveWorkspaceSettings(for: summary, overrides: overrides)
        }
        pendingWorkspaceSettingsSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Rename Workspace

    func beginRename(_ summary: WorkspaceSummary) {
        pendingRenameWorkspace = summary
        lastError = nil
    }

    func cancelRename() {
        pendingRenameWorkspace = nil
    }

    /// Rename slug + move Workspace Data Dir; re-select when this was the current Workspace.
    func renameWorkspace(newSlug: String) {
        guard let target = pendingRenameWorkspace else { return }
        let wasCurrent = current?.id == target.id
        do {
            let updated = try store.rename(
                summary: target,
                newSlug: newSlug,
                workspacesRoot: workspacesRoot
            )
            pendingRenameWorkspace = nil
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
        if pendingRemoveWorkspace != nil { pendingRemoveWorkspace = nil }
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

/// Published when Prefix relocate changes a Workspace’s Data Dir path (`id`).
struct WorkspaceIdRemap: Equatable, Sendable {
    let from: String
    let to: String
}

/// Source toggle for the inline New Project canvas (B2).
enum CreateProjectSource: String, Equatable, Sendable {
    case remote
    case local
}

/// One-shot read-only terminal that runs `git clone` / `git init` during New Project.
struct CreateBootstrapSession: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case clone
        case initRepo
    }

    let id: UUID
    let summary: WorkspaceSummary
    let workingDirectory: String
    let command: String
    let kind: Kind
    /// Bumped on Retry so SwiftUI remounts `TerminalSurfaceView`.
    var generation: Int
    var failed: Bool
    /// Git succeeded — waiting for any key before opening Main CLI.
    var awaitingContinue: Bool
    var exitCode: UInt32?

    init(
        id: UUID = UUID(),
        summary: WorkspaceSummary,
        workingDirectory: String,
        command: String,
        kind: Kind,
        generation: Int = 0,
        failed: Bool = false,
        awaitingContinue: Bool = false,
        exitCode: UInt32? = nil
    ) {
        self.id = id
        self.summary = summary
        self.workingDirectory = workingDirectory
        self.command = command
        self.kind = kind
        self.generation = generation
        self.failed = failed
        self.awaitingContinue = awaitingContinue
        self.exitCode = exitCode
    }

    var viewIdentity: String { "\(id.uuidString)-\(generation)" }

    var title: String {
        if awaitingContinue { return "Ready" }
        switch kind {
        case .clone: return "Cloning…"
        case .initRepo: return "Initializing…"
        }
    }
}
