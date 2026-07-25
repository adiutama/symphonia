import SwiftUI

/// Minimal list / create / focus / remove scaffold for Worktrees (P4.7). Ugly on purpose.
struct WorktreeScaffoldView: View {
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var worktrees: WorktreeController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Worktrees")
                .font(.headline)

            if workspaces.current == nil {
                Text("Select a Workspace to manage Worktrees.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if worktrees.worktrees.isEmpty {
                Text("None yet — create one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(selection: Binding(
                    get: { worktrees.focused?.id },
                    set: { newID in
                        guard let newID,
                              let summary = worktrees.worktrees.first(where: { $0.id == newID })
                        else { return }
                        worktrees.focus(summary)
                    }
                )) {
                    ForEach(worktrees.worktrees) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.threeWordName)
                                    .fontWeight(worktrees.focused?.id == item.id ? .bold : .regular)
                                if worktrees.focused?.id == item.id {
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
                TextField("branch (optional)", text: $worktrees.draftBranchName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(workspaces.current == nil)

                Button("Create Worktree") {
                    worktrees.createWorktree()
                }
                .disabled(workspaces.current == nil)

                Button("Refresh") {
                    worktrees.refresh()
                }
                .disabled(workspaces.current == nil)

                if let focused = worktrees.focused {
                    Button("Clear focus") {
                        worktrees.clearFocus()
                    }

                    Button("Respawn w/ secrets") {
                        worktrees.respawnWithCurrentSecrets()
                    }
                    .help("Restart focused Worktree CLI with the current Enabled Secret Store set")

                    Button("Remove…", role: .destructive) {
                        worktrees.requestRemove(focused)
                    }
                }
            }

            if let focused = worktrees.focused {
                Text("Focused: \(focused.threeWordName) @ \(focused.worktreeURL.path)")
                    .font(.caption)
                    .textSelection(.enabled)
            }

            if let error = worktrees.lastError {
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
    }

    private var removeDialogTitle: String {
        if let name = worktrees.pendingRemove?.threeWordName {
            return "Remove Worktree \u{201C}\(name)\u{201D}?"
        }
        return "Remove Worktree?"
    }
}
