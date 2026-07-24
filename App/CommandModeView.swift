import SwiftUI

/// Floating Command Center palette — a Raycast-like, input-first prompt with results below.
struct CommandModeView: View {
    @EnvironmentObject private var commandMode: CommandModeController
    @EnvironmentObject private var preferences: PreferencesController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            promptBar
            statusBar
            Divider()
            itemList
            Divider()
            footer
        }
        .frame(width: 480)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    /// The hero: a large, input-first prompt line. Backed by `filterQuery` (not a
    /// real `TextField`) because keystrokes are intercepted by `CommandModeController`'s
    /// local key monitor before they'd reach any first responder.
    private var promptBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Text(commandMode.filterQuery.isEmpty ? placeholder : commandMode.filterQuery)
                    .font(.system(size: 19, weight: .regular, design: .rounded))
                    .foregroundStyle(commandMode.filterQuery.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                if !commandMode.filterQuery.isEmpty {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !commandMode.filterQuery.isEmpty {
                Text("⌫")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private var placeholder: String {
        switch commandMode.phase {
        case .root: return "Type a command or /verb…"
        case .pickWorkspace: return "Search Workspaces…"
        case .pickAgent: return "Search Worktrees…"
        case .pickBackground: return "Search Overlays…"
        }
    }

    /// Small, secondary breadcrumb row — demoted so it never competes with `promptBar`.
    private var statusBar: some View {
        HStack {
            Text(phaseTitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(preferences.effective.leaderKey)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
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
            .font(.caption2)
            .help("Dismiss Command Center")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var phaseTitle: String {
        switch commandMode.phase {
        case .root: return "Command Center"
        case .pickWorkspace: return "Switch Workspace"
        case .pickAgent: return "Focus Worktree"
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
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.22) : Color.clear)
    }

    private var footer: some View {
        HStack {
            Text("↑↓ · ↩ · type to filter · / for verbs · keybinds when empty")
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
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }
}
