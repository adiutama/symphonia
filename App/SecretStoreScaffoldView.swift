import SwiftUI

/// Secret Store editor — table/grid over `secrets.toml` (T.6).
struct SecretStoreScaffoldView: View {
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var secrets: SecretStoreController

    @State private var revealValues = false
    @State private var filter = ""

    var body: some View {
        Group {
            if workspaces.current == nil {
                ContentUnavailableView(
                    "No Workspace",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Select a Workspace to manage Env Vars.")
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    toolbar
                    groupsBar
                    varsTable
                    addVarRow
                    footer
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Secret Store")
                .font(.title3.weight(.semibold))

            Spacer()

            Toggle("Reveal values", isOn: $revealValues)
                .toggleStyle(.checkbox)
                .help("Show Env Var values in plain text")

            Button("Reload") {
                secrets.reload()
            }
        }
    }

    // MARK: - Groups

    private var groupsBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Groups")
                    .font(.subheadline.weight(.semibold))
                Text("Off = member vars stay out of spawn env")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if secrets.document.groups.isEmpty {
                Text("No groups — vars can stay ungrouped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowGroups(
                    groups: secrets.document.groups,
                    onToggle: { secrets.setGroupEnabled($0, enabled: $1) },
                    onRename: { secrets.renameGroup($0, name: $1) },
                    onDelete: { secrets.deleteGroup($0) }
                )
            }

            HStack(spacing: 8) {
                TextField("New group name", text: $secrets.draftGroupName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button("Add Group") {
                    secrets.addGroup()
                }
                .disabled(secrets.draftGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Vars table

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

    private var varsTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Env Vars")
                    .font(.subheadline.weight(.semibold))
                TextField("Filter key or group", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Spacer()
                Text("\(filteredVars.count) shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if secrets.document.vars.isEmpty {
                Text("No Env Vars yet — add one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else if filteredVars.isEmpty {
                Text("No matches for “\(filter)”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
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
                            "KEY",
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
                                TextField(
                                    "value",
                                    text: valueBinding(envVar)
                                )
                            } else {
                                SecureField(
                                    "value",
                                    text: valueBinding(envVar)
                                )
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
                .frame(minHeight: 180)
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

    // MARK: - Add row

    private var addVarRow: some View {
        HStack(spacing: 8) {
            TextField("KEY", text: $secrets.draftVarKey)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .frame(minWidth: 100, maxWidth: 160)

            Group {
                if revealValues {
                    TextField("value", text: $secrets.draftVarValue)
                } else {
                    SecureField("value", text: $secrets.draftVarValue)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())

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
            .frame(maxWidth: 140)

            Button("Add") {
                secrets.addVar()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(secrets.draftVarKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            let enabled = secrets.enabledEnvironment
            Text("Spawn env: \(enabled.isEmpty ? "(none)" : enabled.map(\.key).sorted().joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let current = workspaces.current {
                Text(SymphoniaPaths.workspaceSecretsFile(in: current.dataDirURL).path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let error = secrets.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }
}

/// Compact editable chips for Secret Groups (keeps the Env Vars table as the main grid).
private struct FlowGroups: View {
    let groups: [SecretGroup]
    let onToggle: (String, Bool) -> Void
    let onRename: (String, String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(groups) { group in
                HStack(spacing: 8) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { group.enabled },
                            set: { onToggle(group.id, $0) }
                        )
                    )
                    .labelsHidden()
                    .help("Group On")

                    TextField(
                        "name",
                        text: Binding(
                            get: { group.name },
                            set: { onRename(group.id, $0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                    Button(role: .destructive) {
                        onDelete(group.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete group (vars become ungrouped)")

                    Spacer(minLength: 0)
                }
            }
        }
    }
}
