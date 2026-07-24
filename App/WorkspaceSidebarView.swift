import AppKit
import SwiftUI

/// Collapsible left sidebar: Workspaces → Main Repo + Worktrees.
struct WorkspaceSidebarView: View {
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var agents: AgentController
    @EnvironmentObject private var preferences: PreferencesController

    @State private var expandedWorkspaceIDs: Set<String> = []
    @State private var showCreateWorkspace = false
    @State private var createSlug = ""
    @State private var createPrefix = ""
    @State private var createCloneURL = ""
    @State private var showCreateAgent = false
    @State private var createAgentBranch = ""
    @State private var createAgentThreeWordName = ""
    @State private var archivedSheetWorkspace: WorkspaceSummary?
    @State private var renameWorkspaceSlug = ""
    @State private var renameAgentBranch = ""
    @State private var renameAgentFolder = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            workspaceList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .confirmationDialog(
            removeDialogTitle,
            isPresented: Binding(
                get: { agents.pendingRemove != nil },
                set: { if !$0 { agents.cancelRemove() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove worktree (keep branch)", role: .destructive) {
                agents.pendingRemoveDeleteBranch = false
                agents.confirmRemove()
            }
            Button("Remove worktree and delete branch", role: .destructive) {
                agents.pendingRemoveDeleteBranch = true
                agents.confirmRemove()
            }
            Button("Cancel", role: .cancel) {
                agents.cancelRemove()
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
        .sheet(isPresented: $showCreateWorkspace) {
            createWorkspaceSheet
        }
        .sheet(isPresented: $showCreateAgent) {
            createAgentSheet
        }
        .sheet(item: $archivedSheetWorkspace) { workspace in
            archivedWorktreesSheet(workspace)
        }
        .sheet(item: $workspaces.pendingRenameWorkspace) { workspace in
            renameWorkspaceSheet(workspace)
        }
        .sheet(item: $agents.pendingRename) { agent in
            renameAgentSheet(agent)
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
            Spacer()
            Button {
                beginCreateWorkspace()
            } label: {
                Image(systemName: "plus")
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
                agents.refresh()
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
                    .foregroundStyle(.secondary)
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
                        ForEach(agents.agents(in: workspace)) { agent in
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
    }

    private func workspaceLabel(_ workspace: WorkspaceSummary) -> some View {
        let isCurrent = workspaces.current?.id == workspace.id
        return HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(displayLowercased(workspace.slug))
                .fontWeight(isCurrent ? .semibold : .regular)
            if isCurrent {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Button {
                    selectWorkspace(workspace)
                    beginCreateAgent()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            agents.focusMain(for: workspace)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "house.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text("main")
                    .fontWeight(isFocused ? .semibold : .regular)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isFocused ? Color.accentColor.opacity(0.18) : Color.clear)
        .contextMenu {
            Button("New Worktree…") {
                selectWorkspace(workspace)
                beginCreateAgent()
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

    private func agentRow(_ agent: AgentSummary, workspace: WorkspaceSummary) -> some View {
        let isFocused = agents.focusedSession?.agent?.id == agent.id
            && workspaces.current?.id == workspace.id
        // Branch is the real worktree label; folder is secondary and only shown when it
        // actually differs from the branch (case-insensitive — same name, calm single line).
        let secondary = agent.primaryLabel.caseInsensitiveCompare(agent.threeWordName) == .orderedSame
            ? nil
            : agent.threeWordName
        return Button {
            selectWorkspace(workspace)
            agents.focus(agent)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayLowercased(agent.primaryLabel))
                        .fontWeight(isFocused ? .semibold : .regular)
                        .lineLimit(1)
                    if let secondary {
                        Text(displayLowercased(secondary))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isFocused ? Color.accentColor.opacity(0.18) : Color.clear)
        .contextMenu {
            Button("Rename Worktree…") {
                selectWorkspace(workspace)
                beginRenameAgent(agent)
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
                agents.archive(agent)
            }
            Button("Remove Worktree…", role: .destructive) {
                selectWorkspace(workspace)
                agents.requestRemove(agent)
            }
        }
    }

    @ViewBuilder
    private func workspaceContextMenu(_ workspace: WorkspaceSummary) -> some View {
        Button("New Worktree…") {
            selectWorkspace(workspace)
            beginCreateAgent()
        }
        Button("Rename Workspace…") {
            beginRenameWorkspace(workspace)
        }
        Divider()
        Button("Secrets…") {
            openSettings()
        }
        Button("Workspace Settings…") {
            openSettings()
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

            let archived = agents.archivedAgents(in: workspace)
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
                            agents.unarchive(threeWordName: agent.threeWordName, in: workspace)
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
            TextField("slug", text: $createSlug)
                .textFieldStyle(.roundedBorder)
            TextField("prefix (optional)", text: $createPrefix)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 4) {
                TextField("clone URL (optional)", text: $createCloneURL)
                    .textFieldStyle(.roundedBorder)
                Text("Leave empty to start an empty repo (`git init`). Set a URL to clone Main from it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { showCreateWorkspace = false }
                Button("Create") {
                    workspaces.draftSlug = createSlug
                    workspaces.draftPrefix = createPrefix
                    workspaces.draftCloneURL = createCloneURL
                    workspaces.createWorkspace()
                    if workspaces.lastError == nil {
                        showCreateWorkspace = false
                        if let current = workspaces.current {
                            expandedWorkspaceIDs.insert(current.id)
                            agents.focusMain(for: current)
                        }
                    }
                }
                .disabled(createSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func renameAgentSheet(_ agent: AgentSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Worktree")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                TextField("branch name", text: $renameAgentBranch)
                    .textFieldStyle(.roundedBorder)
                Text("Git branch — the primary label in the sidebar.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField("folder name", text: $renameAgentFolder)
                    .textFieldStyle(.roundedBorder)
                Text("On-disk folder (Three-Word Name). Edit only when you want to move the checkout.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    agents.cancelRename()
                }
                Button("Rename") {
                    agents.draftRenameBranchName = renameAgentBranch
                    agents.draftRenameFolderName = renameAgentFolder
                    agents.renameAgent()
                }
                .disabled(
                    renameAgentBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || renameAgentFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .keyboardShortcut(.defaultAction)
            }
            if let error = agents.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            renameAgentBranch = agent.branchName ?? agent.threeWordName
            renameAgentFolder = agent.threeWordName
            agents.lastError = nil
        }
    }

    private var createAgentSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Worktree")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("folder name", text: $createAgentThreeWordName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        createAgentThreeWordName = agents.generateThreeWordName()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Regenerate Three-Word Name")
                }
                Text("Three-Word folder name — edit or regenerate before creating.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            TextField("branch (optional)", text: $createAgentBranch)
                .textFieldStyle(.roundedBorder)
            Text("Optional branch name (empty → folder name above).")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { showCreateAgent = false }
                Button("Create") {
                    agents.draftThreeWordName = createAgentThreeWordName
                    agents.draftBranchName = createAgentBranch
                    agents.createAgent()
                    if agents.lastError == nil {
                        showCreateAgent = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    workspaces.current == nil
                        || createAgentThreeWordName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            if let error = agents.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func beginCreateWorkspace() {
        createSlug = ""
        createPrefix = ""
        createCloneURL = ""
        workspaces.lastError = nil
        showCreateWorkspace = true
    }

    private func beginCreateAgent() {
        createAgentBranch = ""
        createAgentThreeWordName = agents.generateThreeWordName()
        agents.lastError = nil
        showCreateAgent = true
    }

    private func beginRenameWorkspace(_ workspace: WorkspaceSummary) {
        renameWorkspaceSlug = workspace.slug
        workspaces.beginRename(workspace)
    }

    private func beginRenameAgent(_ agent: AgentSummary) {
        renameAgentBranch = agent.branchName ?? agent.threeWordName
        renameAgentFolder = agent.threeWordName
        agents.beginRename(agent)
    }

    private func selectWorkspace(_ workspace: WorkspaceSummary) {
        if workspaces.current?.id != workspace.id {
            workspaces.select(workspace)
        }
        expandedWorkspaceIDs.insert(workspace.id)
    }

    private func isMainFocused(_ workspace: WorkspaceSummary) -> Bool {
        guard workspaces.current?.id == workspace.id,
              let session = agents.focusedSession,
              case .mainRepo = session
        else { return false }
        return true
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
        agents.focusMain(for: workspace)
        agents.respawnWithCurrentSecrets()
    }

    private func reloadCLI(for agent: AgentSummary, in workspace: WorkspaceSummary) {
        selectWorkspace(workspace)
        agents.focus(agent)
        agents.respawnWithCurrentSecrets()
    }

    /// Re-clone Main from persisted remote when `main/` is missing or not a git repo (P1.5 heal).
    private func recloneMain(for workspace: WorkspaceSummary) {
        selectWorkspace(workspace)
        agents.focusMain(for: workspace)
        do {
            let store = WorkspaceStore()
            let config = try store.loadConfig(from: workspace.dataDirURL)
            _ = try store.healMainIfNeeded(at: workspace.dataDirURL, config: config)
            workspaces.refresh()
            agents.refresh()
        } catch {
            workspaces.lastError = error.localizedDescription
        }
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private var removeDialogTitle: String {
        if let name = agents.pendingRemove?.primaryLabel {
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
