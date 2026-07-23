import AppKit
import SwiftUI

/// Collapsible left sidebar: Workspaces → Main Repo + Agents.
struct WorkspaceSidebarView: View {
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var agents: AgentController

    @State private var expandedWorkspaceIDs: Set<String> = []
    @State private var showCreateWorkspace = false
    @State private var createSlug = ""
    @State private var createPrefix = ""
    @State private var showCreateAgent = false
    @State private var createAgentBranch = ""

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
                createSlug = ""
                createPrefix = ""
                showCreateWorkspace = true
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
                createSlug = ""
                createPrefix = ""
                showCreateWorkspace = true
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
            Button("New Agent…") {
                selectWorkspace(workspace)
                createAgentBranch = ""
                showCreateAgent = true
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
                Image(systemName: "person")
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
            Button("Focus Agent") {
                selectWorkspace(workspace)
                agents.focus(agent)
            }
            Button("Reveal in Finder") {
                reveal(agent.worktreeURL)
            }
            Divider()
            Button("Remove Agent…", role: .destructive) {
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
        Button("New Agent…") {
            selectWorkspace(workspace)
            createAgentBranch = ""
            showCreateAgent = true
        }
        Button("Reveal in Finder") {
            reveal(workspace.dataDirURL)
        }
        Divider()
        Button("Create Workspace…") {
            createSlug = ""
            createPrefix = ""
            showCreateWorkspace = true
        }
    }

    private var createWorkspaceSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Workspace")
                .font(.headline)
            TextField("slug", text: $createSlug)
                .textFieldStyle(.roundedBorder)
            TextField("prefix (optional)", text: $createPrefix)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showCreateWorkspace = false }
                Button("Create") {
                    workspaces.draftSlug = createSlug
                    workspaces.draftPrefix = createPrefix
                    workspaces.createWorkspace()
                    showCreateWorkspace = false
                    if let current = workspaces.current {
                        expandedWorkspaceIDs.insert(current.id)
                        agents.focusMain(for: current)
                    }
                }
                .disabled(createSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var createAgentSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Agent")
                .font(.headline)
            Text("Optional branch name (empty → Three-Word folder name).")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("branch (optional)", text: $createAgentBranch)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showCreateAgent = false }
                Button("Create") {
                    agents.draftBranchName = createAgentBranch
                    agents.createAgent()
                    showCreateAgent = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(workspaces.current == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
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
            return "Remove Agent “\(name)”?"
        }
        return "Remove Agent?"
    }
}
