import SwiftUI

/// Command Center chrome — Path B **D · Minimal strip**, Peek nest **E · Nest bar**.
struct CommandModeView: View {
    @EnvironmentObject private var commandMode: CommandModeController
    @EnvironmentObject private var preferences: PreferencesController
    @EnvironmentObject private var ghosttyTheme: GhosttyChromeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if commandMode.phase == .pickBackground {
                nestBar
            } else {
                modeStrip
            }
            promptBar
            SoftHairline(horizontalPadding: 10)
            itemList
            SoftHairline(horizontalPadding: 10)
            footer
        }
        .frame(width: 440)
        .chromeFloatingSurface(
            glass: preferences.preferences.chromeGlass,
            solid: ghosttyTheme.panel,
            cornerRadius: 14
        )
        .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
    }

    // MARK: - D · Minimal strip

    private var modeStrip: some View {
        HStack(spacing: 6) {
            Text(stripLabel)
                .font(.caption2.weight(.semibold).monospaced())
                .foregroundStyle(ghosttyTheme.secondaryText)
                .tracking(0.6)
            Spacer(minLength: 8)
            Text(
                LeaderKeyBinding.parse(preferences.effective.leaderKey)?.displaySymbolString
                    ?? preferences.effective.leaderKey
            )
            .font(.caption2.monospaced())
            .foregroundStyle(ghosttyTheme.tertiaryText)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var stripLabel: String {
        let mode = commandMode.mode.stripLabel
        if let phase = commandMode.phase.phaseTitle {
            return "\(mode) · \(phase)"
        }
        return mode
    }

    // MARK: - E · Nest bar (Overlay Switcher)

    private var nestBar: some View {
        HStack(spacing: 8) {
            Button {
                commandMode.leaveNestToRoot()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ghosttyTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Back to main list (Esc)")

            Text("Overlay Switcher")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ghosttyTheme.foreground.opacity(0.85))

            Spacer(minLength: 8)

            Text("Esc")
                .font(.caption2.monospaced())
                .foregroundStyle(ghosttyTheme.tertiaryText)
                .help("Leave nest to main list")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Prompt

    private var promptBar: some View {
        HStack(spacing: 8) {
            Text(commandMode.filterQuery.isEmpty ? placeholder : commandMode.filterQuery)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundStyle(
                    commandMode.filterQuery.isEmpty
                        ? ghosttyTheme.tertiaryText
                        : ghosttyTheme.foreground
                )
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !commandMode.filterQuery.isEmpty {
                Text("⌫")
                    .font(.caption2)
                    .foregroundStyle(ghosttyTheme.tertiaryText)
            } else {
                Rectangle()
                    .fill(ghosttyTheme.accent.opacity(0.7))
                    .frame(width: 1.5, height: 14)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var placeholder: String {
        switch (commandMode.phase, commandMode.mode) {
        case (.root, .normal): return "Sequence…"
        case (.root, .input): return "Filter commands…"
        case (.pickWorkspace, .normal): return "Sequence…"
        case (.pickWorkspace, .input): return "Search Workspaces…"
        case (.pickWorktree, .normal): return "Sequence…"
        case (.pickWorktree, .input): return "Search Worktrees…"
        case (.pickBackground, .normal): return "Sequence…"
        case (.pickBackground, .input): return "Search Overlays…"
        }
    }

    // MARK: - List

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if commandMode.items.isEmpty {
                        Text("No matches")
                            .font(.caption)
                            .foregroundStyle(ghosttyTheme.secondaryText)
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
            .frame(maxHeight: 300)
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(ghosttyTheme.foreground)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(ghosttyTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let sequence = item.sequence {
                Text(sequence)
                    .font(.caption.monospaced().weight(.medium))
                    .foregroundStyle(
                        selected
                            ? ghosttyTheme.foreground.opacity(0.7)
                            : ghosttyTheme.secondaryText
                    )
            } else if selected {
                Text("↩")
                    .font(.caption)
                    .foregroundStyle(ghosttyTheme.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? ghosttyTheme.selectionFill : Color.clear)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(footerHints)
                .font(.caption2)
                .foregroundStyle(ghosttyTheme.tertiaryText)
            Spacer()
            if let info = commandMode.lastInfo {
                Text(info)
                    .font(.caption2)
                    .foregroundStyle(ghosttyTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var footerHints: String {
        let move = commandMode.mode == .normal ? "⌃N/P · j/k · ↑↓" : "⌃N/P · ↑↓"
        return "⇧Tab · \(move) · ↩ · Esc"
    }
}
