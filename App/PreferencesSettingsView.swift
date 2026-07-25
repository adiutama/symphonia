import SwiftUI

/// Settings (⌘,) — Global + per-Workspace settings and Secret Store (T.5).
struct PreferencesSettingsView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var secrets: SecretStoreController
    @EnvironmentObject private var settingsNavigation: SettingsNavigation

    @State private var selection: SettingsNavItem? = .globalMainCLI
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if !filteredGlobalItems.isEmpty {
                    Section("Global") {
                        ForEach(filteredGlobalItems) { item in
                            Label(item.title, systemImage: item.systemImage)
                                .tag(item)
                        }
                    }
                }

                Section("Workspace") {
                    if workspaces.workspaces.isEmpty {
                        Text("No Workspaces")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else if filteredWorkspaces.isEmpty {
                        Text("No matches")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(filteredWorkspaces) { workspace in
                            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                DisclosureGroup {
                                    workspaceNavLinks(workspace)
                                } label: {
                                    Label(workspace.slug, systemImage: "folder")
                                }
                            } else {
                                DisclosureGroup(isExpanded: .constant(true)) {
                                    workspaceNavLinks(workspace)
                                } label: {
                                    Label(workspace.slug, systemImage: "folder")
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .navigationTitle("Settings")
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { applyPendingNavigation() }
        .onChange(of: settingsNavigation.pending) { _, _ in
            applyPendingNavigation()
        }
        .onChange(of: selection) { _, newValue in
            ensureWorkspaceSelected(for: newValue)
        }
    }

    @ViewBuilder
    private func workspaceNavLinks(_ workspace: WorkspaceSummary) -> some View {
        NavigationLink(value: SettingsNavItem.workspaceSettings(workspace.id)) {
            Label("Settings", systemImage: "slider.horizontal.3")
        }
        NavigationLink(value: SettingsNavItem.workspaceSecrets(workspace.id)) {
            Label("Secret Store", systemImage: "key.fill")
        }
    }

    private var filteredGlobalItems: [SettingsNavItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return SettingsNavItem.globalItems }
        return SettingsNavItem.globalItems.filter { $0.title.lowercased().contains(q) }
    }

    private var filteredWorkspaces: [WorkspaceSummary] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return workspaces.workspaces }
        return workspaces.workspaces.filter { workspace in
            if workspace.slug.lowercased().contains(q) { return true }
            // Typing "set…" / "sec…" surfaces every Workspace so Settings / Secret Store links show.
            if "settings".hasPrefix(q) || "secret".hasPrefix(q) || "secrets".hasPrefix(q) {
                return true
            }
            return false
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
        case .globalCommands:
            globalForm { CommandBindingsSettingsView() }
                .navigationTitle("Commands")
        case .workspaceSettings(let id):
            workspaceSettingsDetail(id)
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
            saveSection(showResetGlobal: true)
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
            Text("Empty runs a login shell. Set a command when you want a specific CLI on spawn.")
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
            if preferences.preferences.leaderKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Leader key should not be empty.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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
            Text("New Worktree branches are created from this ref.")
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
            Text("Workspace values win when set; otherwise Global.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func workspaceSettingsDetail(_ workspaceId: String) -> some View {
        if let workspace = workspaces.workspaces.first(where: { $0.id == workspaceId }) {
            Form {
                Section {
                    Text(workspace.dataDirURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Empty fields inherit Global. Saved to config.toml.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(workspace.slug)
                }

                Section("Main CLI") {
                    TextField(
                        "Command",
                        text: Binding(
                            get: { preferences.workspaceOverrides.mainCLICommand ?? "" },
                            set: { preferences.workspaceOverrides.mainCLICommand = $0.isEmpty ? nil : $0 }
                        ),
                        prompt: Text("inherit Global")
                    )
                }

                Section("Editor") {
                    TextField(
                        "Command",
                        text: Binding(
                            get: { preferences.workspaceOverrides.editorCommand ?? "" },
                            set: { preferences.workspaceOverrides.editorCommand = $0.isEmpty ? nil : $0 }
                        ),
                        prompt: Text("inherit Global")
                    )
                }

                Section("Leader") {
                    TextField(
                        "Leader key",
                        text: Binding(
                            get: { preferences.workspaceOverrides.leaderKey ?? "" },
                            set: { preferences.workspaceOverrides.leaderKey = $0.isEmpty ? nil : $0 }
                        ),
                        prompt: Text("inherit Global")
                    )
                }

                Section("Prefix") {
                    TextField(
                        "Path",
                        text: Binding(
                            get: { preferences.workspaceOverrides.workspacesRoot ?? "" },
                            set: { preferences.workspaceOverrides.workspacesRoot = $0.isEmpty ? nil : $0 }
                        ),
                        prompt: Text("empty = Global Workspaces Root")
                    )
                    Text("Parent directory for this Workspace’s Data Dir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Base Ref") {
                    TextField(
                        "Base Ref",
                        text: Binding(
                            get: { preferences.workspaceOverrides.baseRef ?? "" },
                            set: { preferences.workspaceOverrides.baseRef = $0.isEmpty ? nil : $0 }
                        ),
                        prompt: Text("inherit Global")
                    )
                }

                saveSection(showResetGlobal: false)
            }
            .formStyle(.grouped)
            .padding()
            .navigationTitle("Workspace Settings")
        } else {
            ContentUnavailableView("Workspace not found", systemImage: "folder.badge.questionmark")
        }
    }

    @ViewBuilder
    private func workspaceSecretsDetail(_ workspaceId: String) -> some View {
        if let workspace = workspaces.workspaces.first(where: { $0.id == workspaceId }) {
            SecretStoreScaffoldView()
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

    private func saveSection(showResetGlobal: Bool) -> some View {
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
                if showResetGlobal {
                    Button("Reset Global to defaults") { preferences.resetToDefaults() }
                }
            }

            if let lastError = preferences.lastError ?? workspaces.lastError {
                Text(lastError)
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if case .workspaceSettings = selection {
                if let current = workspaces.current {
                    Text(SymphoniaPaths.workspaceConfigFile(in: current.dataDirURL).path)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            } else {
                Text(SymphoniaPaths.preferencesFile.path)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
    }

    private func applyPendingNavigation() {
        guard let destination = settingsNavigation.consume() else { return }
        switch destination {
        case .globalMainCLI:
            selection = .globalMainCLI
        case .workspaceSettings(let workspaceId):
            selection = .workspaceSettings(workspaceId)
            ensureWorkspaceSelected(for: selection)
        case .workspaceSecrets(let workspaceId):
            selection = .workspaceSecrets(workspaceId)
            ensureWorkspaceSelected(for: selection)
        }
    }

    private func ensureWorkspaceSelected(for item: SettingsNavItem?) {
        switch item {
        case .workspaceSettings(let id), .workspaceSecrets(let id):
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
    case globalCommands
    case globalEffective
    case workspaceSettings(String)
    case workspaceSecrets(String)

    var id: String {
        switch self {
        case .globalMainCLI: return "g-main"
        case .globalEditor: return "g-editor"
        case .globalLeader: return "g-leader"
        case .globalWorkspacesRoot: return "g-root"
        case .globalBaseRef: return "g-base"
        case .globalCommands: return "g-commands"
        case .globalEffective: return "g-effective"
        case .workspaceSettings(let id): return "wo-\(id)"
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
        case .globalCommands: return "Commands"
        case .globalEffective: return "Effective Setting"
        case .workspaceSettings: return "Settings"
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
        case .globalCommands: return "command"
        case .globalEffective: return "checkmark.seal"
        case .workspaceSettings: return "slider.horizontal.3"
        case .workspaceSecrets: return "key.fill"
        }
    }

    static var globalItems: [SettingsNavItem] {
        [
            .globalMainCLI, .globalEditor, .globalLeader, .globalWorkspacesRoot, .globalBaseRef,
            .globalCommands, .globalEffective,
        ]
    }
}
