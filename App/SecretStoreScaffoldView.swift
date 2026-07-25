import SwiftUI

/// Secret Store editor — `secrets.toml` (T.6), styled with Settings chrome (page → section → card).
///
/// Scoped to a Workspace Data Dir so Settings can edit without switching Main (L3).
struct SecretStoreScaffoldView: View {
    let workspace: WorkspaceSummary

    @EnvironmentObject private var workspaces: WorkspaceController
    /// App-wide spawn-bound store (Main’s current Workspace).
    @EnvironmentObject private var spawnSecrets: SecretStoreController
    @StateObject private var secrets: SecretStoreController

    @State private var revealValues = false
    @State private var filter = ""

    init(workspace: WorkspaceSummary) {
        self.workspace = workspace
        _secrets = StateObject(wrappedValue: SecretStoreController(dataDirURL: workspace.dataDirURL))
    }

    var body: some View {
        SettingsPage(title: "Secret Store") {
            Text(workspace.slug)
                .font(.caption)
                .foregroundStyle(.secondary)

            optionsSection
            groupsSection
            envVarsSection
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: secrets.revision) { _, _ in
            syncSpawnSecretsIfEditingCurrent()
        }
    }

    private func syncSpawnSecretsIfEditingCurrent() {
        guard let current = workspaces.current,
              current.dataDirURL.standardizedFileURL == workspace.dataDirURL.standardizedFileURL
        else { return }
        spawnSecrets.reload()
    }

    // MARK: - Options

    private var optionsSection: some View {
        SettingsSection(title: "Options") {
            SettingsCard {
                SettingsRow(
                    title: "Reveal values",
                    description: "Show Env Var values in plain text."
                ) {
                    Toggle("", isOn: $revealValues)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingsRowDivider()
                SettingsRow(
                    title: "Reload",
                    description: "Re-read secrets.toml from disk."
                ) {
                    Button("Reload") {
                        secrets.reload()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Groups

    private var groupsSection: some View {
        SettingsSection(title: "Groups") {
            SettingsCard {
                if secrets.document.groups.isEmpty {
                    SettingsRow(
                        title: "No groups yet",
                        description: "Groups toggle sets of Env Vars in spawn env. Vars can stay ungrouped."
                    ) {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(secrets.document.groups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { SettingsRowDivider() }
                        groupRow(group)
                    }
                    SettingsRowDivider()
                }

                SettingsRow(
                    title: "New group",
                    description: "Name a group, then assign Env Vars to it."
                ) {
                    HStack(spacing: 8) {
                        TextField("Name", text: $secrets.draftGroupName)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 120, idealWidth: 160)
                            .frame(maxWidth: 200)
                        Button("Add") {
                            secrets.addGroup()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(secrets.draftGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func groupRow(_ group: SecretGroup) -> some View {
        SettingsRow(
            title: group.name.isEmpty ? "Untitled" : group.name,
            description: group.enabled ? "On — member vars can enter spawn env." : "Off — member vars stay out of spawn env."
        ) {
            HStack(spacing: 8) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { group.enabled },
                        set: { secrets.setGroupEnabled(group.id, enabled: $0) }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .help("Group On")

                TextField(
                    "Name",
                    text: Binding(
                        get: { group.name },
                        set: { secrets.renameGroup(group.id, name: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)

                Button(role: .destructive) {
                    secrets.deleteGroup(group.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete group (vars become ungrouped)")
            }
        }
    }

    // MARK: - Env Vars

    private var filteredVars: [EnvVar] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return secrets.document.vars }
        return secrets.document.vars.filter { envVar in
            if envVar.key.lowercased().contains(q) { return true }
            if let groupId = envVar.groupId,
               let name = secrets.document.groups.first(where: { $0.id == groupId })?.name,
               name.lowercased().contains(q)
            {
                return true
            }
            return false
        }
    }

    private var envVarsSection: some View {
        SettingsSection(title: "Env Vars") {
            SettingsCard {
                SettingsRow(
                    title: "Filter",
                    description: "\(filteredVars.count) shown"
                ) {
                    TextField("Key or group", text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 140, idealWidth: 200)
                        .frame(maxWidth: 260)
                }
                SettingsRowDivider()

                if secrets.document.vars.isEmpty {
                    SettingsRow(
                        title: "No Env Vars yet",
                        description: "Add one below."
                    ) {
                        EmptyView()
                    }
                } else if filteredVars.isEmpty {
                    SettingsRow(
                        title: "No matches",
                        description: "Nothing matches “\(filter)”."
                    ) {
                        EmptyView()
                    }
                } else {
                    Table(filteredVars, selection: $secrets.selectedVarId) {
                        TableColumn("On") { envVar in
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { envVar.enabled },
                                    set: { secrets.setVarEnabled(envVar.id, enabled: $0) }
                                )
                            )
                            .labelsHidden()
                            .help("Include when Enabled (and group On, if any)")
                        }
                        .width(min: 36, ideal: 44, max: 52)

                        TableColumn("Key") { envVar in
                            TextField(
                                "Key",
                                text: Binding(
                                    get: { envVar.key },
                                    set: { newKey in
                                        secrets.updateVar(
                                            envVar.id,
                                            key: newKey,
                                            value: envVar.value,
                                            groupId: envVar.groupId
                                        )
                                    }
                                )
                            )
                            .textFieldStyle(.plain)
                            .font(.body.monospaced())
                        }
                        .width(min: 100, ideal: 160)

                        TableColumn("Value") { envVar in
                            Group {
                                if revealValues {
                                    TextField("Value", text: valueBinding(envVar))
                                } else {
                                    SecureField("Value", text: valueBinding(envVar))
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.body.monospaced())
                        }
                        .width(min: 120, ideal: 240)

                        TableColumn("Group") { envVar in
                            Picker(
                                "",
                                selection: Binding(
                                    get: { envVar.groupId ?? "" },
                                    set: { raw in
                                        secrets.updateVar(
                                            envVar.id,
                                            key: envVar.key,
                                            value: envVar.value,
                                            groupId: raw.isEmpty ? nil : raw
                                        )
                                    }
                                )
                            ) {
                                Text("—").tag("")
                                ForEach(secrets.document.groups) { group in
                                    Text(group.name).tag(group.id)
                                }
                            }
                            .labelsHidden()
                        }
                        .width(min: 100, ideal: 140, max: 180)

                        TableColumn("") { envVar in
                            Button(role: .destructive) {
                                secrets.deleteVar(envVar.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete Env Var")
                        }
                        .width(36)
                    }
                    .frame(minHeight: 160)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)

                    SettingsRowDivider()
                }

                SettingsRow(
                    title: "Add Env Var",
                    description: "Key is required. Value can be empty."
                ) {
                    HStack(spacing: 8) {
                        TextField("Key", text: $secrets.draftVarKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .frame(width: 120)

                        Group {
                            if revealValues {
                                TextField("Value", text: $secrets.draftVarValue)
                            } else {
                                SecureField("Value", text: $secrets.draftVarValue)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .frame(minWidth: 100, idealWidth: 140)
                        .frame(maxWidth: 180)

                        Picker(
                            "Group",
                            selection: Binding(
                                get: { secrets.draftVarGroupId ?? "" },
                                set: { secrets.draftVarGroupId = $0.isEmpty ? nil : $0 }
                            )
                        ) {
                            Text("—").tag("")
                            ForEach(secrets.document.groups) { group in
                                Text(group.name).tag(group.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)

                        Button("Add") {
                            secrets.addVar()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [])
                        .disabled(secrets.draftVarKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func valueBinding(_ envVar: EnvVar) -> Binding<String> {
        Binding(
            get: { envVar.value },
            set: { newValue in
                secrets.updateVar(
                    envVar.id,
                    key: envVar.key,
                    value: newValue,
                    groupId: envVar.groupId
                )
            }
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            let enabled = secrets.enabledEnvironment
            Text(
                "Enabled for this Workspace: " +
                (enabled.isEmpty ? "(none)" : enabled.map(\.key).sorted().joined(separator: ", "))
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            if let error = secrets.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }
}
