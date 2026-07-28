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
    @State private var renameWorkspaceSlug = ""
    @State private var renameWorktreeBranch = ""
    @State private var renameWorktreeFolder = ""

    var body: some View {
        VStack(spacing: 0) {
            // Clearance under traffic lights; drag strip (Xcode / Raycast).
            Color.clear
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .windowDragRegion()

            header
            SoftHairline(horizontalPadding: 12)
            workspaceList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ghosttyTheme.sidebar)
        .confirmationDialog(
            removeDialogTitle,
            isPresented: Binding(
                get: { worktrees.pendingRemove != nil },
                set: { if !$0 { worktrees.cancelRemove() } }
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
                set: { if !$0 { workspaces.cancelRemove() } }
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
            Text("Deletes the Workspace folder on disk (Main, Worktrees, secrets, config) and removes it from Symphonia’s index. This cannot be undone.")
        }
        .sheet(isPresented: Binding(
            get: { workspaces.pendingCreateWorkspace },
            set: { presented in
                if !presented { workspaces.cancelCreateWorkspace() }
            }
        )) {
            createWorkspaceSheet
        }
        .sheet(isPresented: Binding(
            get: { worktrees.pendingCreateWorktree },
            set: { presented in
                if !presented { worktrees.cancelCreateWorktree() }
            }
        )) {
            createWorktreeSheet
        }
        .sheet(item: $archivedSheetWorkspace) { workspace in
            archivedWorktreesSheet(workspace)
        }
        .sheet(item: $workspaces.pendingRenameWorkspace) { workspace in
            renameWorkspaceSheet(workspace)
        }
        .sheet(item: $worktrees.pendingRename) { agent in
            renameWorktreeSheet(agent)
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

    private var header: some View {
        HStack {
            Text("workspaces")
                .font(.headline)
                .foregroundStyle(ghosttyTheme.foreground)
            Spacer(minLength: 8)
                .windowDragRegion()
            Button {
                beginCreateWorkspace()
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(ghosttyTheme.accent)
            }
            .buttonStyle(.borderless)
            .help("Create Workspace")
            .accessibilityLabel("Create Workspace")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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

    private var workspaceList: some View {
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
                        .foregroundStyle(ghosttyTheme.accent)
                }
                .buttonStyle(.borderless)
                .help("New Worktree")
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

    private func archivedWorktreesSheet(_ workspace: WorkspaceSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Archived Worktrees")
                .font(.headline)
            Text(workspace.slug)
                .font(.caption)
                .foregroundStyle(.secondary)

            let archived = worktrees.archivedWorktrees(in: workspace)
            if archived.isEmpty {
                Text("No archived Worktrees. Folder + branch stay on disk when archived — this list is empty until you archive one from its context menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                List(archived) { agent in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.primaryLabel)
                            if let secondary = agent.secondaryLabel {
                                Text(secondary)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Button("Reveal") {
                            reveal(agent.worktreeURL)
                        }
                        Button("Unarchive") {
                            worktrees.unarchive(threeWordName: agent.threeWordName, in: workspace)
                        }
                    }
                }
                .frame(minHeight: 80, maxHeight: 220)
                .listStyle(.bordered)
            }

            HStack {
                Spacer()
                Button("Done") { archivedSheetWorkspace = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var createWorkspaceSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Workspace")
                .font(.headline)
            TextField("slug", text: $workspaces.draftSlug)
                .textFieldStyle(.roundedBorder)
            TextField("prefix (optional)", text: $workspaces.draftPrefix)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 4) {
                TextField("clone URL (optional)", text: $workspaces.draftCloneURL)
                    .textFieldStyle(.roundedBorder)
                Text("Leave empty to start an empty repo (`git init`). Set a URL to clone Main from it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { workspaces.cancelCreateWorkspace() }
                Button("Create") {
                    workspaces.createWorkspace()
                    if workspaces.lastError == nil {
                        if let current = workspaces.current {
                            expandedWorkspaceIDs.insert(current.id)
                            worktrees.focusMain(for: current)
                        }
                    }
                }
                .disabled(workspaces.draftSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            if let error = workspaces.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func renameWorkspaceSheet(_ workspace: WorkspaceSummary) -> some View {
        let trimmedSlug = renameWorkspaceSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        let previewDir = WorkspaceStore().dataDirURL(
            slug: trimmedSlug.isEmpty ? workspace.slug : trimmedSlug,
            prefix: workspace.prefix,
            workspacesRoot: workspaces.workspacesRoot
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text("Rename Workspace")
                .font(.headline)
            TextField("slug", text: $renameWorkspaceSlug)
                .textFieldStyle(.roundedBorder)
            Text("Folder will move to:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(previewDir.path)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .lineLimit(2)
            HStack {
                Spacer()
                Button("Cancel") {
                    workspaces.cancelRename()
                }
                Button("Rename") {
                    let oldExpandedID = workspace.id
                    workspaces.draftRenameSlug = renameWorkspaceSlug
                    workspaces.renameWorkspace()
                    if workspaces.lastError == nil {
                        expandedWorkspaceIDs.remove(oldExpandedID)
                        if let current = workspaces.current {
                            expandedWorkspaceIDs.insert(current.id)
                        }
                    }
                }
                .disabled(trimmedSlug.isEmpty || trimmedSlug == workspace.slug)
                .keyboardShortcut(.defaultAction)
            }
            if let error = workspaces.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            renameWorkspaceSlug = workspace.slug
            workspaces.lastError = nil
        }
    }

    private func renameWorktreeSheet(_ agent: WorktreeSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Worktree")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                TextField("branch name", text: $renameWorktreeBranch)
                    .textFieldStyle(.roundedBorder)
                Text("Git branch — the primary label in the sidebar.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField("folder name", text: $renameWorktreeFolder)
                    .textFieldStyle(.roundedBorder)
                Text("On-disk folder (Three-Word Name). Edit only when you want to move the checkout.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    worktrees.cancelRename()
                }
                Button("Rename") {
                    worktrees.draftRenameBranchName = renameWorktreeBranch
                    worktrees.draftRenameFolderName = renameWorktreeFolder
                    worktrees.renameWorktree()
                }
                .disabled(
                    renameWorktreeBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || renameWorktreeFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .keyboardShortcut(.defaultAction)
            }
            if let error = worktrees.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            renameWorktreeBranch = agent.branchName ?? agent.threeWordName
            renameWorktreeFolder = agent.threeWordName
            worktrees.lastError = nil
        }
    }

    private var createWorktreeSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Worktree")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                TextField("branch name", text: $worktrees.draftBranchName)
                    .textFieldStyle(.roundedBorder)
                Text("Git branch — the primary label in the sidebar. Empty → folder name below.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("folder name", text: $worktrees.draftThreeWordName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let name = worktrees.generateThreeWordName()
                        worktrees.draftThreeWordName = name
                        worktrees.draftBranchName = name
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Regenerate Three-Word Name")
                }
                Text("On-disk folder (Three-Word Name).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    worktrees.cancelCreateWorktree()
                }
                Button("Create") {
                    worktrees.createWorktree()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    workspaces.current == nil
                        || worktrees.draftThreeWordName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            if let error = worktrees.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 380)
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
