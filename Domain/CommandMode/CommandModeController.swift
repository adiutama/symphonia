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
    private let worktrees: WorktreeController
    private let overlays: OverlayController
    private let settingsNavigation: SettingsNavigation
    /// Source of root-palette items and matching data (ADR 0021 / CC.2). Root no longer
    /// owns a private hardcoded item/slash-verb table — see `filteredRootItems()`.
    private let commandRegistry: CommandRegistry

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
        worktrees: WorktreeController,
        overlays: OverlayController,
        settingsNavigation: SettingsNavigation,
        commandRegistry: CommandRegistry
    ) {
        self.preferences = preferences
        self.workspaces = workspaces
        self.worktrees = worktrees
        self.overlays = overlays
        self.settingsNavigation = settingsNavigation
        self.commandRegistry = commandRegistry

        Publishers.CombineLatest4(
            workspaces.$workspaces,
            worktrees.$worktrees,
            overlays.$sessions,
            preferences.$preferences
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
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
            settingsNavigation.openSettings()
            lastInfo = "Settings"
            dismiss()

        case .showWorkspacePicker:
            phase = .pickWorkspace
            filterQuery = ""
            rebuildItems(resetSelection: true)

        case .showWorktreePicker:
            phase = .pickWorktree
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
            worktrees.focusMain(for: current)
            lastInfo = "Main"
            dismiss()

        case .focusWorktree(let id):
            if let wt = worktrees.worktrees.first(where: { $0.id == id }) {
                worktrees.focus(wt)
                lastInfo = "Worktree: \(wt.primaryLabel)"
            }
            dismiss()

        case .newWorktree:
            guard workspaces.current != nil else {
                lastInfo = "Select a Workspace first"
                dismiss()
                return
            }
            worktrees.beginCreateWorktree()
            lastInfo = "New Worktree"
            dismiss()

        case .removeFocusedWorktree:
            guard let focused = worktrees.focused else {
                lastInfo = "No focused Worktree to remove"
                dismiss()
                return
            }
            worktrees.requestRemove(focused)
            lastInfo = "Confirm Remove Worktree"
            dismiss()

        case .removeCurrentWorkspace:
            guard let current = workspaces.current else {
                lastInfo = "No Workspace selected"
                dismiss()
                return
            }
            workspaces.requestRemove(current)
            lastInfo = "Confirm Remove Workspace"
            dismiss()

        case .renameWorkspace:
            guard let current = workspaces.current else {
                lastInfo = "No Workspace selected"
                dismiss()
                return
            }
            workspaces.beginRename(current)
            lastInfo = "Rename Workspace"
            dismiss()

        case .renameFocusedWorktree:
            guard let focused = worktrees.focused else {
                lastInfo = "Focus a Worktree first"
                dismiss()
                return
            }
            worktrees.beginRename(focused)
            lastInfo = "Rename Worktree"
            dismiss()

        case .reloadFocusedCLI:
            worktrees.respawnWithCurrentSecrets()
            if let err = worktrees.lastError {
                lastInfo = err
            } else {
                lastInfo = "Reloaded CLI"
            }
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
            if overlays.isShowingOverlay {
                overlays.hide()
                lastInfo = "Main CLI"
            } else {
                lastInfo = "Already on Main CLI"
            }
            dismiss()

        case .toggleStatusCue:
            let key = StatusCueDefaults.listVisibleKey
            let next = !UserDefaults.standard.bool(forKey: key)
            UserDefaults.standard.set(next, forKey: key)
            lastInfo = next ? "Status cue on" : "Status cue off"
            dismiss()
        }
    }

    // MARK: - Items

    private func rebuildItems(resetSelection: Bool) {
        switch phase {
        case .root:
            items = filteredRootItems()
        case .pickWorkspace:
            items = filter(workspacePickerItems())
        case .pickWorktree:
            items = filter(worktreePickerItems())
        case .pickBackground:
            items = filter(backgroundPickerItems())
        }
        if resetSelection || selectedIndex >= items.count {
            selectedIndex = items.isEmpty ? 0 : min(selectedIndex, max(items.count - 1, 0))
        }
    }

    // MARK: - Root (Command registry, ADR 0021 / CC.2)

    private func filteredRootItems() -> [CommandModeItem] {
        let context = CommandContext(worktrees: worktrees, overlays: overlays)
        let commands = commandRegistry.availableCommands(context: context)
        let overrides = preferences.preferences.commandBindings
        let query = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = query.isEmpty ? commands : commands.filter { matches($0, query: query, overrides: overrides) }
        return matched.map { commandItem($0, overrides: overrides) }
    }

    private func matches(_ command: Command, query: String, overrides: [String: CommandBindingOverride]) -> Bool {
        if command.title.lowercased().contains(query) { return true }
        if let subtitle = command.subtitle, subtitle.lowercased().contains(query) { return true }
        let aliases = CommandBindingResolver.aliases(for: command, overrides: overrides)
        return aliases.contains { $0.lowercased().contains(query) }
    }

    private func commandItem(_ command: Command, overrides: [String: CommandBindingOverride]) -> CommandModeItem {
        CommandModeItem(
            id: command.id,
            title: command.title,
            subtitle: liveSubtitle(for: command),
            keybind: CommandBindingResolver.shortcutDisplay(
                CommandBindingResolver.shortcut(for: command, overrides: overrides)
            ),
            action: command.action
        )
    }

    private func liveSubtitle(for command: Command) -> String? {
        switch command.id {
        case "overlay.openEditor":
            return preferences.effective.editorCommand
        case "overlay.hide":
            return overlays.isShowingOverlay ? overlays.visibleSession?.title : "Already on Main CLI"
        default:
            return command.subtitle
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

    private func worktreePickerItems() -> [CommandModeItem] {
        var list: [CommandModeItem] = [
            CommandModeItem(id: "wt-back", title: "← Back", action: .back),
        ]
        if workspaces.current == nil {
            list.append(CommandModeItem(
                id: "wt-nows",
                title: "(select a Workspace first)",
                action: .back
            ))
        } else {
            let current = workspaces.current!
            let mainFocused = worktrees.focusedSession?.isMainRepo == true
            list.append(CommandModeItem(
                id: "wt-main",
                title: "main" + (mainFocused ? " ← focus" : ""),
                subtitle: SymphoniaPaths.workspaceMainDirectory(in: current.dataDirURL).path,
                keybind: "⌃M",
                action: .focusMainRepo
            ))
            if worktrees.worktrees.isEmpty {
                list.append(CommandModeItem(
                    id: "wt-empty",
                    title: "(no Worktrees)",
                    action: .back
                ))
            } else {
                for wt in worktrees.worktrees {
                    let mark = worktrees.focused?.id == wt.id ? " ← focus" : ""
                    list.append(CommandModeItem(
                        id: "wt-\(wt.id)",
                        title: wt.primaryLabel + mark,
                        subtitle: wt.secondaryLabel ?? wt.threeWordName,
                        action: .focusWorktree(id: wt.id)
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

        // Chord shortcuts when filter empty (Raycast-like: bare letters always filter).
        if filterQuery.isEmpty,
           let match = items.first(where: { item in
               guard let raw = item.keybind,
                     let binding = LeaderKeyBinding.parse(raw),
                     !binding.modifiers.intersection([.control, .option, .command]).isEmpty
               else { return false }
               return binding.matches(event)
           })
        {
            run(match.action)
            return nil
        }

        // Type-to-filter: append printable characters (including bare former shortcut letters).
        let mods = event.modifierFlags.intersection([.control, .option, .command])
        if mods.isEmpty,
           let chars = event.charactersIgnoringModifiers,
           chars.count == 1,
           let ch = chars.first,
           (ch.isLetter || ch.isNumber || ch == "," || ch == "." || ch == "-" || ch == "_" || ch == " " || ch == "/")
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
