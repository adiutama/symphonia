import AppKit
import SwiftUI

/// Collapsible left sidebar: Workspaces → Main Repo + Worktrees.
struct WorkspaceSidebarView: View {
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var worktrees: WorktreeController
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var settingsNavigation: SettingsNavigation
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    @State private var expandedWorkspaceIDs: Set<String> = []
    @State private var archivedSheetWorkspace: WorkspaceSummary?
    @State private var createWorkspaceSlug = ""
    @State private var createWorkspacePrefix = ""
    @State private var createWorkspaceCloneURL = ""
    @State private var createWorktreeBranch = ""
    @State private var createWorktreeFolder = ""
    @State private var renameWorkspaceSlug = ""
    @State private var renameWorktreeBranch = ""
    @State private var renameWorktreeFolder = ""

    /// Clearance under traffic lights / unified titlebar (matches settings sidebar).
    private let titlebarBandHeight: CGFloat = 52
    /// Match standard traffic-light leading inset from the window edge.
    private let titlebarEdgeInset: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            sidebarTitlebarBand
            projectList
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Glass / solid fills under the transparent titlebar; list content stays below the band.
            .background {
                sidebarChrome
                    .ignoresSafeArea(.container, edges: .top)
            }
            .ignoresSafeArea(.container, edges: .top)
            .confirmationDialog(
                removeDialogTitle,
                isPresented: Binding(
                    get: { worktrees.pendingRemove != nil },
                    set: { presented in
                        // Only cancel on real dismiss — SwiftUI may write `false` while reconciling.
                        if !presented, worktrees.pendingRemove != nil {
                            worktrees.cancelRemove()
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
            Button("Remove worktree (keep branch)", role: .destructive) {
                worktrees.pendingRemoveDeleteBranch = false
                worktrees.confirmRemove()
            }
            Button("Remove worktree and delete branch", role: .destructive) {
                worktrees.pendingRemoveDeleteBranch = true
                worktrees.confirmRemove()
            }
            Button("Cancel", role: .cancel) {
                worktrees.cancelRemove()
            }
        } message: {
            Text("Default keeps the git branch. Folder + worktree registration are removed.")
        }
        .confirmationDialog(
            removeWorkspaceDialogTitle,
            isPresented: Binding(
                get: { workspaces.pendingRemoveWorkspace != nil },
                set: { presented in
                    if !presented, workspaces.pendingRemoveWorkspace != nil {
                        workspaces.cancelRemove()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Workspace permanently", role: .destructive) {
                workspaces.confirmRemove()
            }
            Button("Cancel", role: .cancel) {
                workspaces.cancelRemove()
            }
        } message: {
            Text("Deletes the Workspace Data Dir on disk (Main, Worktrees, secrets, config) and removes it from Symphonia’s index. This cannot be undone.")
        }
        .sheet(isPresented: Binding(
            get: { workspaces.pendingCreateWorkspace },
            set: { presented in
                if !presented { workspaces.cancelCreateWorkspace() }
            }
        )) {
            WorkspaceSidebarSheets.CreateWorkspace(
                slug: $createWorkspaceSlug,
                prefix: $createWorkspacePrefix,
                cloneURL: $createWorkspaceCloneURL,
                onCreated: { expandedWorkspaceIDs.insert($0.id) }
            )
        }
        .sheet(isPresented: Binding(
            get: { worktrees.pendingCreateWorktree },
            set: { presented in
                if !presented, worktrees.pendingCreateWorktree {
                    worktrees.cancelCreateWorktree()
                }
            }
        )) {
            WorkspaceSidebarSheets.CreateWorktree(
                branch: $createWorktreeBranch,
                folder: $createWorktreeFolder
            )
        }
        .sheet(item: $archivedSheetWorkspace) { workspace in
            WorkspaceSidebarSheets.ArchivedWorktrees(
                workspace: workspace,
                presentedWorkspace: $archivedSheetWorkspace
            )
        }
        .sheet(item: Binding(
            get: { workspaces.pendingRenameWorkspace },
            set: { newValue in
                guard workspaces.pendingRenameWorkspace != nil || newValue != nil else { return }
                if newValue == nil {
                    workspaces.pendingRenameWorkspace = nil
                } else {
                    workspaces.pendingRenameWorkspace = newValue
                }
            }
        )) { workspace in
            WorkspaceSidebarSheets.RenameWorkspace(
                workspace: workspace,
                slug: $renameWorkspaceSlug,
                onRenamed: { oldID, current in
                    expandedWorkspaceIDs.remove(oldID)
                    if let current {
                        expandedWorkspaceIDs.insert(current.id)
                    }
                }
            )
        }
        .sheet(item: Binding(
            get: { worktrees.pendingRename },
            set: { newValue in
                guard worktrees.pendingRename != nil || newValue != nil else { return }
                if newValue == nil {
                    worktrees.cancelRename()
                } else {
                    worktrees.pendingRename = newValue
                }
            }
        )) { agent in
            WorkspaceSidebarSheets.RenameWorktree(
                agent: agent,
                branch: $renameWorktreeBranch,
                folder: $renameWorktreeFolder
            )
        }
        .onAppear {
            if let current = workspaces.current {
                expandedWorkspaceIDs.insert(current.id)
            }
        }
        .onChange(of: workspaces.current?.id) { _, newID in
            if let newID {
                expandedWorkspaceIDs.insert(newID)
            }
        }
    }

    /// Titlebar strip over the sidebar: drag region + New Workspace pinned to the trailing edge
    /// so it tracks sidebar resize (not a window-toolbar item next to the traffic lights).
    private var sidebarTitlebarBand: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity)
                .windowDragRegion()

            Button {
                beginCreateWorkspace()
            } label: {
                Image(systemName: "folder.badge.plus")
                    .foregroundStyle(ghosttyTheme.foreground)
            }
            .buttonStyle(.borderless)
            .help("New Workspace")
            .padding(.trailing, titlebarEdgeInset)
        }
        .frame(height: titlebarBandHeight)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var sidebarChrome: some View {
        if preferences.preferences.chromeGlass {
            ChromeGlassBackground(
                tintColor: NSColor(ghosttyTheme.sidebar).withAlphaComponent(0.55)
            )
        } else {
            ghosttyTheme.sidebar
        }
    }

    private var projectList: some View {
        List {
            if workspaces.workspaces.isEmpty {
                Text("No Workspaces yet")
                    .foregroundStyle(ghosttyTheme.secondaryText)
                    .font(.caption)
            } else {
                ForEach(workspaces.workspaces) { workspace in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedWorkspaceIDs.contains(workspace.id) },
                            set: { expanded in
                                if expanded {
                                    expandedWorkspaceIDs.insert(workspace.id)
                                } else {
                                    expandedWorkspaceIDs.remove(workspace.id)
                                }
                            }
                        )
                    ) {
                        mainRepoRow(workspace)
                        ForEach(worktrees.worktrees(in: workspace)) { agent in
                            agentRow(agent, workspace: workspace)
                        }
                    } label: {
                        workspaceLabel(workspace)
                            .contextMenu {
                                workspaceContextMenu(workspace)
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .contextMenu {
            Button("New Workspace…") {
                beginCreateWorkspace()
            }
            Button("Refresh") {
                workspaces.refresh()
                worktrees.refresh()
            }
            Button("Reveal Workspaces Root") {
                reveal(preferences.effective.workspacesRootURL)
            }
        }
    }

    private func workspaceLabel(_ workspace: WorkspaceSummary) -> some View {
        let isCurrent = workspaces.current?.id == workspace.id
        return HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(ghosttyTheme.secondaryText)
                .font(.caption)
            Text(displayLowercased(workspace.slug))
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(ghosttyTheme.foreground)
            if isCurrent {
                Circle()
                    .fill(ghosttyTheme.accent)
                    .frame(width: 6, height: 6)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Button {
                    selectWorkspace(workspace)
                    beginCreateWorktree()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(
                            worktrees.canCreateWorktree(in: workspace)
                                ? ghosttyTheme.accent
                                : ghosttyTheme.secondaryText.opacity(0.45)
                        )
                }
                .buttonStyle(.borderless)
                .help(
                    worktrees.canCreateWorktree(in: workspace)
                        ? "New Worktree"
                        : "Main has no commits yet — click for details"
                )
                .accessibilityLabel("New Worktree")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectWorkspace(workspace)
        }
    }

    /// Main row context menu deliberately has no Remove / Archive action — Main is protected
    /// (P1.5); only New Worktree / Reveal are offered here (Focus is a click, not a menu item).
    private func mainRepoRow(_ workspace: WorkspaceSummary) -> some View {
        let isFocused = isMainFocused(workspace)
        return Button {
            selectWorkspace(workspace)
            worktrees.focusMain(for: workspace)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "house.fill")
                    .font(.caption)
                    .foregroundStyle(ghosttyTheme.secondaryText)
                    .frame(width: 14)
                Text("main")
                    .fontWeight(isFocused ? .semibold : .regular)
                    .foregroundStyle(ghosttyTheme.foreground)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isFocused ? ghosttyTheme.selectionFill : Color.clear)
        .contextMenu {
            Button("New Worktree…") {
                selectWorkspace(workspace)
                beginCreateWorktree()
            }
            Divider()
            Button("Reveal in Finder") {
                reveal(SymphoniaPaths.workspaceMainDirectory(in: workspace.dataDirURL))
            }
            Button("Reload Main CLI") {
                reloadMainCLI(for: workspace)
            }
            if hasMainRemoteURL(workspace) {
                if workspace.mainIsGitRepo {
                    Button("Re-clone Main…") {}
                        .disabled(true)
                        .help("Coming in Main CLI pass — heal on open already covers a missing main/")
                } else {
                    Button("Re-clone Main…") {
                        recloneMain(for: workspace)
                    }
                }
            }
        }
    }

    private func agentRow(_ agent: WorktreeSummary, workspace: WorkspaceSummary) -> some View {
        let isFocused = worktrees.focusedSession?.worktree?.id == agent.id
            && workspaces.current?.id == workspace.id
        // Branch is the real worktree label; folder is secondary and only shown when it
        // actually differs from the branch (case-insensitive — same name, calm single line).
        let secondary = agent.primaryLabel.caseInsensitiveCompare(agent.threeWordName) == .orderedSame
            ? nil
            : agent.threeWordName
        return Button {
            selectWorkspace(workspace)
            worktrees.focus(agent)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(ghosttyTheme.secondaryText)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayLowercased(agent.primaryLabel))
                        .fontWeight(isFocused ? .semibold : .regular)
                        .foregroundStyle(ghosttyTheme.foreground)
                        .lineLimit(1)
                    if let secondary {
                        Text(displayLowercased(secondary))
                            .font(.caption2)
                            .foregroundStyle(ghosttyTheme.tertiaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isFocused ? ghosttyTheme.selectionFill : Color.clear)
        .contextMenu {
            Button("Rename Worktree…") {
                selectWorkspace(workspace)
                beginRenameWorktree(agent)
            }
            Divider()
            Button("Reveal in Finder") {
                reveal(agent.worktreeURL)
            }
            Button("Copy Path") {
                copyToPasteboard(agent.worktreeURL.path)
            }
            Button("Copy Branch Name") {
                copyToPasteboard(agent.branchName ?? agent.threeWordName)
            }
            Divider()
            Button("Reload CLI") {
                reloadCLI(for: agent, in: workspace)
            }
            Divider()
            Button("Archive Worktree") {
                selectWorkspace(workspace)
                worktrees.archive(agent)
            }
            Button("Remove Worktree…", role: .destructive) {
                selectWorkspace(workspace)
                worktrees.requestRemove(agent)
            }
        }
    }

    @ViewBuilder
    private func workspaceContextMenu(_ workspace: WorkspaceSummary) -> some View {
        Button("New Worktree…") {
            selectWorkspace(workspace)
            beginCreateWorktree()
        }
        Button("Rename Workspace…") {
            beginRenameWorkspace(workspace)
        }
        Divider()
        Button("Secrets…") {
            settingsNavigation.open(.workspaceSecrets(workspaceId: workspace.id))
        }
        Button("Workspace Settings…") {
            settingsNavigation.open(.workspaceSettings(workspaceId: workspace.id))
        }
        Divider()
        Button("Reveal in Finder") {
            reveal(workspace.dataDirURL)
        }
        Button("Reveal Main in Finder") {
            reveal(SymphoniaPaths.workspaceMainDirectory(in: workspace.dataDirURL))
        }
        Button("Reload Main CLI") {
            reloadMainCLI(for: workspace)
        }
        if hasMainRemoteURL(workspace) {
            if workspace.mainIsGitRepo {
                Button("Re-clone Main…") {}
                    .disabled(true)
                    .help("Coming in Main CLI pass — heal on open already covers a missing main/")
            } else {
                Button("Re-clone Main…") {
                    recloneMain(for: workspace)
                }
            }
        }
        Divider()
        Button("Archived Worktrees…") {
            archivedSheetWorkspace = workspace
        }
        Divider()
        Button("Remove Workspace…", role: .destructive) {
            workspaces.requestRemove(workspace)
        }
    }

    private func beginCreateWorkspace() {
        workspaces.beginCreateWorkspace()
    }

    private func beginCreateWorktree() {
        worktrees.beginCreateWorktree()
    }

    private func beginRenameWorkspace(_ workspace: WorkspaceSummary) {
        renameWorkspaceSlug = workspace.slug
        workspaces.beginRename(workspace)
    }

    private func beginRenameWorktree(_ agent: WorktreeSummary) {
        renameWorktreeBranch = agent.branchName ?? agent.threeWordName
        renameWorktreeFolder = agent.threeWordName
        worktrees.beginRename(agent)
    }

    private func selectWorkspace(_ workspace: WorkspaceSummary) {
        if workspaces.current?.id != workspace.id {
            workspaces.select(workspace)
        }
        expandedWorkspaceIDs.insert(workspace.id)
    }

    private func isMainFocused(_ workspace: WorkspaceSummary) -> Bool {
        guard workspaces.current?.id == workspace.id,
              let session = worktrees.focusedSession,
              case .mainRepo = session
        else { return false }
        return true
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func workspaceConfig(for workspace: WorkspaceSummary) -> WorkspaceConfig? {
        if workspace.id == workspaces.current?.id {
            return workspaces.currentConfig
        }
        return try? WorkspaceStore().loadConfig(from: workspace.dataDirURL)
    }

    private func hasMainRemoteURL(_ workspace: WorkspaceSummary) -> Bool {
        let remote = workspaceConfig(for: workspace)?.mainRemoteURL?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !remote.isEmpty
    }

    private func reloadMainCLI(for workspace: WorkspaceSummary) {
        selectWorkspace(workspace)
        let target = workspaces.workspaces.first(where: { $0.id == workspace.id }) ?? workspace
        worktrees.reloadMainCLI(for: target)
    }

    private func reloadCLI(for agent: WorktreeSummary, in workspace: WorkspaceSummary) {
        selectWorkspace(workspace)
        let target = worktrees.worktrees(in: workspace).first(where: { $0.id == agent.id }) ?? agent
        worktrees.reloadCLI(for: target)
    }

    /// Re-clone Main from persisted remote when `main/` is missing or not a git repo (P1.5 heal).
    private func recloneMain(for workspace: WorkspaceSummary) {
        selectWorkspace(workspace)
        workspaces.healMain(for: workspace)
        guard workspaces.lastError == nil else { return }
        worktrees.refresh()
        let target = workspaces.workspaces.first(where: { $0.id == workspace.id }) ?? workspace
        worktrees.reloadMainCLI(for: target)
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private var removeDialogTitle: String {
        if let name = worktrees.pendingRemove?.primaryLabel {
            return "Remove Worktree “\(name)”?"
        }
        return "Remove Worktree?"
    }

    private var removeWorkspaceDialogTitle: String {
        if let slug = workspaces.pendingRemoveWorkspace?.slug {
            return "Remove Workspace “\(slug)”?"
        }
        return "Remove Workspace?"
    }
}
