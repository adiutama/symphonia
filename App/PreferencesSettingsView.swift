import SwiftUI

/// Settings (⌘,) — Global section + Workspace section with nested Secret Store (Supacode-style).
struct PreferencesSettingsView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var secrets: SecretStoreController

    @State private var selection: SettingsNavItem? = .globalMainCLI

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Global") {
                    ForEach(SettingsNavItem.globalItems) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                    }
                }

                Section("Workspace") {
                    if workspaces.workspaces.isEmpty {
                        Text("No Workspaces")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(workspaces.workspaces) { workspace in
                            DisclosureGroup {
                                NavigationLink(value: SettingsNavItem.workspaceOverrides(workspace.id)) {
                                    Label("Effective overrides", systemImage: "slider.horizontal.3")
                                }
                                NavigationLink(value: SettingsNavItem.workspaceSecrets(workspace.id)) {
                                    Label("Secret Store", systemImage: "key.fill")
                                }
                            } label: {
                                Label(workspace.slug, systemImage: "folder")
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .navigationTitle("Settings")
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 720, minHeight: 480)
        .onChange(of: selection) { _, newValue in
            ensureWorkspaceSelected(for: newValue)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .globalMainCLI:
            globalForm { mainCLIFields }
                .navigationTitle("Main CLI")
        case .globalEditor:
            globalForm { editorFields }
                .navigationTitle("Editor")
        case .globalLeader:
            globalForm { leaderFields }
                .navigationTitle("Leader")
        case .globalWorkspacesRoot:
            globalForm { workspacesRootFields }
                .navigationTitle("Workspaces Root")
        case .globalBaseRef:
            globalForm { baseRefFields }
                .navigationTitle("Base Ref")
        case .globalEffective:
            globalForm { effectiveFields }
                .navigationTitle("Effective Setting")
        case .workspaceOverrides(let id):
            workspaceOverridesDetail(id)
        case .workspaceSecrets(let id):
            workspaceSecretsDetail(id)
        case .none:
            ContentUnavailableView(
                "Settings",
                systemImage: "gearshape",
                description: Text("Choose Global or a Workspace.")
            )
        }
    }

    private func globalForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form {
            content()
            saveSection
        }
        .formStyle(.grouped)
        .padding()
    }

    private var mainCLIFields: some View {
        Section("Main CLI") {
            TextField(
                "Command",
                text: $preferences.preferences.mainCLICommand,
                prompt: Text("empty = bare shell")
            )
            Text("Empty runs a normal login shell until the Operator sets a coding-agent command.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var editorFields: some View {
        Section("Editor") {
            TextField(
                "Command",
                text: $preferences.preferences.editorCommand,
                prompt: Text("empty = $EDITOR")
            )
            Text("Empty uses $EDITOR (fallback vi). GUI editors launch externally.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var leaderFields: some View {
        Section("Leader") {
            TextField("Leader key", text: $preferences.preferences.leaderKey)
            Text("Opens Command Center. Example: ctrl+p")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var workspacesRootFields: some View {
        Section("Workspaces Root") {
            TextField("Path", text: $preferences.preferences.workspacesRoot)
            Text("Parent for new Workspaces when Prefix is empty.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var baseRefFields: some View {
        Section("Base Ref") {
            TextField("Base Ref", text: $preferences.preferences.baseRef)
            Text("New Agent branches are created from this ref.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var effectiveFields: some View {
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
            LabeledContent("Workspaces Root / Prefix", value: preferences.effective.workspacesRoot)
            LabeledContent("Expanded parent", value: preferences.effective.workspacesRootURL.path)
            LabeledContent("Base Ref", value: preferences.effective.baseRef)
        }
    }

    @ViewBuilder
    private func workspaceOverridesDetail(_ workspaceId: String) -> some View {
        if let workspace = workspaces.workspaces.first(where: { $0.id == workspaceId }) {
            Form {
                Section {
                    Text(workspace.dataDirURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } header: {
                    Text(workspace.slug)
                }

                Section("Workspace Setting overrides") {
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
                    TextField(
                        "Base Ref override",
                        text: Binding(
                            get: { preferences.workspaceOverrides.baseRef ?? "" },
                            set: { preferences.workspaceOverrides.baseRef = $0.isEmpty ? nil : $0 }
                        )
                    )
                }

                saveSection
            }
            .formStyle(.grouped)
            .padding()
            .navigationTitle(workspace.slug)
        } else {
            ContentUnavailableView("Workspace not found", systemImage: "folder.badge.questionmark")
        }
    }

    @ViewBuilder
    private func workspaceSecretsDetail(_ workspaceId: String) -> some View {
        if let workspace = workspaces.workspaces.first(where: { $0.id == workspaceId }) {
            ScrollView {
                SecretStoreScaffoldView()
                    .padding()
            }
            .navigationTitle("Secret Store")
            .onAppear {
                if workspaces.current?.id != workspace.id {
                    workspaces.select(workspace)
                }
            }
        } else {
            ContentUnavailableView("Workspace not found", systemImage: "folder.badge.questionmark")
        }
    }

    private var saveSection: some View {
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

    private func ensureWorkspaceSelected(for item: SettingsNavItem?) {
        switch item {
        case .workspaceOverrides(let id), .workspaceSecrets(let id):
            if let workspace = workspaces.workspaces.first(where: { $0.id == id }),
               workspaces.current?.id != id
            {
                workspaces.select(workspace)
            }
        default:
            break
        }
    }
}

private enum SettingsNavItem: Hashable, Identifiable {
    case globalMainCLI
    case globalEditor
    case globalLeader
    case globalWorkspacesRoot
    case globalBaseRef
    case globalEffective
    case workspaceOverrides(String)
    case workspaceSecrets(String)

    var id: String {
        switch self {
        case .globalMainCLI: return "g-main"
        case .globalEditor: return "g-editor"
        case .globalLeader: return "g-leader"
        case .globalWorkspacesRoot: return "g-root"
        case .globalBaseRef: return "g-base"
        case .globalEffective: return "g-effective"
        case .workspaceOverrides(let id): return "wo-\(id)"
        case .workspaceSecrets(let id): return "ws-\(id)"
        }
    }

    var title: String {
        switch self {
        case .globalMainCLI: return "Main CLI"
        case .globalEditor: return "Editor"
        case .globalLeader: return "Leader"
        case .globalWorkspacesRoot: return "Workspaces Root"
        case .globalBaseRef: return "Base Ref"
        case .globalEffective: return "Effective Setting"
        case .workspaceOverrides: return "Overrides"
        case .workspaceSecrets: return "Secret Store"
        }
    }

    var systemImage: String {
        switch self {
        case .globalMainCLI: return "terminal"
        case .globalEditor: return "pencil"
        case .globalLeader: return "keyboard"
        case .globalWorkspacesRoot: return "externaldrive"
        case .globalBaseRef: return "arrow.triangle.branch"
        case .globalEffective: return "checkmark.seal"
        case .workspaceOverrides: return "slider.horizontal.3"
        case .workspaceSecrets: return "key.fill"
        }
    }

    static var globalItems: [SettingsNavItem] {
        [.globalMainCLI, .globalEditor, .globalLeader, .globalWorkspacesRoot, .globalBaseRef, .globalEffective]
    }
}
