import SwiftUI

/// Floating Command Mode palette scaffold (P7.2). Ugly on purpose; polish later.
struct CommandModeView: View {
    @EnvironmentObject private var commandMode: CommandModeController
    @EnvironmentObject private var preferences: PreferencesController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            itemList
            Divider()
            footer
        }
        .frame(width: 420)
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
                if commandMode.phase == .root {
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

    private var phaseTitle: String {
        switch commandMode.phase {
        case .root: return "Command Mode"
        case .pickWorkspace: return "Switch Workspace"
        case .pickAgent: return "Focus Agent"
        case .pickBackground: return "Peek Overlay"
        }
    }

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
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
            if selected {
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
            Text("↑↓ navigate · ↩ run · Esc cancel")
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
