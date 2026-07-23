import SwiftUI

/// Floating Command Mode palette with search/filter and keybind hints.
struct CommandModeView: View {
    @EnvironmentObject private var commandMode: CommandModeController
    @EnvironmentObject private var preferences: PreferencesController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            filterField
            Divider()
            itemList
            Divider()
            footer
        }
        .frame(width: 440)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }

    private var header: some View {
        HStack {
            Text(phaseTitle)
                .font(.headline)
            Spacer()
            Text(preferences.effective.leaderKey)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Button("Esc") {
                if !commandMode.filterQuery.isEmpty {
                    commandMode.setFilter("")
                } else if commandMode.phase == .root {
                    commandMode.dismiss()
                } else {
                    commandMode.run(.back)
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Dismiss Command Mode")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            Text(commandMode.filterQuery.isEmpty ? "Type to filter…" : commandMode.filterQuery)
                .font(.body.monospaced())
                .foregroundStyle(commandMode.filterQuery.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !commandMode.filterQuery.isEmpty {
                Text("⌫")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var phaseTitle: String {
        switch commandMode.phase {
        case .root: return "Command Mode"
        case .pickWorkspace: return "Switch Workspace"
        case .pickAgent: return "Focus session"
        case .pickBackground: return "Peek Overlay"
        }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if commandMode.items.isEmpty {
                        Text("No matches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    } else {
                        ForEach(Array(commandMode.items.enumerated()), id: \.element.id) { index, item in
                            Button {
                                commandMode.selectedIndex = index
                                commandMode.run(item.action)
                            } label: {
                                row(item: item, selected: index == commandMode.selectedIndex)
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
            .onChange(of: commandMode.selectedIndex) {
                let newValue = commandMode.selectedIndex
                guard commandMode.items.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(commandMode.items[newValue].id, anchor: .center)
                }
            }
        }
    }

    private func row(item: CommandModeItem, selected: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(selected ? .semibold : .regular))
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let keybind = item.keybind {
                Text(keybind)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else if selected {
                Text("↩")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.22) : Color.clear)
    }

    private var footer: some View {
        HStack {
            Text("↑↓ · ↩ · type to filter · keybinds when empty")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            if let info = commandMode.lastInfo {
                Text(info)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
