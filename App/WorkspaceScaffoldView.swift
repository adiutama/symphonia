import SwiftUI

/// Minimal list / create / switch scaffold for Workspaces (P3.6). Ugly on purpose.
struct WorkspaceScaffoldView: View {
    @EnvironmentObject private var workspaces: WorkspaceController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workspaces")
                .font(.headline)

            if workspaces.workspaces.isEmpty {
                Text("None yet — create one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(selection: Binding(
                    get: { workspaces.current?.id },
                    set: { newID in
                        guard let newID,
                              let summary = workspaces.workspaces.first(where: { $0.id == newID })
                        else { return }
                        workspaces.select(summary)
                    }
                )) {
                    ForEach(workspaces.workspaces) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.slug)
                                    .fontWeight(workspaces.current?.id == item.id ? .bold : .regular)
                                if workspaces.current?.id == item.id {
                                    Text("← current")
                                        .font(.caption2)
                                        .foregroundStyle(.tint)
                                }
                            }
                            Text(item.dataDirURL.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(item.mainIsGitRepo ? "main/: git" : "main/: empty")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(item.id)
                    }
                }
                .frame(minHeight: 80, maxHeight: 160)
                .listStyle(.bordered)
            }

            HStack {
                TextField("slug", text: $workspaces.draftSlug)
                    .textFieldStyle(.roundedBorder)
                TextField("prefix (optional)", text: $workspaces.draftPrefix)
                    .textFieldStyle(.roundedBorder)
                Button("Create") {
                    workspaces.createWorkspace()
                }
                .disabled(workspaces.draftSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Refresh") {
                    workspaces.refresh()
                }

                if workspaces.current != nil {
                    Button("Clear") {
                        workspaces.clearSelection()
                    }
                }
            }

            if let current = workspaces.current {
                Text("Selected: \(current.slug) @ \(current.dataDirURL.path)")
                    .font(.caption)
                    .textSelection(.enabled)
            }

            if let error = workspaces.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    let preferences = PreferencesController()
    return WorkspaceScaffoldView()
        .environmentObject(WorkspaceController(preferences: preferences))
        .frame(width: 640)
}
