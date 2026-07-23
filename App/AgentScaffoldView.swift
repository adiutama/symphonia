import SwiftUI

/// Minimal list / create / focus / remove scaffold for Agents (P4.7). Ugly on purpose.
struct AgentScaffoldView: View {
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var agents: AgentController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agents")
                .font(.headline)

            if workspaces.current == nil {
                Text("Select a Workspace to manage Agents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if agents.agents.isEmpty {
                Text("None yet — create one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(selection: Binding(
                    get: { agents.focused?.id },
                    set: { newID in
                        guard let newID,
                              let summary = agents.agents.first(where: { $0.id == newID })
                        else { return }
                        agents.focus(summary)
                    }
                )) {
                    ForEach(agents.agents) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.threeWordName)
                                    .fontWeight(agents.focused?.id == item.id ? .bold : .regular)
                                if agents.focused?.id == item.id {
                                    Text("← focus")
                                        .font(.caption2)
                                        .foregroundStyle(.tint)
                                }
                            }
                            Text(item.worktreeURL.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("branch: \(item.branchName ?? "(detached)")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(item.id)
                    }
                }
                .frame(minHeight: 80, maxHeight: 140)
                .listStyle(.bordered)
            }

            HStack {
                TextField("branch (optional)", text: $agents.draftBranchName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(workspaces.current == nil)

                Button("Create Agent") {
                    agents.createAgent()
                }
                .disabled(workspaces.current == nil)

                Button("Refresh") {
                    agents.refresh()
                }
                .disabled(workspaces.current == nil)

                if let focused = agents.focused {
                    Button("Clear focus") {
                        agents.clearFocus()
                    }

                    Button("Respawn w/ secrets") {
                        agents.respawnWithCurrentSecrets()
                    }
                    .help("Restart focused Agent CLI with the current Enabled Secret Store set")

                    Button("Remove…", role: .destructive) {
                        agents.requestRemove(focused)
                    }
                }
            }

            if let focused = agents.focused {
                Text("Focused: \(focused.threeWordName) @ \(focused.worktreeURL.path)")
                    .font(.caption)
                    .textSelection(.enabled)
            }

            if let error = agents.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
    }

    private var removeDialogTitle: String {
        if let name = agents.pendingRemove?.threeWordName {
            return "Remove Agent “\(name)”?"
        }
        return "Remove Agent?"
    }
}
