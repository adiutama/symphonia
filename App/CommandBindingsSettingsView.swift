import SwiftUI

/// Settings → Global → Commands: edit per-Command alias/shortcut overrides and surface
/// duplicate-binding conflicts across the whole registry (ADR 0021 CC.4).
///
/// Uses Settings chrome cards. Autosave is owned by the parent via Global preferences debounce.
struct CommandBindingsSettingsView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var commandRegistry: CommandRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(
                "Aliases are comma-separated free text (Command Center matches title or any " +
                "alias). Shortcut fires when Command Center's filter is empty. An emptied " +
                "field is saved as an explicit override — use Reset to fall back to defaults."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if !conflicts.isEmpty {
                SettingsSection(title: "Conflicts") {
                    SettingsCard {
                        ForEach(Array(conflicts.enumerated()), id: \.element.id) { index, conflict in
                            if index > 0 { SettingsRowDivider() }
                            SettingsRow(title: conflict.label, description: conflict.commandTitles.joined(separator: " ↔ ")) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }

            ForEach(groupedCommands, id: \.group) { entry in
                SettingsSection(title: entry.group) {
                    SettingsCard {

                        ForEach(Array(entry.commands.enumerated()), id: \.element.id) { index, command in
                            if index > 0 { SettingsRowDivider() }
                            commandRow(command)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func commandRow(_ command: Command) -> some View {
        let changed = hasChangedOverride(for: command)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title)
                        .font(.body.weight(.medium))
                    Text(command.id)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Button("Reset") {
                    preferences.preferences.commandBindings.removeValue(forKey: command.id)
                }
                .font(.caption)
                .opacity(changed ? 1 : 0)
                .disabled(!changed)
                .accessibilityHidden(!changed)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aliases")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(
                        "Aliases",
                        text: aliasesBinding(for: command),
                        prompt: Text(
                            command.defaultAliases.isEmpty
                                ? "none"
                                : command.defaultAliases.joined(separator: ", ")
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Shortcut")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    TextField(
                        "Shortcut",
                        text: shortcutBinding(for: command),
                        prompt: Text(command.defaultShortcut ?? "none")
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func hasChangedOverride(for command: Command) -> Bool {
        guard let override = preferences.preferences.commandBindings[command.id] else {
            return false
        }
        return override.aliases != nil || override.shortcut != nil
    }

    private func aliasesBinding(for command: Command) -> Binding<String> {
        Binding(
            get: { preferences.preferences.commandBindings[command.id]?.aliases ?? "" },
            set: { newValue in
                let existing = preferences.preferences.commandBindings[command.id]
                if existing == nil, newValue.isEmpty { return }
                if existing?.aliases == nil, newValue.isEmpty { return }
                var override = existing ?? CommandBindingOverride()
                override.aliases = newValue
                preferences.preferences.commandBindings[command.id] = override
            }
        )
    }

    private func shortcutBinding(for command: Command) -> Binding<String> {
        Binding(
            get: { preferences.preferences.commandBindings[command.id]?.shortcut ?? "" },
            set: { newValue in
                let existing = preferences.preferences.commandBindings[command.id]
                if existing == nil, newValue.isEmpty { return }
                if existing?.shortcut == nil, newValue.isEmpty { return }
                var override = existing ?? CommandBindingOverride()
                override.shortcut = newValue
                preferences.preferences.commandBindings[command.id] = override
            }
        )
    }

    private var groupedCommands: [(group: String, commands: [Command])] {
        var order: [String] = []
        var buckets: [String: [Command]] = [:]
        for command in commandRegistry.allCommands {
            let key = command.group ?? "Other"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key, default: []].append(command)
        }
        return order.map { (group: $0, commands: buckets[$0] ?? []) }
    }

    private struct Conflict: Identifiable {
        let id: String
        let label: String
        let commandTitles: [String]
    }

    private var conflicts: [Conflict] {
        let overrides = preferences.preferences.commandBindings
        let all = commandRegistry.allCommands

        var aliasMap: [String: [String]] = [:]
        var shortcutMap: [String: [String]] = [:]
        for command in all {
            for alias in CommandBindingResolver.aliases(for: command, overrides: overrides) {
                let key = alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !key.isEmpty else { continue }
                aliasMap[key, default: []].append(command.title)
            }
            if let shortcut = CommandBindingResolver.shortcut(for: command, overrides: overrides) {
                let key = shortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !key.isEmpty else { continue }
                shortcutMap[key, default: []].append(command.title)
            }
        }

        var result: [Conflict] = []
        for (alias, titles) in aliasMap where titles.count > 1 {
            result.append(Conflict(id: "alias-\(alias)", label: "Alias \"\(alias)\"", commandTitles: titles))
        }
        for (shortcut, titles) in shortcutMap where titles.count > 1 {
            result.append(Conflict(id: "shortcut-\(shortcut)", label: "Shortcut \"\(shortcut)\"", commandTitles: titles))
        }
        return result.sorted { $0.label < $1.label }
    }
}
