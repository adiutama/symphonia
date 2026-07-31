import AppKit
import SwiftUI

/// Create / rename / archive sheets for `WorkspaceSidebarView`.
enum WorkspaceSidebarSheets {
    struct CreateWorktree: View {
        @EnvironmentObject private var workspaces: WorkspaceController
        @EnvironmentObject private var worktrees: WorktreeController
        @Binding var branch: String
        @Binding var folder: String

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("New Worktree")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("branch name", text: $branch)
                        .textFieldStyle(.roundedBorder)
                    Text("Git branch — the primary label in the sidebar. Empty → folder name below.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("folder name", text: $folder)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            let name = worktrees.generateThreeWordName()
                            folder = name
                            branch = name
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
                        worktrees.createWorktree(branch: branch, folder: folder)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        workspaces.current == nil
                            || folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            .onAppear {
                let name = worktrees.generateThreeWordName()
                folder = name
                branch = name
                worktrees.lastError = nil
            }
        }
    }

    struct RenameWorkspace: View {
        @EnvironmentObject private var workspaces: WorkspaceController
        let workspace: WorkspaceSummary
        @Binding var slug: String
        let onRenamed: (_ oldID: String, _ current: WorkspaceSummary?) -> Void

        var body: some View {
            let trimmedSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
            let previewDir = WorkspaceStore().dataDirURL(
                slug: trimmedSlug.isEmpty ? workspace.slug : trimmedSlug,
                prefix: workspace.prefix,
                workspacesRoot: workspaces.workspacesRoot
            )
            return VStack(alignment: .leading, spacing: 12) {
                Text("Rename Workspace")
                    .font(.headline)
                TextField("slug", text: $slug)
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
                        workspaces.renameWorkspace(newSlug: slug)
                        if workspaces.lastError == nil {
                            onRenamed(oldExpandedID, workspaces.current)
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
                slug = workspace.slug
                workspaces.lastError = nil
            }
        }
    }

    struct RenameWorktree: View {
        @EnvironmentObject private var worktrees: WorktreeController
        let agent: WorktreeSummary
        @Binding var branch: String
        @Binding var folder: String

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename Worktree")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("branch name", text: $branch)
                        .textFieldStyle(.roundedBorder)
                    Text("Git branch — the primary label in the sidebar.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("folder name", text: $folder)
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
                        worktrees.renameWorktree(branch: branch, folder: folder)
                    }
                    .disabled(
                        branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                branch = agent.branchName ?? agent.threeWordName
                folder = agent.threeWordName
                worktrees.lastError = nil
            }
        }
    }

    struct ArchivedWorktrees: View {
        @EnvironmentObject private var worktrees: WorktreeController
        let workspace: WorkspaceSummary
        @Binding var presentedWorkspace: WorkspaceSummary?

        var body: some View {
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
                                NSWorkspace.shared.activateFileViewerSelecting([agent.worktreeURL])
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
                    Button("Done") { presentedWorkspace = nil }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 380)
        }
    }
}
