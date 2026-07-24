import AppKit
import SwiftUI

/// Collapsible left sidebar: Workspaces → Main Repo + Worktrees.
struct WorkspaceSidebarView: View {
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var agents: AgentController

    @State private var expandedWorkspaceIDs: Set<String> = []
    @State private var showCreateWorkspace = false
    @State private var createSlug = ""
    @State private var createPrefix = ""
    @State private var createCloneURL = ""
    @State private var showCreateAgent = false
    @State private var createAgentBranch = ""
    @State private var createAgentThreeWordName = ""
    @State private var archivedSheetWorkspace: WorkspaceSummary?

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
        .sheet(isPresented: $showCreateWorkspace) {
            createWorkspaceSheet
        }
        .sheet(isPresented: $showCreateAgent) {
            createAgentSheet
        }
        .sheet(item: $archivedSheetWorkspace) { workspace in
            archivedWorktreesSheet(workspace)
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
            Text("Workspaces")
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
            Button("Create Workspace…") {
                beginCreateWorkspace()
            }
            Button("Refresh") {
                workspaces.refresh()
                agents.refresh()
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
                    }
                    .contextMenu {
                        workspaceContextMenu(workspace)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func workspaceLabel(_ workspace: WorkspaceSummary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(workspace.slug)
                .fontWeight(workspaces.current?.id == workspace.id ? .semibold : .regular)
            if workspaces.current?.id == workspace.id {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectWorkspace(workspace)
        }
    }

    /// Main row context menu deliberately has no Remove / Archive action — Main is protected
    /// (P1.5); only Focus / Reveal / New Worktree are offered here.
    private func mainRepoRow(_ workspace: WorkspaceSummary) -> some View {
        let isFocused = isMainFocused(workspace)
        return Button {
            selectWorkspace(workspace)
            agents.focusMain(for: workspace)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Main")
                        .fontWeight(isFocused ? .semibold : .regular)
                    Text(workspace.mainIsGitRepo ? "git repo" : "empty / not git")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isFocused ? Color.accentColor.opacity(0.18) : Color.clear)
        .contextMenu {
            Button("Focus Main Repo") {
                selectWorkspace(workspace)
                agents.focusMain(for: workspace)
            }
            Button("Reveal in Finder") {
                reveal(SymphoniaPaths.workspaceMainDirectory(in: workspace.dataDirURL))
            }
            Button("New Worktree…") {
                selectWorkspace(workspace)
                beginCreateAgent()
            }
        }
    }

    private func agentRow(_ agent: AgentSummary, workspace: WorkspaceSummary) -> some View {
        let isFocused = agents.focusedSession?.agent?.id == agent.id
            && workspaces.current?.id == workspace.id
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
                    Text(agent.primaryLabel)
                        .fontWeight(isFocused ? .semibold : .regular)
                        .lineLimit(1)
                    if let secondary = agent.secondaryLabel {
                        Text(secondary)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    } else if agent.branchName == nil || agent.branchName?.isEmpty == true {
                        Text(agent.threeWordName)
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
            Button("Focus Worktree") {
                selectWorkspace(workspace)
                agents.focus(agent)
            }
            Button("Reveal in Finder") {
                reveal(agent.worktreeURL)
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
        Button("Select Workspace") {
            selectWorkspace(workspace)
        }
        Button("Focus Main Repo") {
            selectWorkspace(workspace)
            agents.focusMain(for: workspace)
        }
        Button("New Worktree…") {
            selectWorkspace(workspace)
            beginCreateAgent()
        }
        Button("Reveal in Finder") {
            reveal(workspace.dataDirURL)
        }
        Divider()
        Button("Refresh") {
            workspaces.refresh()
            agents.refresh()
        }
        Button("Archived Worktrees…") {
            archivedSheetWorkspace = workspace
        }
        Divider()
        Button("Create Workspace…") {
            beginCreateWorkspace()
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

    private var removeDialogTitle: String {
        if let name = agents.pendingRemove?.primaryLabel {
            return "Remove Worktree “\(name)”?"
        }
        return "Remove Worktree?"
    }
}
