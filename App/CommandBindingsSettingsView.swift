import SwiftUI

/// Settings → Global → Shortcuts: Name | Sequence | Hotkey.
///
/// - **Sequence** — editable Normal-mode chord (persisted overrides).
/// - **Hotkey** — fixed ⌘/⌃ chords from `KeymapBindings` (read-only). Leader is the
///   exception: it is editable Global Setting.
///
/// No aliases, no enable checkboxes, no per-row clear buttons.
struct ShortcutsSettingsView: View {
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var commandRegistry: CommandRegistry
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    @State private var search = ""
    @State private var expandedGroups: Set<String> = []

    private let sequenceColumnWidth: CGFloat = 100
    private let hotkeyColumnWidth: CGFloat = 140
    private let rowHorizontalPadding: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !conflicts.isEmpty {
                conflictsBanner
            }

            table
        }
        .onAppear {
            expandedGroups = Set(allGroups.map(\.id))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcuts")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(ghosttyTheme.foreground)
                Text("Sequences are editable. Hotkeys are fixed app chords.")
                    .font(.caption)
                    .foregroundStyle(ghosttyTheme.secondaryText)
            }

            Spacer(minLength: 8)

            Button {
                resetAll()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body.weight(.medium))
                    .frame(width: 28, height: 28)
                    .background(ghosttyTheme.control)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Reset all shortcuts to defaults")
            .disabled(!hasAnyOverride)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ghosttyTheme.secondaryText)
                TextField("Search…", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 200)
            .background(ghosttyTheme.control)
            .clipShape(Capsule())
        }
    }

    private var conflictsBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(conflicts) { conflict in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conflict.label)
                            .font(.caption.weight(.semibold))
                        Text(conflict.commandTitles.joined(separator: " ↔ "))
                            .font(.caption)
                            .foregroundStyle(ghosttyTheme.secondaryText)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Table

    private var table: some View {
        ScrollView {
            VStack(spacing: 0) {
                columnHeaders
                tableDivider

                ForEach(visibleGroups, id: \.id) { group in
                    groupBlock(group)
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(ghosttyTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            headerLabel("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            headerLabel("Sequence", detail: "editable")
                .frame(width: sequenceColumnWidth, alignment: .leading)
            headerLabel("Hotkey", detail: "fixed")
                .frame(width: hotkeyColumnWidth, alignment: .leading)
        }
        .padding(.horizontal, rowHorizontalPadding)
        .padding(.vertical, 10)
    }

    private func headerLabel(_ title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ghosttyTheme.secondaryText)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(ghosttyTheme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupBlock(_ group: ShortcutGroup) -> some View {
        let isExpanded = expandedGroups.contains(group.id)
            || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 0) {
            tableDivider
            Button {
                toggleGroup(group.id)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ghosttyTheme.secondaryText)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .frame(width: 12)
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ghosttyTheme.foreground)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, rowHorizontalPadding)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(group.rows) { row in
                    tableDivider
                    tableRow(row)
                }
            }
        }
    }

    private func tableRow(_ row: ShortcutRow) -> some View {
        HStack(spacing: 0) {
            Text(row.title)
                .font(.body)
                .foregroundStyle(ghosttyTheme.foreground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            sequenceCell(for: row)
                .frame(width: sequenceColumnWidth, alignment: .leading)

            hotkeyCell(for: row)
                .frame(width: hotkeyColumnWidth, alignment: .leading)
        }
        .padding(.horizontal, rowHorizontalPadding)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func sequenceCell(for row: ShortcutRow) -> some View {
        switch row.kind {
        case .leader:
            placeholderCell("—")
        case .command(let commandId, let allowsSequence):
            if allowsSequence {
                SequenceRecordField(
                    sequence: sequenceBinding(for: commandId),
                    emptyLabel: "Record",
                    fillsWidth: true
                )
            } else {
                placeholderCell("—")
            }
        }
    }

    @ViewBuilder
    private func hotkeyCell(for row: ShortcutRow) -> some View {
        switch row.kind {
        case .leader:
            KeyChordField(chord: leaderBinding, emptyLabel: "Record", fillsWidth: true)
        case .command(let commandId, _):
            if let display = hotkeyDisplay(for: commandId) {
                Text(display)
                    .font(.body.monospaced())
                    .foregroundStyle(ghosttyTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .help("Fixed app hotkey — not editable. Use Sequence for Normal mode.")
                    .accessibilityLabel("Hotkey \(display), fixed")
            } else {
                placeholderCell("—")
            }
        }
    }

    private func hotkeyDisplay(for commandId: String) -> String? {
        guard let command = commandRegistry.command(id: commandId) else { return nil }
        return KeymapBindings.hotkeyDisplay(for: command.action)
    }

    private func placeholderCell(_ text: String) -> some View {
        Text(text)
            .font(.body.monospaced())
            .foregroundStyle(ghosttyTheme.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }

    private var tableDivider: some View {
        SoftHairline(horizontalPadding: 8)
    }

    // MARK: - Data

    private struct ShortcutGroup: Identifiable {
        let id: String
        let title: String
        let rows: [ShortcutRow]
    }

    private struct ShortcutRow: Identifiable {
        enum Kind {
            case leader
            /// `allowsSequence` is false when the Command ships with an explicit empty sequence.
            case command(commandId: String, allowsSequence: Bool)
        }

        let id: String
        let title: String
        let kind: Kind
        let searchText: String
    }

    private var allGroups: [ShortcutGroup] {
        var groups: [ShortcutGroup] = [
            ShortcutGroup(
                id: "general",
                title: "General",
                rows: [
                    ShortcutRow(
                        id: "leader",
                        title: "Command Center",
                        kind: .leader,
                        searchText: "command center leader palette"
                    ),
                ]
            ),
        ]

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

        for key in order {
            let commands = buckets[key] ?? []
            let rows = commands.map { command -> ShortcutRow in
                // nil → title-derived sequence allowed; "" → explicitly none (ADR 2026-07-25-0022-keyboard-keymap).
                let allowsSequence = command.defaultSequence.map { !$0.isEmpty } ?? true
                return ShortcutRow(
                    id: command.id,
                    title: command.title,
                    kind: .command(commandId: command.id, allowsSequence: allowsSequence),
                    searchText: "\(command.title) \(command.id) \(command.group ?? "")"
                )
            }
            groups.append(ShortcutGroup(id: key.lowercased(), title: key, rows: rows))
        }
        return groups
    }

    private var visibleGroups: [ShortcutGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allGroups }
        return allGroups.compactMap { group in
            let rows = group.rows.filter {
                $0.searchText.lowercased().contains(query)
                    || $0.title.lowercased().contains(query)
            }
            guard !rows.isEmpty else { return nil }
            return ShortcutGroup(id: group.id, title: group.title, rows: rows)
        }
    }

    private var hasAnyOverride: Bool {
        isLeaderModified || !preferences.preferences.commandBindings.isEmpty
    }

    private var isLeaderModified: Bool {
        let current = preferences.preferences.leaderKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return current != GlobalPreferences.default.leaderKey
    }

    // MARK: - Bindings

    private var leaderBinding: Binding<String> {
        Binding(
            get: { preferences.preferences.leaderKey },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                preferences.preferences.leaderKey = trimmed.isEmpty
                    ? GlobalPreferences.default.leaderKey
                    : trimmed
            }
        )
    }

    private func sequenceBinding(for commandId: String) -> Binding<String> {
        Binding(
            get: {
                guard let command = commandRegistry.command(id: commandId) else { return "" }
                return CommandBindingResolver.sequence(
                    for: command,
                    overrides: preferences.preferences.commandBindings
                ) ?? ""
            },
            set: { newValue in
                guard let command = commandRegistry.command(id: commandId) else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let defaultSeq = CommandBindingResolver.sequence(for: command, overrides: [:])
                var override = preferences.preferences.commandBindings[commandId]
                    ?? CommandBindingOverride()

                if trimmed.isEmpty {
                    override.sequence = ""
                } else if trimmed == defaultSeq {
                    override.sequence = nil
                } else {
                    override.sequence = CommandSequence.sanitize(trimmed)
                }
                persist(commandId, override)
            }
        )
    }

    private func persist(_ commandId: String, _ override: CommandBindingOverride) {
        if override.sequence == nil {
            preferences.preferences.commandBindings.removeValue(forKey: commandId)
        } else {
            preferences.preferences.commandBindings[commandId] = CommandBindingOverride(
                sequence: override.sequence
            )
        }
    }

    // MARK: - Actions

    private func toggleGroup(_ id: String) {
        if expandedGroups.contains(id) {
            expandedGroups.remove(id)
        } else {
            expandedGroups.insert(id)
        }
    }

    private func resetAll() {
        preferences.preferences.leaderKey = GlobalPreferences.default.leaderKey
        preferences.preferences.commandBindings = [:]
    }

    // MARK: - Conflicts

    private struct Conflict: Identifiable {
        let id: String
        let label: String
        let commandTitles: [String]
    }

    private var conflicts: [Conflict] {
        let overrides = preferences.preferences.commandBindings
        var sequenceMap: [String: [String]] = [:]
        for command in commandRegistry.allCommands {
            if let sequence = CommandBindingResolver.sequence(for: command, overrides: overrides),
               let key = CommandBindingResolver.sequenceConflictKey(sequence)
            {
                sequenceMap[key, default: []].append(command.title)
            }
        }

        var result: [Conflict] = []
        for (sequence, titles) in sequenceMap where titles.count > 1 {
            result.append(Conflict(id: "seq-\(sequence)", label: "Sequence \"\(sequence)\"", commandTitles: titles))
        }
        return result.sorted { $0.label < $1.label }
    }
}
