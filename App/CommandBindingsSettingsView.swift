import SwiftUI

/// Settings → Global → Commands: edit per-Command alias/shortcut overrides and surface
/// duplicate-binding conflicts across the whole registry (ADR 0021 CC.4).
///
/// Meant to be embedded inside `PreferencesSettingsView`'s `globalForm` (Sections only —
/// no own `Form`/padding) so it gets the existing Save / Reload / Reset chrome for free.
struct CommandBindingsSettingsView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var commandRegistry: CommandRegistry

    @State private var searchText: String = ""

    var body: some View {
        Group {
            Section("Commands") {
                TextField("Search", text: $searchText, prompt: Text("Filter by title or id"))
                Text(
                    "Aliases are comma-separated free text (Command Center matches title or any " +
                    "alias). Shortcut fires when Command Center's filter is empty. An emptied " +
                    "field is saved as an explicit override (e.g. \"no aliases\") — use Reset to " +
                    "clear the override and fall back to the Command's own defaults."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !conflicts.isEmpty {
                Section("Conflicts") {
                    ForEach(conflicts) { conflict in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(conflict.label, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text(conflict.commandTitles.joined(separator: " ↔ "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ForEach(filteredGroups, id: \.group) { entry in
                Section(entry.group) {
                    ForEach(entry.commands) { command in
                        row(for: command)
                    }
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for command: Command) -> some View {
        let hasOverride = preferences.preferences.commandBindings[command.id] != nil
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title)
                        .fontWeight(.medium)
                    Text(command.id)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                if hasOverride {
                    Button("Reset") {
                        preferences.preferences.commandBindings.removeValue(forKey: command.id)
                    }
                    .font(.caption)
                }
            }
            HStack(spacing: 8) {
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

                TextField(
                    "Shortcut",
                    text: shortcutBinding(for: command),
                    prompt: Text(command.defaultShortcut ?? "none")
                )
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 90)
            }
        }
        .padding(.vertical, 2)
    }

    /// `nil` override → shows empty text (placeholder shows defaults). Typing writes a
    /// (possibly empty) explicit override string, matching `CommandBindingOverride` /
    /// `CommandBindingResolver` semantics from CC.3 — Reset above is the only way back
    /// to "use the Command's defaults" once an override key exists.
    private func aliasesBinding(for command: Command) -> Binding<String> {
        Binding(
            get: { preferences.preferences.commandBindings[command.id]?.aliases ?? "" },
            set: { newValue in
                var override = preferences.preferences.commandBindings[command.id] ?? CommandBindingOverride()
                override.aliases = newValue
                preferences.preferences.commandBindings[command.id] = override
            }
        )
    }

    private func shortcutBinding(for command: Command) -> Binding<String> {
        Binding(
            get: { preferences.preferences.commandBindings[command.id]?.shortcut ?? "" },
            set: { newValue in
                var override = preferences.preferences.commandBindings[command.id] ?? CommandBindingOverride()
                override.shortcut = newValue
                preferences.preferences.commandBindings[command.id] = override
            }
        )
    }

    // MARK: - Grouping / filtering

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

    private var filteredGroups: [(group: String, commands: [Command])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return groupedCommands }
        return groupedCommands.compactMap { entry in
            let matches = entry.commands.filter {
                $0.title.lowercased().contains(query) || $0.id.lowercased().contains(query)
            }
            return matches.isEmpty ? nil : (group: entry.group, commands: matches)
        }
    }

    // MARK: - Conflicts

    private struct Conflict: Identifiable {
        let id: String
        let label: String
        let commandTitles: [String]
    }

    /// Non-blocking: Commands sharing an effective alias (case-insensitive, trimmed) or a
    /// non-empty effective shortcut, computed over the *whole* registry regardless of the
    /// search filter above (ADR 0021 CC.4 — "clear error", not a hard save block).
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
