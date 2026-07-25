import SwiftUI

/// Secret Store editor (Settings → Workspace → Secret Store).
struct SecretStoreScaffoldView: View {
    @EnvironmentObject private var workspaces: WorkspaceController
    @EnvironmentObject private var secrets: SecretStoreController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Secret Store")
                .font(.headline)

            if workspaces.current == nil {
                Text("Select a Workspace to manage Env Vars.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                groupsSection
                varsSection
                addForms
            }

            if let current = workspaces.current {
                Text("File: \(SymphoniaPaths.workspaceSecretsFile(in: current.dataDirURL).path)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            let enabled = secrets.enabledEnvironment
            Text("Enabled for spawn: \(enabled.isEmpty ? "(none)" : enabled.map(\.key).joined(separator: ", "))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let error = secrets.lastError {
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

    // MARK: - Groups

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Secret Groups")
                .font(.subheadline)
                .fontWeight(.semibold)

            if secrets.document.groups.isEmpty {
                Text("No groups — vars can be ungrouped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(secrets.document.groups) { group in
                    HStack(spacing: 8) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { group.enabled },
                                set: { secrets.setGroupEnabled(group.id, enabled: $0) }
                            )
                        )
                        .labelsHidden()
                        .help("Group Enabled — gates member Env Vars")

                        TextField(
                            "name",
                            text: Binding(
                                get: { group.name },
                                set: { secrets.renameGroup(group.id, name: $0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                        Button("Delete", role: .destructive) {
                            secrets.deleteGroup(group.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Vars

    private var varsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Env Vars")
                .font(.subheadline)
                .fontWeight(.semibold)

            if secrets.document.vars.isEmpty {
                Text("None yet — add one below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(secrets.document.vars) { envVar in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { envVar.enabled },
                                    set: { secrets.setVarEnabled(envVar.id, enabled: $0) }
                                )
                            )
                            .labelsHidden()
                            .help("Env Var Enabled")

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
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 100, maxWidth: 160)

                            SecureField(
                                "value",
                                text: Binding(
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
                            )
                            .textFieldStyle(.roundedBorder)

                            Picker(
                                "group",
                                selection: Binding(
                                    get: { envVar.groupId ?? "" },
                                    set: { raw in
                                        let groupId = raw.isEmpty ? nil : raw
                                        secrets.updateVar(
                                            envVar.id,
                                            key: envVar.key,
                                            value: envVar.value,
                                            groupId: groupId
                                        )
                                    }
                                )
                            ) {
                                Text("(ungrouped)").tag("")
                                ForEach(secrets.document.groups) { group in
                                    Text(group.name).tag(group.id)
                                }
                            }
                            .frame(maxWidth: 140)

                            Button("Delete", role: .destructive) {
                                secrets.deleteVar(envVar.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Add forms

    private var addForms: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("new group name", text: $secrets.draftGroupName)
                    .textFieldStyle(.roundedBorder)
                Button("Add Group") {
                    secrets.addGroup()
                }
                .disabled(secrets.draftGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack {
                TextField("KEY", text: $secrets.draftVarKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 100, maxWidth: 160)
                SecureField("value", text: $secrets.draftVarValue)
                    .textFieldStyle(.roundedBorder)
                Picker(
                    "group",
                    selection: Binding(
                        get: { secrets.draftVarGroupId ?? "" },
                        set: { secrets.draftVarGroupId = $0.isEmpty ? nil : $0 }
                    )
                ) {
                    Text("(ungrouped)").tag("")
                    ForEach(secrets.document.groups) { group in
                        Text(group.name).tag(group.id)
                    }
                }
                .frame(maxWidth: 140)
                Button("Add Env Var") {
                    secrets.addVar()
                }
                .disabled(secrets.draftVarKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Reload") {
                    secrets.reload()
                }
            }
        }
    }
}
