import SwiftUI

/// Minimal Settings scene so the Operator can dogfood Global + Workspace Setting (P2.6 / P3).
/// Scaffolding only — polish after core phases.
struct PreferencesSettingsView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var workspaces: WorkspaceController

    var body: some View {
        Form {
            Section("Global Setting") {
                TextField(
                    "Main CLI command",
                    text: $preferences.preferences.mainCLICommand,
                    prompt: Text("empty = bare shell")
                )
                Text("Empty runs a normal login shell until the Operator sets a coding-agent command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    "Editor command",
                    text: $preferences.preferences.editorCommand,
                    prompt: Text("empty = $EDITOR")
                )
                Text("Empty uses $EDITOR (fallback vi). GUI editors are flagged for external launch later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Leader", text: $preferences.preferences.leaderKey)
                TextField("Workspaces Root", text: $preferences.preferences.workspacesRoot)
                TextField("Base Ref", text: $preferences.preferences.baseRef)
            }

            Section("Workspace Setting") {
                if let current = workspaces.current {
                    Text("Overrides for “\(current.slug)” → \(current.dataDirURL.path)/config.json")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .textSelection(.enabled)

                    TextField(
                        "Main CLI override",
                        text: Binding(
                            get: { preferences.workspaceOverrides.mainCLICommand ?? "" },
                            set: { preferences.workspaceOverrides.mainCLICommand = $0.isEmpty ? nil : $0 }
                        )
                    )
                    TextField(
                        "Editor override",
                        text: Binding(
                            get: { preferences.workspaceOverrides.editorCommand ?? "" },
                            set: { preferences.workspaceOverrides.editorCommand = $0.isEmpty ? nil : $0 }
                        )
                    )
                    TextField(
                        "Leader override",
                        text: Binding(
                            get: { preferences.workspaceOverrides.leaderKey ?? "" },
                            set: { preferences.workspaceOverrides.leaderKey = $0.isEmpty ? nil : $0 }
                        )
                    )
                    TextField(
                        "Prefix override",
                        text: Binding(
                            get: { preferences.workspaceOverrides.workspacesRoot ?? "" },
                            set: { preferences.workspaceOverrides.workspacesRoot = $0.isEmpty ? nil : $0 }
                        ),
                        prompt: Text("empty = Global Workspaces Root")
                    )
                    Text("Prefix is the parent of this Workspace’s container. Set at create to place it elsewhere; changing here updates config.json (does not move the folder yet).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(
                        "Base Ref override",
                        text: Binding(
                            get: { preferences.workspaceOverrides.baseRef ?? "" },
                            set: { preferences.workspaceOverrides.baseRef = $0.isEmpty ? nil : $0 }
                        )
                    )
                } else {
                    Text("Select a Workspace in the main window to edit persisted Workspace Setting.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section("Effective Setting") {
                LabeledContent(
                    "Main CLI",
                    value: preferences.effective.mainCLICommand.isEmpty
                        ? "(bare shell)"
                        : preferences.effective.mainCLICommand
                )
                LabeledContent("Editor", value: preferences.effective.editorCommand)
                LabeledContent("Editor presentation", value: preferences.effective.editorPresentation.rawValue)
                LabeledContent("Leader", value: preferences.effective.leaderKey)
                LabeledContent(
                    "Workspaces Root / Prefix",
                    value: preferences.effective.workspacesRoot
                )
                LabeledContent(
                    "Expanded parent",
                    value: preferences.effective.workspacesRootURL.path
                )
                LabeledContent("Base Ref", value: preferences.effective.baseRef)
            }

            Section {
                HStack {
                    Button("Save") {
                        preferences.save()
                        workspaces.saveCurrentWorkspaceSettings()
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    Button("Reload") {
                        preferences.reload()
                        workspaces.refresh()
                        if let current = workspaces.current {
                            workspaces.select(current)
                        }
                    }
                    Button("Reset Global to defaults") { preferences.resetToDefaults() }
                }

                if let lastError = preferences.lastError ?? workspaces.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .font(.caption)
                } else {
                    Text("Global: \(SymphoniaPaths.preferencesFile.path)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 520)
    }
}
