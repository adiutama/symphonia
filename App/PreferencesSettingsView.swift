import SwiftUI

/// Settings (⌘,) — Global + per-Workspace settings and Secret Store (T.5).
/// Detail chrome follows Supacode: page title → section → multi-row cards.
/// Window uses fullSizeContentView so traffic lights sit in the sidebar (Raycast/Supacode).
struct PreferencesSettingsView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var settingsNavigation: SettingsNavigation
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    @State private var selection: SettingsNavItem? = .globalGeneral
    /// Draft overrides for the Workspace Settings pane (may differ from Main’s current Workspace).
    @State private var draftOverrides: WorkspaceSettingOverrides = .none
    @State private var draftWorkspaceId: String?
    /// Skip workspace autosave while selection loads overrides from disk.
    @State private var suppressWorkspaceAutosave = false

    /// Clearance under system traffic lights when titlebar is transparent / full-size content.
    private let trafficLightClearance: CGFloat = 52

    var body: some View {
        // Custom HStack split — NavigationSplitView draws an inset sidebar that never
        // reaches the traffic lights (unlike Xcode / Raycast / Supacode).
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 220)
                .frame(maxHeight: .infinity, alignment: .top)

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(ghosttyTheme.background)
        }
        .frame(minWidth: 720, minHeight: 480)
        .background {
            if preferences.preferences.chromeGlass {
                Color.clear
            } else {
                ghosttyTheme.background
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .symphoniaTitlebarChrome()
        .background(SettingsWindowChrome())
        .onAppear { applyPendingNavigation() }
        .onChange(of: settingsNavigation.pending) { _, _ in
            applyPendingNavigation()
        }
        .onChange(of: selection) { _, newValue in
            suppressWorkspaceAutosave = true
            mountWorkspaceSettingsIfNeeded(for: newValue)
            DispatchQueue.main.async {
                suppressWorkspaceAutosave = false
            }
        }
        .onChange(of: preferences.preferences) { _, _ in
            guard isEditingGlobal else { return }
            preferences.scheduleSave()
        }
        .onChange(of: draftOverrides) { _, _ in
            guard case .workspaceSettings = selection,
                  let id = draftWorkspaceId,
                  !suppressWorkspaceAutosave,
                  let workspace = workspaces.workspaces.first(where: { $0.id == id })
            else { return }
            // Keep Main’s Effective Setting live when editing the current Workspace.
            if workspaces.current?.id == id {
                preferences.workspaceOverrides = draftOverrides
            }
            workspaces.scheduleSaveWorkspaceSettings(for: workspace, overrides: draftOverrides)
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
                        .foregroundStyle(ghosttyTheme.secondaryText)
                        .textCase(nil)
                }

                Section {
                    if workspaces.workspaces.isEmpty {
                        Text("No Workspaces")
                            .foregroundStyle(ghosttyTheme.secondaryText)
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
                        .foregroundStyle(ghosttyTheme.secondaryText)
                        .textCase(nil)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .chromeSurface(glass: preferences.preferences.chromeGlass, solid: ghosttyTheme.sidebar)
        .overlay(alignment: .trailing) {
            SoftPaneHairline()
        }
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
            shortcutsPage
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
                            .settingsControlField()
                            .frame(minWidth: 160, idealWidth: 220)
                            .frame(maxWidth: 280)
                    }
                    SettingsRowDivider()
                    SettingsRow(
                        title: "Editor",
                        description: "Empty uses $EDITOR (fallback vi). GUI editors launch externally."
                    ) {
                        TextField("Command", text: $preferences.preferences.editorCommand)
                            .settingsControlField()
                            .frame(minWidth: 160, idealWidth: 220)
                            .frame(maxWidth: 280)
                    }
                    SettingsRowDivider()
                    SettingsRow(
                        title: "Command Center mode",
                        description: "Applied when Leader opens Command Center. ⇧Tab toggles while open."
                    ) {
                        Picker(
                            "",
                            selection: $preferences.preferences.commandCenterPreferredMode
                        ) {
                            Text("Input").tag(CommandCenterMode.input)
                            Text("Normal").tag(CommandCenterMode.normal)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 160)
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
                            .settingsControlField()
                            .frame(minWidth: 100, idealWidth: 140)
                            .frame(maxWidth: 180)
                    }
                }
            }

            SettingsSection(title: "Appearance") {
                SettingsCard {
                    SettingsRow(
                        title: "Glass chrome",
                        description: "Liquid Glass sidebar on macOS 26+ (frosted fallback earlier). Also tints Command Center and Overlay peeks."
                    ) {
                        Toggle("", isOn: $preferences.preferences.chromeGlass)
                            .labelsHidden()
                            .toggleStyle(.switch)
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

    // MARK: - Shortcuts

    private var shortcutsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShortcutsSettingsView()
                .padding(24)
            if let lastError = preferences.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Workspace Settings

    @ViewBuilder
    private func workspaceSettingsDetail(_ workspaceId: String) -> some View {
        if let workspace = workspaces.workspaces.first(where: { $0.id == workspaceId }) {
            SettingsPage(title: workspace.slug) {
                Text("Empty fields inherit Global. Changes save to this Workspace’s config.toml.")
                    .font(.caption)
                    .foregroundStyle(ghosttyTheme.secondaryText)

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
                                        get: { draftOverrides.mainCLICommand ?? "" },
                                        set: { newValue in
                                            if draftOverrides.mainCLICommand == nil {
                                                if newValue.isEmpty { return }
                                                draftOverrides.mainCLICommand = newValue
                                            } else {
                                                draftOverrides.mainCLICommand = newValue
                                            }
                                        }
                                    )
                                )
                                .settingsControlField()
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
                                    get: { draftOverrides.editorCommand ?? "" },
                                    set: { draftOverrides.editorCommand = $0.isEmpty ? nil : $0 }
                                )
                            )
                            .settingsControlField()
                            .frame(minWidth: 160, idealWidth: 220)
                            .frame(maxWidth: 280)
                        }
                        SettingsRowDivider()
                        SettingsRow(
                            title: "Leader",
                            description: "Empty inherits Global Leader."
                        ) {
                            KeyChordField(chord: workspaceLeaderBinding, emptyLabel: "Inherit")
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
                                    get: { draftOverrides.baseRef ?? "" },
                                    set: { draftOverrides.baseRef = $0.isEmpty ? nil : $0 }
                                )
                            )
                            .settingsControlField()
                            .frame(minWidth: 100, idealWidth: 140)
                            .frame(maxWidth: 180)
                        }
                    }
                }

                if let lastError = workspaces.lastError {
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
            get: { draftOverrides.leaderKey ?? "" },
            set: { draftOverrides.leaderKey = $0.isEmpty ? nil : $0 }
        )
    }

    private var workspacePrefixBinding: Binding<String> {
        Binding(
            get: { draftOverrides.workspacesRoot ?? "" },
            set: { draftOverrides.workspacesRoot = $0.isEmpty ? nil : $0 }
        )
    }

    private var mainCLIOverrideDescription: String {
        let override = draftOverrides.mainCLICommand
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
        let override = draftOverrides.mainCLICommand
        if override == nil {
            Button("Use bare shell") {
                draftOverrides.mainCLICommand = ""
            }
            .buttonStyle(.borderless)
            .font(.caption)
        } else {
            Button("Inherit Global") {
                draftOverrides.mainCLICommand = nil
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    // MARK: - Secret Store

    @ViewBuilder
    private func workspaceSecretsDetail(_ workspaceId: String) -> some View {
        if let workspace = workspaces.workspaces.first(where: { $0.id == workspaceId }) {
            SecretStoreScaffoldView(workspace: workspace)
                .navigationTitle("")
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
        case .workspaceSecrets(let workspaceId):
            selection = .workspaceSecrets(workspaceId)
        }
    }

    /// Load draft overrides for Workspace Settings without changing Main’s current Workspace.
    private func mountWorkspaceSettingsIfNeeded(for item: SettingsNavItem?) {
        guard case .workspaceSettings(let id) = item,
              let workspace = workspaces.workspaces.first(where: { $0.id == id })
        else {
            draftWorkspaceId = nil
            return
        }
        draftWorkspaceId = id
        if workspace.id == workspaces.current?.id {
            draftOverrides = preferences.workspaceOverrides
        } else if let loaded = workspaces.loadSettingsOverrides(for: workspace) {
            draftOverrides = loaded
        } else {
            draftOverrides = .none
        }
    }

    private func healSelectionAfterWorkspaceRelocate(from oldId: String, to newId: String) {
        guard oldId != newId else { return }
        switch selection {
        case .workspaceSettings(let id) where id == oldId:
            suppressWorkspaceAutosave = true
            selection = .workspaceSettings(newId)
            draftWorkspaceId = newId
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
        case .globalCommands: return "Shortcuts"
        case .workspaceSettings: return "Settings"
        case .workspaceSecrets: return "Secret Store"
        }
    }

    var systemImage: String {
        switch self {
        case .globalGeneral: return "gearshape"
        case .globalCommands: return "keyboard"
        case .workspaceSettings: return "slider.horizontal.3"
        case .workspaceSecrets: return "key"
        }
    }

    static var globalItems: [SettingsNavItem] {
        [.globalGeneral, .globalCommands]
    }
}
