import Foundation

/// Builds Command Center nest picker rows and ephemeral nest sequences (ADR 0022).
///
/// Owned by `CommandCenterController`; kept separate so palette orchestration stays thin.
@MainActor
struct CommandCenterNestCatalog {
    let workspaces: WorkspaceController
    let worktrees: WorktreeController
    let overlays: OverlayController

    /// Ephemeral nest chords assigned when entering a picker phase.
    private(set) var sequences: [String: String] = [:]

    mutating func resetSequences() {
        sequences = [:]
    }

    mutating func assignSequences(for nest: CommandCenterPhase) {
        sequences = [:]
        let raw: [CommandCenterItem]
        switch nest {
        case .root:
            return
        case .pickWorkspace:
            raw = workspacePickerItemsRaw()
        case .pickWorktree:
            raw = worktreePickerItemsRaw()
        case .pickBackground:
            // Peek: random ephemeral chords for all nest rows.
            raw = backgroundPickerItemsRaw()
            let chords = CommandSequence.randomChords(count: raw.count)
            for (item, chord) in zip(raw, chords) {
                sequences[item.id] = chord
            }
            return
        }
        // Workspace / Worktree: prefer title-initial style.
        let chords = CommandSequence.titleStyleChords(for: raw.map(\.title))
        for (item, chord) in zip(raw, chords) {
            sequences[item.id] = chord
        }
    }

    mutating func items(for nest: CommandCenterPhase) -> [CommandCenterItem] {
        rawItems(for: nest).map { withNestSequence($0) }
    }

    private func rawItems(for nest: CommandCenterPhase) -> [CommandCenterItem] {
        switch nest {
        case .root:
            return []
        case .pickWorkspace:
            return workspacePickerItemsRaw()
        case .pickWorktree:
            return worktreePickerItemsRaw()
        case .pickBackground:
            return backgroundPickerItemsRaw()
        }
    }

    private mutating func withNestSequence(_ item: CommandCenterItem) -> CommandCenterItem {
        let chord: String
        if let existing = sequences[item.id] {
            chord = existing
        } else {
            // Rows that appear after nest enter (e.g. Close Overlay) get a fresh chord.
            let used = Set(sequences.values)
            chord = CommandSequence.randomChords(count: 1, excluding: used).first ?? "xx"
            sequences[item.id] = chord
        }
        return CommandCenterItem(
            id: item.id,
            title: item.title,
            subtitle: item.subtitle,
            sequence: chord,
            action: item.action
        )
    }

    private func workspacePickerItemsRaw() -> [CommandCenterItem] {
        var list: [CommandCenterItem] = []
        if workspaces.workspaces.isEmpty {
            list.append(CommandCenterItem(
                id: "ws-empty",
                title: "(no Workspaces)",
                action: .back
            ))
        } else {
            for ws in workspaces.workspaces {
                let mark = workspaces.current?.id == ws.id ? " ← current" : ""
                list.append(CommandCenterItem(
                    id: "ws-\(ws.id)",
                    title: ws.slug + mark,
                    subtitle: ws.dataDirURL.path,
                    action: .switchWorkspace(id: ws.id)
                ))
            }
        }
        return list
    }

    private func worktreePickerItemsRaw() -> [CommandCenterItem] {
        var list: [CommandCenterItem] = []
        if let current = workspaces.current {
            let mainFocused = worktrees.focusedSession?.isMainRepo == true
            list.append(CommandCenterItem(
                id: "wt-main",
                title: "main" + (mainFocused ? " ← focus" : ""),
                subtitle: SymphoniaPaths.workspaceMainDirectory(in: current.dataDirURL).path,
                action: .focusMainRepo
            ))
            if worktrees.worktrees.isEmpty {
                list.append(CommandCenterItem(
                    id: "wt-empty",
                    title: "(no Worktrees)",
                    action: .back
                ))
            } else {
                for wt in worktrees.worktrees {
                    let mark = worktrees.focused?.id == wt.id ? " ← focus" : ""
                    list.append(CommandCenterItem(
                        id: "wt-\(wt.id)",
                        title: wt.primaryLabel + mark,
                        subtitle: wt.secondaryLabel ?? wt.threeWordName,
                        action: .focusWorktree(id: wt.id)
                    ))
                }
            }
        } else {
            list.append(CommandCenterItem(
                id: "wt-nows",
                title: "(select a Workspace first)",
                action: .back
            ))
        }
        return list
    }

    /// Overlay nest: siblings + Back (hide) + Close Overlay — no main-catalog duplication.
    private func backgroundPickerItemsRaw() -> [CommandCenterItem] {
        var list: [CommandCenterItem] = []
        let sessions = overlays.focusedSessions
        if sessions.isEmpty {
            list.append(CommandCenterItem(
                id: "bg-empty",
                title: "(no Overlay sessions)",
                action: .back
            ))
        } else {
            for session in sessions {
                let mark = overlays.visibleOverlayID == session.id ? " ●" : ""
                let kindLabel = session.displayKindLabel
                list.append(CommandCenterItem(
                    id: "bg-\(session.id.uuidString)",
                    title: session.title + mark,
                    subtitle: kindLabel,
                    action: .peekBackground(id: session.id)
                ))
            }
        }

        // Product Back = hide Overlay → Main CLI (not Esc leave-nest).
        list.append(CommandCenterItem(
            id: "bg-hide",
            title: "Back",
            subtitle: "Main CLI · hide (keeps running)",
            action: .hideOverlay
        ))

        if let visible = overlays.visibleSession, visible.kind == .background {
            list.append(CommandCenterItem(
                id: "bg-close",
                title: "Close Overlay",
                subtitle: "Kill Background PTY",
                action: .closeOverlay(id: visible.id)
            ))
        }

        return list
    }
}
