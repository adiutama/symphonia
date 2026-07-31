import SwiftUI
import AppKit

/// Settings (⌘,) — Global + per-Workspace settings and Secret Store (T.5).
/// Detail chrome follows Supacode: page title → section → multi-row cards.
/// Window uses fullSizeContentView so traffic lights sit in the sidebar (Raycast/Supacode).
struct PreferencesSettingsView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var settingsNavigation: SettingsNavigation
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme
    @EnvironmentObject private var sparkle: SparkleUpdateController

    @State private var selection: SettingsNavItem? = .globalGeneral
    /// Draft overrides for the Workspace Settings pane (may differ from Main’s current Workspace).
    @State private var draftOverrides: WorkspaceSettingOverrides = .none
    @State private var draftWorkspaceId: String?
    /// Skip workspace autosave while selection loads overrides from disk.
    @State private var suppressWorkspaceAutosave = false
    @State private var showExternalEditorReminder = false
    @State private var showResetPreferencesConfirm = false

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
        .alert("External Editor", isPresented: $showExternalEditorReminder) {
            Button("OK") {
                preferences.preferences.hasSeenExternalEditorReminder = true
                preferences.scheduleSave()
            }
        } message: {
            Text(
                "GUI editors run as External Activities — Focus brings them forward, End quits. Full peek/hide needs a TUI editor."
            )
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
        case .globalGeneral, .globalTools, .globalCommands: return true
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
        case .globalTools:
            toolsPage
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
            SettingsSection(title: "Command Center") {
                SettingsCard {
                    SettingsRow(
                        title: "Mode",
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
                        description: "Liquid Glass sidebar, Command Center, Glance, and Overlay peeks."
                    ) {
                        Toggle("", isOn: $preferences.preferences.chromeGlass)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }

            SettingsSection(title: "Updates") {
                SettingsCard {
                    SettingsRow(
                        title: "Channel",
                        description: "Stable uses tagged releases. Nightly is a pre-release build from main — may be rough."
                    ) {
                        Picker("", selection: $preferences.preferences.updateChannel) {
                            ForEach(UpdateChannel.allCases) { channel in
                                Text(channel.displayName).tag(channel)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }
            }
            .onChange(of: preferences.preferences.updateChannel) { _, _ in
                sparkle.noteChannelChanged()
            }

            SettingsSection(title: "Reset") {
                SettingsCard {
                    SettingsRow(
                        title: "Reset Global preferences",
                        description: "Restores ~/.symphonia/preferences.toml to factory defaults (Tools, Leader, chrome…). Workspace configs and Secret Stores are untouched. Onboarding runs again."
                    ) {
                        Button("Reset…") {
                            showResetPreferencesConfirm = true
                        }
                    }
                }
            }

            if let lastError = preferences.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .alert("Reset Global preferences?", isPresented: $showResetPreferencesConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                preferences.resetToDefaults()
            }
        } message: {
            Text("This rewrites ~/.symphonia/preferences.toml. Workspace folders and secrets stay as they are.")
        }
    }

    // MARK: - Tools

    private var toolsPage: some View {
        SettingsPage(title: "Tools") {
            Text("Craft surfaces Glance opens for the focused Worktree. Overlay peeks; External Focus / End.")
                .font(.callout)
                .foregroundStyle(ghosttyTheme.secondaryText)
                .padding(.bottom, 4)

            ActivitySettingsSection(
                title: "Shell",
                systemImage: "terminal",
                blurb: "Background CLIs and Overlay Terminal. Always Overlay — peek and hide without quitting.",
                badge: "Overlay"
            ) {
                ShellActivityConfigurator(command: $preferences.preferences.shellCommand)
            }

            ActivitySettingsSection(
                title: "Editor",
                systemImage: "pencil",
                blurb: "Open Editor from Glance or ⌘E. Choose TUI for the full peek/hide experience.",
                badge: nil
            ) {
                ActivityPresentationConfigurator(
                    presentation: globalEditorPresentationBinding,
                    command: $preferences.preferences.editorCommand,
                    bundleID: $preferences.preferences.editorBundleID,
                    commandPlaceholder: "vi · $EDITOR",
                    commandDetail: "Empty uses $VISUAL / $EDITOR, then vi.",
                    bundlePlaceholder: ActivityDefaults.editorBundleID,
                    bundleDetail: "Folder-capable: Cursor, VS Code, Zed, Xcode, Sublime, JetBrains. TextEdit launches only."
                )
            }

            ActivitySettingsSection(
                title: "Files",
                systemImage: "folder",
                blurb: "Open Files from Glance. Finder is the stock External default.",
                badge: nil
            ) {
                ActivityPresentationConfigurator(
                    presentation: $preferences.preferences.fileManagerPresentation,
                    command: $preferences.preferences.fileManagerCommand,
                    bundleID: $preferences.preferences.fileManagerBundleID,
                    commandPlaceholder: "Command",
                    commandDetail: "Empty opens a bare shell Overlay in the Worktree.",
                    bundlePlaceholder: ActivityDefaults.fileManagerBundleID,
                    bundleDetail: "Stock default is Finder."
                )
            }

            if let lastError = preferences.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Editor / Files (Global bindings)

    private var resolvedGlobalEditorPresentation: EditorPresentation {
        preferences.preferences.editorPresentation
            ?? preferences.effective.editorPresentation
    }

    private var globalEditorPresentationBinding: Binding<EditorPresentation> {
        Binding(
            get: { resolvedGlobalEditorPresentation },
            set: { newValue in
                let wasOverlay = resolvedGlobalEditorPresentation == .terminalOverlay
                preferences.preferences.editorPresentation = newValue
                if newValue == .externalApp {
                    if preferences.preferences.editorBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        preferences.preferences.editorBundleID = ActivityDefaults.editorBundleID
                    }
                    if wasOverlay, !preferences.preferences.hasSeenExternalEditorReminder {
                        showExternalEditorReminder = true
                    }
                }
            }
        )
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

                SettingsSection(title: "Tools") {
                    ActivitySettingsSection(
                        title: "Shell",
                        systemImage: "terminal",
                        blurb: "Override Global Shell default. Always Overlay.",
                        badge: "Overlay"
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            ShellActivityConfigurator(
                                command: Binding(
                                    get: {
                                        draftOverrides.shellCommand
                                            ?? preferences.preferences.shellCommand
                                    },
                                    set: { draftOverrides.shellCommand = $0 }
                                ),
                                detail: draftOverrides.shellCommand == nil
                                    ? "Showing Global. Edit to override for this Workspace."
                                    : "Empty opens a login shell in the Worktree."
                            )
                            if draftOverrides.shellCommand != nil {
                                Button("Inherit Global") {
                                    draftOverrides.shellCommand = nil
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }
                    }

                    ActivitySettingsSection(
                        title: "Editor",
                        systemImage: "pencil",
                        blurb: "Empty inherits Global Editor Presentation and value.",
                        badge: nil
                    ) {
                        OptionalActivityPresentationConfigurator(
                            presentation: Binding(
                                get: { draftOverrides.editorPresentation },
                                set: { draftOverrides.editorPresentation = $0 }
                            ),
                            command: Binding(
                                get: { draftOverrides.editorCommand },
                                set: { draftOverrides.editorCommand = $0 }
                            ),
                            bundleID: Binding(
                                get: { draftOverrides.editorBundleID },
                                set: { draftOverrides.editorBundleID = $0 }
                            ),
                            resolvedPresentation: resolvedWorkspaceEditorPresentation,
                            commandPlaceholder: "Command",
                            commandDetail: "Empty inherits Global Editor command.",
                            bundlePlaceholder: ActivityDefaults.editorBundleID,
                            bundleDetail: "Empty inherits Global bundle id."
                        )
                    }

                    ActivitySettingsSection(
                        title: "Files",
                        systemImage: "folder",
                        blurb: "Empty inherits Global Files Presentation and value.",
                        badge: nil
                    ) {
                        OptionalActivityPresentationConfigurator(
                            presentation: Binding(
                                get: { draftOverrides.fileManagerPresentation },
                                set: { draftOverrides.fileManagerPresentation = $0 }
                            ),
                            command: Binding(
                                get: { draftOverrides.fileManagerCommand },
                                set: { draftOverrides.fileManagerCommand = $0 }
                            ),
                            bundleID: Binding(
                                get: { draftOverrides.fileManagerBundleID },
                                set: { draftOverrides.fileManagerBundleID = $0 }
                            ),
                            resolvedPresentation: resolvedWorkspaceFileManagerPresentation,
                            commandPlaceholder: "Command",
                            commandDetail: "Empty inherits Global file manager command.",
                            bundlePlaceholder: ActivityDefaults.fileManagerBundleID,
                            bundleDetail: "Empty inherits Global bundle id."
                        )
                    }
                }

                SettingsSection(title: "Control") {
                    SettingsCard {
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

    /// Resolve from draft + Global (not focused Workspace Effective) so Settings for any Workspace is correct.
    private var resolvedWorkspaceEditorPresentation: EditorPresentation {
        if let override = draftOverrides.editorPresentation {
            return override
        }
        if let global = preferences.preferences.editorPresentation {
            return global
        }
        let configured = draftOverrides.editorCommand ?? preferences.preferences.editorCommand
        return EditorCommandResolver.presentation(
            forCommand: EditorCommandResolver.resolveCommand(configured: configured)
        )
    }

    private var resolvedWorkspaceFileManagerPresentation: EditorPresentation {
        draftOverrides.fileManagerPresentation
            ?? preferences.preferences.fileManagerPresentation
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
        case .globalTools:
            selection = .globalTools
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
    case globalTools
    case globalCommands
    case workspaceSettings(String)
    case workspaceSecrets(String)

    var id: String {
        switch self {
        case .globalGeneral: return "g-general"
        case .globalTools: return "g-tools"
        case .globalCommands: return "g-commands"
        case .workspaceSettings(let id): return "wo-\(id)"
        case .workspaceSecrets(let id): return "ws-\(id)"
        }
    }

    var title: String {
        switch self {
        case .globalGeneral: return "General"
        case .globalTools: return "Tools"
        case .globalCommands: return "Shortcuts"
        case .workspaceSettings: return "Settings"
        case .workspaceSecrets: return "Secret Store"
        }
    }

    var systemImage: String {
        switch self {
        case .globalGeneral: return "gearshape"
        case .globalTools: return "wrench.and.screwdriver"
        case .globalCommands: return "keyboard"
        case .workspaceSettings: return "slider.horizontal.3"
        case .workspaceSecrets: return "key"
        }
    }

    static var globalItems: [SettingsNavItem] {
        [.globalGeneral, .globalTools, .globalCommands]
    }
}
