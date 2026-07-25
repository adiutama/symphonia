import SwiftUI

/// Settings (⌘,) — Global + per-Workspace settings and Secret Store (T.5).
/// Detail chrome follows Supacode: page title → section → multi-row cards.
/// Window uses fullSizeContentView so traffic lights sit in the sidebar (Raycast/Supacode).
struct PreferencesSettingsView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var secrets: SecretStoreController
    @EnvironmentObject private var settingsNavigation: SettingsNavigation
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    @State private var selection: SettingsNavItem? = .globalGeneral
    /// Skip workspace autosave while selection loads overrides from disk.
    @State private var suppressWorkspaceAutosave = false

    /// Clearance under system traffic lights when titlebar is transparent / full-size content.
    private let trafficLightClearance: CGFloat = 28

    var body: some View {
        // Custom HStack split — NavigationSplitView draws an inset sidebar that never
        // reaches the traffic lights (unlike Xcode / Raycast / Supacode).
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 220)
                .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(ghosttyTheme.background)
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(ghosttyTheme.background)
        .ignoresSafeArea(.container, edges: .top)
        .symphoniaTitlebarChrome()
        .background(SettingsWindowChrome())
        .onAppear { applyPendingNavigation() }
        .onChange(of: settingsNavigation.pending) { _, _ in
            applyPendingNavigation()
        }
        .onChange(of: selection) { _, newValue in
            suppressWorkspaceAutosave = true
            ensureWorkspaceSelected(for: newValue)
            DispatchQueue.main.async {
                suppressWorkspaceAutosave = false
            }
        }
        .onChange(of: preferences.preferences) { _, _ in
            guard isEditingGlobal else { return }
            preferences.scheduleSave()
        }
        .onChange(of: preferences.workspaceOverrides) { _, _ in
            guard case .workspaceSettings = selection, !suppressWorkspaceAutosave else { return }
            workspaces.scheduleSaveCurrentWorkspaceSettings()
        }
        .onChange(of: workspaces.lastWorkspaceIdRemap) { _, remap in
            guard let remap else { return }
            healSelectionAfterWorkspaceRelocate(from: remap.from, to: remap.to)
        }
    }

    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: trafficLightClearance)
                .frame(maxWidth: .infinity)
                .windowDragRegion()

            List(selection: $selection) {
                Section {
                    ForEach(SettingsNavItem.globalItems) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .tag(item)
                    }
                } header: {
                    Text("Global")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }

                Section {
                    if workspaces.workspaces.isEmpty {
                        Text("No Workspaces")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(workspaces.workspaces) { workspace in
                            DisclosureGroup {
                                workspaceNavRows(workspace)
                            } label: {
                                Label(workspace.slug, systemImage: "folder")
                            }
                        }
                    }
                } header: {
                    Text("Workspace")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ghosttyTheme.sidebar)
    }

    private var isEditingGlobal: Bool {
        switch selection {
        case .globalGeneral, .globalCommands: return true
        default: return false
        }
    }

    @ViewBuilder
    private func workspaceNavRows(_ workspace: WorkspaceSummary) -> some View {
        Label("Settings", systemImage: "slider.horizontal.3")
            .tag(SettingsNavItem.workspaceSettings(workspace.id))
        Label("Secret Store", systemImage: "key")
            .tag(SettingsNavItem.workspaceSecrets(workspace.id))
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .globalGeneral:
            generalPage
                .navigationTitle("")
        case .globalCommands:
            commandsPage
                .navigationTitle("")
        case .workspaceSettings(let id):
            workspaceSettingsDetail(id)
                .navigationTitle("")
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

    // MARK: - General

    private var generalPage: some View {
        SettingsPage(title: "General") {
            SettingsSection(title: "Runtime") {
                SettingsCard {
                    SettingsRow(
                        title: "Main CLI",
                        description: "Empty runs a login shell. Set a command when you want a specific CLI on spawn."
                    ) {
                        TextField("Command", text: $preferences.preferences.mainCLICommand)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 160, idealWidth: 220)
                            .frame(maxWidth: 280)
                    }
                    SettingsRowDivider()
                    SettingsRow(
                        title: "Editor",
                        description: "Empty uses $EDITOR (fallback vi). GUI editors launch externally."
                    ) {
                        TextField("Command", text: $preferences.preferences.editorCommand)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 160, idealWidth: 220)
                            .frame(maxWidth: 280)
                    }
                    SettingsRowDivider()
                    SettingsRow(
                        title: "Leader",
                        description: leaderDescription
                    ) {
                        KeyChordField(chord: $preferences.preferences.leaderKey)
                    }
                }
            }

            SettingsSection(title: "Workspace defaults") {
                SettingsCard {
                    SettingsRow(
                        title: "Workspaces Root",
                        description: "Parent for new Workspaces when Prefix is empty."
                    ) {
                        DirectoryPathField(path: $preferences.preferences.workspacesRoot)
                    }
                    SettingsRowDivider()
                    SettingsRow(
                        title: "Base Ref",
                        description: "New Worktree branches are created from this ref."
                    ) {
                        TextField("Ref", text: $preferences.preferences.baseRef)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 100, idealWidth: 140)
                            .frame(maxWidth: 180)
                    }
                }
            }

            if let lastError = preferences.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var leaderDescription: String {
        if preferences.preferences.leaderKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Opens Command Center. Leader key should not be empty."
        }
        return "Opens Command Center."
    }

    // MARK: - Commands

    private var commandsPage: some View {
        SettingsPage(title: "Commands") {
            CommandBindingsSettingsView()
            if let lastError = preferences.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Workspace Settings

    @ViewBuilder
    private func workspaceSettingsDetail(_ workspaceId: String) -> some View {
        if let workspace = workspaces.workspaces.first(where: { $0.id == workspaceId }) {
            SettingsPage(title: workspace.slug) {
                Text(workspace.dataDirURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Empty fields inherit Global. Changes save to this Workspace’s config.toml.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingsSection(title: "Runtime") {
                    SettingsCard {
                        SettingsRow(
                            title: "Main CLI",
                            description: mainCLIOverrideDescription
                        ) {
                            VStack(alignment: .trailing, spacing: 6) {
                                TextField(
                                    "Command",
                                    text: Binding(
                                        get: { preferences.workspaceOverrides.mainCLICommand ?? "" },
                                        set: { newValue in
                                            if preferences.workspaceOverrides.mainCLICommand == nil {
                                                if newValue.isEmpty { return }
                                                preferences.workspaceOverrides.mainCLICommand = newValue
                                            } else {
                                                preferences.workspaceOverrides.mainCLICommand = newValue
                                            }
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 160, idealWidth: 220)
                                .frame(maxWidth: 280)

                                mainCLIOverrideControls
                            }
                        }
                        SettingsRowDivider()
                        SettingsRow(
                            title: "Editor",
                            description: "Empty inherits Global Editor."
                        ) {
                            TextField(
                                "Command",
                                text: Binding(
                                    get: { preferences.workspaceOverrides.editorCommand ?? "" },
                                    set: { preferences.workspaceOverrides.editorCommand = $0.isEmpty ? nil : $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 160, idealWidth: 220)
                            .frame(maxWidth: 280)
                        }
                        SettingsRowDivider()
                        SettingsRow(
                            title: "Leader",
                            description: "Empty inherits Global Leader."
                        ) {
                            KeyChordField(chord: workspaceLeaderBinding)
                        }
                    }
                }

                SettingsSection(title: "Paths") {
                    SettingsCard {
                        SettingsRow(
                            title: "Prefix",
                            description: "Parent directory for this Workspace’s Data Dir. Empty uses Global Workspaces Root. Changing Prefix moves the Data Dir."
                        ) {
                            DirectoryPathField(path: workspacePrefixBinding, prompt: "Prefix")
                        }
                        SettingsRowDivider()
                        SettingsRow(
                            title: "Base Ref",
                            description: "Empty inherits Global Base Ref."
                        ) {
                            TextField(
                                "Ref",
                                text: Binding(
                                    get: { preferences.workspaceOverrides.baseRef ?? "" },
                                    set: { preferences.workspaceOverrides.baseRef = $0.isEmpty ? nil : $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 100, idealWidth: 140)
                            .frame(maxWidth: 180)
                        }
                    }
                }

                if let lastError = preferences.lastError ?? workspaces.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } else {
            ContentUnavailableView("Workspace not found", systemImage: "folder.badge.questionmark")
        }
    }

    private var workspaceLeaderBinding: Binding<String> {
        Binding(
            get: { preferences.workspaceOverrides.leaderKey ?? "" },
            set: { preferences.workspaceOverrides.leaderKey = $0.isEmpty ? nil : $0 }
        )
    }

    private var workspacePrefixBinding: Binding<String> {
        Binding(
            get: { preferences.workspaceOverrides.workspacesRoot ?? "" },
            set: { preferences.workspaceOverrides.workspacesRoot = $0.isEmpty ? nil : $0 }
        )
    }

    private var mainCLIOverrideDescription: String {
        let override = preferences.workspaceOverrides.mainCLICommand
        let global = preferences.preferences.mainCLICommand
        let globalLabel = global.isEmpty ? "bare shell" : global
        if override == nil {
            return "Inherits Global (\(globalLabel))."
        }
        if override?.isEmpty == true {
            return "Bare shell (overrides Global)."
        }
        return "Overrides Global (\(globalLabel))."
    }

    @ViewBuilder
    private var mainCLIOverrideControls: some View {
        let override = preferences.workspaceOverrides.mainCLICommand
        if override == nil {
            Button("Use bare shell") {
                preferences.workspaceOverrides.mainCLICommand = ""
            }
            .buttonStyle(.borderless)
            .font(.caption)
        } else {
            Button("Inherit Global") {
                preferences.workspaceOverrides.mainCLICommand = nil
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    // MARK: - Secret Store

    @ViewBuilder
    private func workspaceSecretsDetail(_ workspaceId: String) -> some View {
        if let workspace = workspaces.workspaces.first(where: { $0.id == workspaceId }) {
            SecretStoreScaffoldView()
                .navigationTitle("")
                .onAppear {
                    if workspaces.current?.id != workspace.id {
                        workspaces.select(workspace)
                    }
                }
        } else {
            ContentUnavailableView("Workspace not found", systemImage: "folder.badge.questionmark")
        }
    }

    // MARK: - Navigation

    private func applyPendingNavigation() {
        guard let destination = settingsNavigation.consume() else { return }
        switch destination {
        case .globalMainCLI, .globalGeneral:
            selection = .globalGeneral
        case .globalCommands:
            selection = .globalCommands
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

    private func healSelectionAfterWorkspaceRelocate(from oldId: String, to newId: String) {
        guard oldId != newId else { return }
        switch selection {
        case .workspaceSettings(let id) where id == oldId:
            suppressWorkspaceAutosave = true
            selection = .workspaceSettings(newId)
            DispatchQueue.main.async { suppressWorkspaceAutosave = false }
        case .workspaceSecrets(let id) where id == oldId:
            suppressWorkspaceAutosave = true
            selection = .workspaceSecrets(newId)
            DispatchQueue.main.async { suppressWorkspaceAutosave = false }
        default:
            break
        }
    }
}

private enum SettingsNavItem: Hashable, Identifiable {
    case globalGeneral
    case globalCommands
    case workspaceSettings(String)
    case workspaceSecrets(String)

    var id: String {
        switch self {
        case .globalGeneral: return "g-general"
        case .globalCommands: return "g-commands"
        case .workspaceSettings(let id): return "wo-\(id)"
        case .workspaceSecrets(let id): return "ws-\(id)"
        }
    }

    var title: String {
        switch self {
        case .globalGeneral: return "General"
        case .globalCommands: return "Commands"
        case .workspaceSettings: return "Settings"
        case .workspaceSecrets: return "Secret Store"
        }
    }

    var systemImage: String {
        switch self {
        case .globalGeneral: return "gearshape"
        case .globalCommands: return "command"
        case .workspaceSettings: return "slider.horizontal.3"
        case .workspaceSecrets: return "key"
        }
    }

    static var globalItems: [SettingsNavItem] {
        [.globalGeneral, .globalCommands]
    }
}
