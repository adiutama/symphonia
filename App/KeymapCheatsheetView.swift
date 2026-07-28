import AppKit
import SwiftUI

/// Live Operator cheatsheet built from `KeymapBindings` + `CommandRegistry` (not docs).
/// Toggle with ⌘⇧/ / Help → Keymap / Command Center (`kh`).
struct KeymapCheatsheetView: View {
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme
    @EnvironmentObject private var commandRegistry: CommandRegistry
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var settingsNavigation: SettingsNavigation

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("System", rows: KeymapBindings.systemWindowRows.map {
                        (title: $0.title, display: $0.display)
                    })
                    section("Global", rows: globalRows)
                    Text("Worktree cycle includes Main. Leader: \(leaderDisplay).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    section("Command Center chrome", rows: KeymapBindings.commandCenterChrome.map {
                        (title: $0.title, display: $0.display)
                    })
                    section("Command Center–only", rows: ccOnlyRows)
                    section("Sequences", rows: sequenceRows)

                    Text("Sequences respect Settings → Shortcuts overrides.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 520)
        .background(ghosttyTheme.panel)
        .onAppear { settingsNavigation.keymapDidAppear() }
        .onDisappear { settingsNavigation.keymapDidDisappear() }
    }

    private var header: some View {
        HStack {
            Text("Keymap")
                .font(.headline)
            Spacer()
            Text("⌘⇧/")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Button("Done") {
                settingsNavigation.closeKeymap()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(ghosttyTheme.sidebar)
    }

    private var leaderDisplay: String {
        LeaderKeyBinding.parse(preferences.effective.leaderKey)?.displaySymbolString
            ?? preferences.effective.leaderKey
    }

    private var globalRows: [(title: String, display: String)] {
        var rows: [(title: String, display: String)] = [
            (title: "Command Center", display: leaderDisplay),
        ]
        rows.append(contentsOf: KeymapBindings.globalChords.map { chord in
            (title: title(for: chord), display: chord.display)
        })
        return rows
    }

    private var ccOnlyRows: [(title: String, display: String)] {
        KeymapBindings.commandCenterOnlyChords.map { chord in
            (title: title(for: chord), display: chord.display)
        }
    }

    /// Effective sequences from the live registry (overrides applied).
    private var sequenceRows: [(title: String, display: String)] {
        let overrides = preferences.preferences.commandBindings
        return commandRegistry.allCommands.compactMap { command in
            guard let seq = CommandBindingResolver.sequence(for: command, overrides: overrides)
            else { return nil }
            return (title: command.title, display: seq)
        }
        .sorted { lhs, rhs in
            if lhs.display.count != rhs.display.count {
                return lhs.display.count < rhs.display.count
            }
            return lhs.display.localizedCaseInsensitiveCompare(rhs.display) == .orderedAscending
        }
    }

    private func title(for chord: KeymapBindings.Chord) -> String {
        if let command = commandRegistry.allCommands.first(where: { $0.action == chord.action }) {
            return command.title
        }
        return chord.titleFallback
    }

    private func section(_ title: String, rows: [(title: String, display: String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider().opacity(0.35)
                    }
                    HStack {
                        Text(row.title)
                            .font(.body)
                        Spacer(minLength: 12)
                        Text(row.display)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
