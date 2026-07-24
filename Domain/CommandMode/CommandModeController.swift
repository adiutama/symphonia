import AppKit
import Combine
import Foundation

/// Leader → Command Mode (ADR 0009 / Phase 7).
///
/// Uses an AppKit local keyDown monitor so Ghostty first-responder PTYs never see
/// Leader chords or in-mode keystrokes. Effective `leaderKey` is re-parsed each event.
@MainActor
final class CommandModeController: ObservableObject {
    private let preferences: PreferencesController
    private let workspaces: WorkspaceController
    private let agents: AgentController
    private let overlays: OverlayController

    @Published private(set) var isActive = false
    @Published private(set) var phase: CommandModePhase = .root
    @Published private(set) var items: [CommandModeItem] = []
    @Published var selectedIndex: Int = 0
    /// Type-to-filter query (also accumulates printable keys when not a root keybind).
    @Published var filterQuery: String = ""
    @Published var lastInfo: String?

    private var localMonitor: Any?
    private weak var savedFirstResponder: NSResponder?
    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: PreferencesController,
        workspaces: WorkspaceController,
        agents: AgentController,
        overlays: OverlayController
    ) {
        self.preferences = preferences
        self.workspaces = workspaces
        self.agents = agents
        self.overlays = overlays

        Publishers.CombineLatest3(
            workspaces.$workspaces,
            agents.$agents,
            overlays.$sessions
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in
            guard let self, self.isActive else { return }
            self.rebuildItems(resetSelection: false)
        }
        .store(in: &cancellables)

        installMonitor()
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    // MARK: - Enter / dismiss

    func enter() {
        guard !isActive else { return }
        isActive = true
        phase = .root
        filterQuery = ""
        lastInfo = nil
        resignTerminalFocus()
        rebuildItems(resetSelection: true)
    }

    func dismiss() {
        guard isActive else { return }
        isActive = false
        phase = .root
        filterQuery = ""
        items = []
        selectedIndex = 0
        restoreTerminalFocus()
    }

    func setFilter(_ query: String) {
        filterQuery = query
        rebuildItems(resetSelection: true)
    }

    // MARK: - Navigation / run

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let next = selectedIndex + delta
        selectedIndex = max(0, min(items.count - 1, next))
    }

    func runSelected() {
        guard items.indices.contains(selectedIndex) else { return }
        run(items[selectedIndex].action)
    }

    func run(_ action: CommandModeAction) {
        switch action {
        case .dismiss:
            dismiss()

        case .back:
            phase = .root
            filterQuery = ""
            rebuildItems(resetSelection: true)

        case .openSettings:
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            lastInfo = "Settings"
            dismiss()

        case .showWorkspacePicker:
            phase = .pickWorkspace
            filterQuery = ""
            rebuildItems(resetSelection: true)

        case .showAgentPicker:
            phase = .pickAgent
            filterQuery = ""
            rebuildItems(resetSelection: true)

        case .showBackgroundPicker:
            phase = .pickBackground
            filterQuery = ""
            rebuildItems(resetSelection: true)

        case .switchWorkspace(let id):
            if let summary = workspaces.workspaces.first(where: { $0.id == id }) {
                workspaces.select(summary)
                lastInfo = "Workspace: \(summary.slug)"
            }
            dismiss()

        case .focusMainRepo:
            guard let current = workspaces.current else {
                lastInfo = "Select a Workspace first"
                dismiss()
                return
            }
            agents.focusMain(for: current)
            lastInfo = "Main Repo"
            dismiss()

        case .focusAgent(let id):
            if let agent = agents.agents.first(where: { $0.id == id }) {
                agents.focus(agent)
                lastInfo = "Agent: \(agent.primaryLabel)"
            }
            dismiss()

        case .newAgent:
            agents.createAgent()
            if let focused = agents.focused {
                lastInfo = "Created Agent: \(focused.primaryLabel)"
            } else if let err = agents.lastError {
                lastInfo = err
            }
            dismiss()

        case .removeFocusedAgent:
            guard let focused = agents.focused else {
                lastInfo = "No focused Agent to remove"
                dismiss()
                return
            }
            agents.requestRemove(focused)
            lastInfo = "Confirm Remove Agent"
            dismiss()

        case .openEditor:
            overlays.openEditor()
            lastInfo = overlays.lastInfo ?? overlays.lastError ?? "Editor"
            dismiss()

        case .createBackground:
            overlays.createBackgroundCLI()
            lastInfo = overlays.lastInfo ?? overlays.lastError ?? "Background CLI"
            dismiss()

        case .peekBackground(let id):
            overlays.peek(id)
            lastInfo = overlays.visibleSession?.title ?? "Peek Overlay"
            dismiss()

        case .hideOverlay:
            overlays.hide()
            lastInfo = "Main CLI"
            dismiss()
        }
    }

    // MARK: - Items

    private func rebuildItems(resetSelection: Bool) {
        let raw: [CommandModeItem]
        switch phase {
        case .root:
            raw = rootItems()
        case .pickWorkspace:
            raw = workspacePickerItems()
        case .pickAgent:
            raw = agentPickerItems()
        case .pickBackground:
            raw = backgroundPickerItems()
        }
        items = filter(raw)
        if resetSelection || selectedIndex >= items.count {
            selectedIndex = items.isEmpty ? 0 : min(selectedIndex, max(items.count - 1, 0))
        }
    }

    private func filter(_ raw: [CommandModeItem]) -> [CommandModeItem] {
        let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return raw }
        return raw.filter { item in
            if item.action == .back { return true }
            let hay = [item.title, item.subtitle, item.keybind]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            return hay.contains(q)
        }
    }

    private func rootItems() -> [CommandModeItem] {
        var rows: [CommandModeItem] = []

        rows.append(CommandModeItem(
            id: "workspaces",
            title: "Switch Workspace…",
            subtitle: workspaces.current.map { "current: \($0.slug)" } ?? "none selected",
            keybind: "w",
            action: .showWorkspacePicker
        ))
        rows.append(CommandModeItem(
            id: "agents",
            title: "Focus session…",
            subtitle: agents.focusedSession.map(\.displayTitle) ?? "none focused",
            keybind: "a",
            action: .showAgentPicker
        ))
        rows.append(CommandModeItem(
            id: "main",
            title: "Focus Main Repo",
            subtitle: workspaces.current.map { $0.slug } ?? "needs Workspace",
            keybind: "m",
            action: .focusMainRepo
        ))
        rows.append(CommandModeItem(
            id: "new-agent",
            title: "New Agent",
            subtitle: workspaces.current == nil ? "needs Workspace" : nil,
            keybind: "n",
            action: .newAgent
        ))
        rows.append(CommandModeItem(
            id: "remove-agent",
            title: "Remove Agent…",
            subtitle: agents.focused.map(\.primaryLabel) ?? "needs focused Agent",
            keybind: "x",
            action: .removeFocusedAgent
        ))
        rows.append(CommandModeItem(
            id: "editor",
            title: "Open Editor",
            subtitle: preferences.effective.editorCommand,
            keybind: "e",
            action: .openEditor
        ))
        rows.append(CommandModeItem(
            id: "bg-create",
            title: "Create Background CLI",
            subtitle: "peek new Overlay (empty = shell)",
            keybind: "b",
            action: .createBackground
        ))
        rows.append(CommandModeItem(
            id: "bg-peek",
            title: "Peek Overlay…",
            subtitle: overlays.focusedSessions.isEmpty
                ? "no live Overlays"
                : "\(overlays.focusedSessions.count) session(s)",
            keybind: "p",
            action: .showBackgroundPicker
        ))
        rows.append(CommandModeItem(
            id: "hide-overlay",
            title: "Hide Overlay → Main CLI",
            subtitle: overlays.isShowingOverlay ? overlays.visibleSession?.title : "already on Main CLI",
            keybind: "h",
            action: .hideOverlay
        ))
        rows.append(CommandModeItem(
            id: "settings",
            title: "Open Settings…",
            subtitle: "Secret Store lives under Workspace",
            keybind: ",",
            action: .openSettings
        ))
        rows.append(CommandModeItem(
            id: "dismiss",
            title: "Dismiss Command Center",
            subtitle: "Esc",
            keybind: nil,
            action: .dismiss
        ))
        return rows
    }

    private func workspacePickerItems() -> [CommandModeItem] {
        var list: [CommandModeItem] = [
            CommandModeItem(id: "ws-back", title: "← Back", action: .back),
        ]
        if workspaces.workspaces.isEmpty {
            list.append(CommandModeItem(
                id: "ws-empty",
                title: "(no Workspaces)",
                action: .back
            ))
        } else {
            for ws in workspaces.workspaces {
                let mark = workspaces.current?.id == ws.id ? " ← current" : ""
                list.append(CommandModeItem(
                    id: "ws-\(ws.id)",
                    title: ws.slug + mark,
                    subtitle: ws.dataDirURL.path,
                    action: .switchWorkspace(id: ws.id)
                ))
            }
        }
        return list
    }

    private func agentPickerItems() -> [CommandModeItem] {
        var list: [CommandModeItem] = [
            CommandModeItem(id: "ag-back", title: "← Back", action: .back),
        ]
        if workspaces.current == nil {
            list.append(CommandModeItem(
                id: "ag-nows",
                title: "(select a Workspace first)",
                action: .back
            ))
        } else {
            let current = workspaces.current!
            let mainFocused = agents.focusedSession?.isMainRepo == true
            list.append(CommandModeItem(
                id: "ag-main",
                title: "Main Repo" + (mainFocused ? " ← focus" : ""),
                subtitle: SymphoniaPaths.workspaceMainDirectory(in: current.dataDirURL).path,
                keybind: "m",
                action: .focusMainRepo
            ))
            if agents.agents.isEmpty {
                list.append(CommandModeItem(
                    id: "ag-empty",
                    title: "(no Agents)",
                    action: .back
                ))
            } else {
                for agent in agents.agents {
                    let mark = agents.focused?.id == agent.id ? " ← focus" : ""
                    list.append(CommandModeItem(
                        id: "ag-\(agent.id)",
                        title: agent.primaryLabel + mark,
                        subtitle: agent.secondaryLabel ?? agent.threeWordName,
                        action: .focusAgent(id: agent.id)
                    ))
                }
            }
        }
        return list
    }

    private func backgroundPickerItems() -> [CommandModeItem] {
        var list: [CommandModeItem] = [
            CommandModeItem(id: "bg-back", title: "← Back", action: .back),
        ]
        let sessions = overlays.focusedSessions
        if sessions.isEmpty {
            list.append(CommandModeItem(
                id: "bg-empty",
                title: "(no Overlay sessions)",
                action: .back
            ))
        } else {
            for session in sessions {
                let mark = overlays.visibleOverlayID == session.id ? " ●" : ""
                list.append(CommandModeItem(
                    id: "bg-\(session.id.uuidString)",
                    title: session.title + mark,
                    subtitle: session.kind == .editor ? "Editor" : "Background",
                    action: .peekBackground(id: session.id)
                ))
            }
        }
        return list
    }

    // MARK: - Key monitor

    private func installMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let binding = LeaderKeyBinding.parse(preferences.effective.leaderKey)

        if !isActive {
            if let binding, binding.matches(event) {
                enter()
                return nil
            }
            return event
        }

        if event.keyCode == 53 { // Escape
            if !filterQuery.isEmpty {
                filterQuery = ""
                rebuildItems(resetSelection: true)
            } else if phase != .root {
                phase = .root
                rebuildItems(resetSelection: true)
            } else {
                dismiss()
            }
            return nil
        }

        if let binding, binding.matches(event) {
            dismiss()
            return nil
        }

        switch event.keyCode {
        case 125: // down
            moveSelection(1)
            return nil
        case 126: // up
            moveSelection(-1)
            return nil
        case 36, 76: // return / keypad enter
            runSelected()
            return nil
        case 51: // delete
            if !filterQuery.isEmpty {
                filterQuery.removeLast()
                rebuildItems(resetSelection: true)
            }
            return nil
        default:
            break
        }

        // Root keybinds when filter empty and no modifiers (except shift for symbols).
        let mods = event.modifierFlags.intersection([.control, .option, .command])
        if mods.isEmpty,
           filterQuery.isEmpty,
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars.count == 1,
           let match = items.first(where: { $0.keybind?.lowercased() == chars })
        {
            run(match.action)
            return nil
        }

        // Type-to-filter: append printable characters.
        if mods.intersection([.control, .option, .command]).isEmpty,
           let chars = event.charactersIgnoringModifiers,
           chars.count == 1,
           let ch = chars.first,
           (ch.isLetter || ch.isNumber || ch == "," || ch == "." || ch == "-" || ch == "_" || ch == " ")
        {
            filterQuery.append(ch)
            rebuildItems(resetSelection: true)
            return nil
        }

        return nil
    }

    // MARK: - First responder

    private func resignTerminalFocus() {
        guard let window = NSApp.keyWindow else { return }
        savedFirstResponder = window.firstResponder
        if window.firstResponder is NSView {
            window.makeFirstResponder(nil)
        }
    }

    private func restoreTerminalFocus() {
        defer { savedFirstResponder = nil }
        guard let window = NSApp.keyWindow else { return }
        if let saved = savedFirstResponder,
           saved !== window,
           (saved as? NSView)?.window === window
        {
            window.makeFirstResponder(saved)
            return
        }
        if let terminal = findTerminalSurface(in: window.contentView) {
            window.makeFirstResponder(terminal)
        }
    }

    private func findTerminalSurface(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        let typeName = String(describing: type(of: view))
        if typeName.contains("TerminalSurface") {
            return view
        }
        for child in view.subviews {
            if let found = findTerminalSurface(in: child) {
                return found
            }
        }
        return nil
    }
}
