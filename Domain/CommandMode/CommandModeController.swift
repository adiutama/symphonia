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
    /// Shared with ContentView: collapse / expand Workspace / Agent / Secrets scaffolds.
    @Published var scaffoldsExpanded = false
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

        // Rebuild list when underlying lists change while open.
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
        // Monitors must be removed; MainActor deinit cannot call MainActor methods directly
        // in all Swift versions — capture and remove synchronously.
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    // MARK: - Enter / dismiss

    func enter() {
        guard !isActive else { return }
        isActive = true
        phase = .root
        lastInfo = nil
        resignTerminalFocus()
        rebuildItems(resetSelection: true)
    }

    func dismiss() {
        guard isActive else { return }
        isActive = false
        phase = .root
        items = []
        selectedIndex = 0
        restoreTerminalFocus()
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
            rebuildItems(resetSelection: true)

        case .toggleScaffolds:
            scaffoldsExpanded.toggle()
            lastInfo = scaffoldsExpanded ? "Panels shown" : "Panels hidden"
            dismiss()

        case .showScaffolds:
            scaffoldsExpanded = true
            lastInfo = "Panels shown"
            dismiss()

        case .hideScaffolds:
            scaffoldsExpanded = false
            lastInfo = "Panels hidden"
            dismiss()

        case .openSecretStorePanel:
            scaffoldsExpanded = true
            lastInfo = "Secret Store panel open"
            dismiss()

        case .showWorkspacePicker:
            phase = .pickWorkspace
            rebuildItems(resetSelection: true)

        case .showAgentPicker:
            phase = .pickAgent
            rebuildItems(resetSelection: true)

        case .showBackgroundPicker:
            phase = .pickBackground
            rebuildItems(resetSelection: true)

        case .switchWorkspace(let id):
            if let summary = workspaces.workspaces.first(where: { $0.id == id }) {
                workspaces.select(summary)
                lastInfo = "Workspace: \(summary.slug)"
            }
            dismiss()

        case .focusAgent(let id):
            if let agent = agents.agents.first(where: { $0.id == id }) {
                agents.focus(agent)
                lastInfo = "Agent: \(agent.threeWordName)"
            }
            dismiss()

        case .newAgent:
            agents.createAgent()
            if let focused = agents.focused {
                lastInfo = "Created Agent: \(focused.threeWordName)"
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
            // Hand off to existing AgentScaffold confirm dialog (ADR 0020).
            agents.requestRemove(focused)
            scaffoldsExpanded = true
            lastInfo = "Confirm Remove Agent in Agents panel"
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
        switch phase {
        case .root:
            items = rootItems()
        case .pickWorkspace:
            items = workspacePickerItems()
        case .pickAgent:
            items = agentPickerItems()
        case .pickBackground:
            items = backgroundPickerItems()
        }
        if resetSelection || selectedIndex >= items.count {
            selectedIndex = items.isEmpty ? 0 : min(selectedIndex, items.count - 1)
        }
    }

    private func rootItems() -> [CommandModeItem] {
        var rows: [CommandModeItem] = []

        rows.append(CommandModeItem(
            id: "workspaces",
            title: "Switch Workspace…",
            subtitle: workspaces.current.map { "current: \($0.slug)" } ?? "none selected",
            action: .showWorkspacePicker
        ))
        rows.append(CommandModeItem(
            id: "agents",
            title: "Focus Agent…",
            subtitle: agents.focused.map { "focus: \($0.threeWordName)" } ?? "none focused",
            action: .showAgentPicker
        ))
        rows.append(CommandModeItem(
            id: "new-agent",
            title: "New Agent",
            subtitle: workspaces.current == nil ? "needs Workspace" : nil,
            action: .newAgent
        ))
        rows.append(CommandModeItem(
            id: "remove-agent",
            title: "Remove Agent…",
            subtitle: agents.focused.map { $0.threeWordName } ?? "needs focused Agent",
            action: .removeFocusedAgent
        ))
        rows.append(CommandModeItem(
            id: "editor",
            title: "Open Editor",
            subtitle: preferences.effective.editorCommand,
            action: .openEditor
        ))
        rows.append(CommandModeItem(
            id: "bg-create",
            title: "Create Background CLI",
            subtitle: "peek new Overlay (empty = shell)",
            action: .createBackground
        ))
        rows.append(CommandModeItem(
            id: "bg-peek",
            title: "Peek Overlay…",
            subtitle: overlays.focusedSessions.isEmpty
                ? "no live Overlays"
                : "\(overlays.focusedSessions.count) session(s)",
            action: .showBackgroundPicker
        ))
        rows.append(CommandModeItem(
            id: "hide-overlay",
            title: "Hide Overlay → Main CLI",
            subtitle: overlays.isShowingOverlay ? overlays.visibleSession?.title : "already on Main CLI",
            action: .hideOverlay
        ))
        rows.append(CommandModeItem(
            id: "toggle-panels",
            title: scaffoldsExpanded ? "Hide scaffold panels" : "Show scaffold panels",
            subtitle: "Workspace / Agent / Secrets",
            action: .toggleScaffolds
        ))
        rows.append(CommandModeItem(
            id: "secrets",
            title: "Open Secret Store panel",
            subtitle: "expands scaffolds",
            action: .openSecretStorePanel
        ))
        rows.append(CommandModeItem(
            id: "dismiss",
            title: "Dismiss Command Mode",
            subtitle: "Esc",
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
        } else if agents.agents.isEmpty {
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
                    title: agent.threeWordName + mark,
                    subtitle: agent.branchName.map { "branch: \($0)" },
                    action: .focusAgent(id: agent.id)
                ))
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
        // Always read Effective Setting so Settings changes apply without restart (P7.3).
        let binding = LeaderKeyBinding.parse(preferences.effective.leaderKey)

        if !isActive {
            if let binding, binding.matches(event) {
                enter()
                return nil // swallow Leader — PTY must not see it
            }
            return event
        }

        // Command Mode active: consume everything so Main CLI / Overlay PTY stay quiet.
        if event.keyCode == 53 { // Escape
            if phase != .root {
                phase = .root
                rebuildItems(resetSelection: true)
            } else {
                dismiss()
            }
            return nil
        }

        // Leader again while active → dismiss.
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
        default:
            return nil
        }
    }

    // MARK: - First responder

    private func resignTerminalFocus() {
        guard let window = NSApp.keyWindow else { return }
        savedFirstResponder = window.firstResponder
        // Prefer resigning terminal surfaces so the caret stops blinking in the PTY.
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
        // Fall back: first TerminalSurfaceNSView in the key window.
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
