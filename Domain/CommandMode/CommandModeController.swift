import AppKit
import Combine
import Foundation

/// Leader → Command Center Path B (ADR 0009 / 0021): Normal / Input modes, sequences, nests.
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
    private let commandRegistry: CommandRegistry

    @Published private(set) var isActive = false
    @Published private(set) var phase: CommandModePhase = .root
    @Published private(set) var mode: CommandCenterMode = .input
    @Published private(set) var items: [CommandModeItem] = []
    @Published var selectedIndex: Int = 0
    /// Shared buffer: filter text in Input, sequence prefix in Normal.
    @Published var filterQuery: String = ""
    @Published var lastInfo: String?

    private var localMonitor: Any?
    private weak var savedFirstResponder: NSResponder?
    private var cancellables = Set<AnyCancellable>()
    /// Ephemeral nest chords assigned when entering a picker phase.
    private var nestSequences: [String: String] = [:]

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
        mode = preferences.preferences.commandCenterPreferredMode
        filterQuery = ""
        lastInfo = nil
        nestSequences = [:]

        // Peek ergonomics: while peeking, Leader opens the Overlay nest directly.
        if overlays.isShowingOverlay {
            phase = .pickBackground
            assignNestSequences(for: .pickBackground)
        } else {
            phase = .root
        }

        resignTerminalFocus()
        rebuildItems(resetSelection: true)
    }

    func dismiss() {
        guard isActive else { return }
        isActive = false
        phase = .root
        filterQuery = ""
        nestSequences = [:]
        items = []
        selectedIndex = 0
        restoreTerminalFocus()
    }

    func setFilter(_ query: String) {
        filterQuery = query
        rebuildItems(resetSelection: true)
        maybeAutoRun()
    }

    func toggleMode() {
        mode = mode == .normal ? .input : .normal
        filterQuery = ""
        rebuildItems(resetSelection: true)
    }

    func leaveNestToRoot() {
        phase = .root
        filterQuery = ""
        nestSequences = [:]
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
            leaveNestToRoot()

        case .openSettings:
            settingsNavigation.openSettings()
            lastInfo = "Settings"
            dismiss()

        case .showWorkspacePicker:
            enterNest(.pickWorkspace)

        case .showWorktreePicker:
            enterNest(.pickWorktree)

        case .showBackgroundPicker:
            enterNest(.pickBackground)

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
            lastInfo = "Confirm Discard Tree"
            dismiss()

        case .removeCurrentWorkspace:
            guard let current = workspaces.current else {
                lastInfo = "No Workspace selected"
                dismiss()
                return
            }
            workspaces.requestRemove(current)
            lastInfo = "Confirm Discard Workspace"
            dismiss()

        case .renameWorkspace:
            guard let current = workspaces.current else {
                lastInfo = "No Workspace selected"
                dismiss()
                return
            }
            workspaces.beginRename(current)
            lastInfo = "Rename Slug"
            dismiss()

        case .renameFocusedWorktree:
            guard let focused = worktrees.focused else {
                lastInfo = "Focus a Worktree first"
                dismiss()
                return
            }
            worktrees.beginRename(focused)
            lastInfo = "Rename Tree"
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

        case .closeOverlay(let id):
            overlays.close(id)
            lastInfo = "Closed Overlay"
            if overlays.focusedSessions.isEmpty {
                dismiss()
            } else {
                filterQuery = ""
                assignNestSequences(for: .pickBackground)
                rebuildItems(resetSelection: true)
            }

        case .toggleStatusCue:
            let key = StatusCueDefaults.listVisibleKey
            let next = !UserDefaults.standard.bool(forKey: key)
            UserDefaults.standard.set(next, forKey: key)
            lastInfo = next ? "Status cue on" : "Status cue off"
            dismiss()
        }
    }

    private func enterNest(_ nest: CommandModePhase) {
        phase = nest
        filterQuery = ""
        assignNestSequences(for: nest)
        rebuildItems(resetSelection: true)
    }

    // MARK: - Items

    private func rebuildItems(resetSelection: Bool) {
        switch phase {
        case .root:
            items = filteredRootItems()
        case .pickWorkspace:
            items = filterNest(workspacePickerItems())
        case .pickWorktree:
            items = filterNest(worktreePickerItems())
        case .pickBackground:
            items = filterNest(backgroundPickerItems())
        }
        if resetSelection || selectedIndex >= items.count {
            selectedIndex = items.isEmpty ? 0 : min(selectedIndex, max(items.count - 1, 0))
        }
    }

    private func filteredRootItems() -> [CommandModeItem] {
        let context = CommandContext(worktrees: worktrees, overlays: overlays)
        let commands = commandRegistry.availableCommands(context: context)
            .filter { $0.action != .dismiss }
        let overrides = preferences.preferences.commandBindings

        switch mode {
        case .input:
            let query = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matched = query.isEmpty
                ? commands
                : commands.filter { matches($0, query: query, overrides: overrides) }
            return matched.map { commandItem($0, overrides: overrides) }

        case .normal:
            let seq = filterQuery.lowercased()
            let mapped = commands.map { commandItem($0, overrides: overrides) }
            guard !seq.isEmpty else { return mapped }
            return mapped.filter { item in
                guard let chord = item.sequence?.lowercased() else { return false }
                return chord.hasPrefix(seq)
            }
        }
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
            sequence: CommandBindingResolver.sequence(for: command, overrides: overrides),
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

    private func filterNest(_ raw: [CommandModeItem]) -> [CommandModeItem] {
        switch mode {
        case .input:
            let q = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return raw }
            return raw.filter { item in
                let hay = [item.title, item.subtitle, item.sequence]
                    .compactMap { $0?.lowercased() }
                    .joined(separator: " ")
                return hay.contains(q)
            }
        case .normal:
            let seq = filterQuery.lowercased()
            guard !seq.isEmpty else { return raw }
            return raw.filter { item in
                guard let chord = item.sequence?.lowercased() else { return false }
                return chord.hasPrefix(seq)
            }
        }
    }

    private func maybeAutoRun() {
        guard mode == .normal else { return }
        let seq = filterQuery.lowercased()
        guard seq.count >= CommandSequence.minLength else { return }
        let exact = items.filter { $0.sequence?.lowercased() == seq }
        if exact.count == 1, let only = exact.first {
            run(only.action)
        }
    }

    // MARK: - Nest builders

    private func assignNestSequences(for nest: CommandModePhase) {
        nestSequences = [:]
        let raw: [CommandModeItem]
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
                nestSequences[item.id] = chord
            }
            return
        }
        // Workspace / Worktree: prefer title-initial style.
        let chords = CommandSequence.titleStyleChords(for: raw.map(\.title))
        for (item, chord) in zip(raw, chords) {
            nestSequences[item.id] = chord
        }
    }

    private func withNestSequence(_ item: CommandModeItem) -> CommandModeItem {
        let chord: String
        if let existing = nestSequences[item.id] {
            chord = existing
        } else {
            // Rows that appear after nest enter (e.g. Close Overlay) get a fresh chord.
            let used = Set(nestSequences.values)
            chord = CommandSequence.randomChords(count: 1, excluding: used).first ?? "xx"
            nestSequences[item.id] = chord
        }
        return CommandModeItem(
            id: item.id,
            title: item.title,
            subtitle: item.subtitle,
            sequence: chord,
            action: item.action
        )
    }

    private func workspacePickerItems() -> [CommandModeItem] {
        workspacePickerItemsRaw().map(withNestSequence)
    }

    private func workspacePickerItemsRaw() -> [CommandModeItem] {
        var list: [CommandModeItem] = []
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
        worktreePickerItemsRaw().map(withNestSequence)
    }

    private func worktreePickerItemsRaw() -> [CommandModeItem] {
        var list: [CommandModeItem] = []
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

    /// Overlay nest: siblings + Back (hide) + Close Overlay — no main-catalog duplication.
    private func backgroundPickerItems() -> [CommandModeItem] {
        backgroundPickerItemsRaw().map(withNestSequence)
    }

    private func backgroundPickerItemsRaw() -> [CommandModeItem] {
        var list: [CommandModeItem] = []
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
                let kindLabel = session.kind == .editor ? "EDITOR" : "BG"
                list.append(CommandModeItem(
                    id: "bg-\(session.id.uuidString)",
                    title: session.title + mark,
                    subtitle: kindLabel,
                    action: .peekBackground(id: session.id)
                ))
            }
        }

        // Product Back = hide Overlay → Main CLI (not Esc leave-nest).
        list.append(CommandModeItem(
            id: "bg-hide",
            title: "Back",
            subtitle: "Hide Overlay · Main CLI",
            action: .hideOverlay
        ))

        if let visible = overlays.visibleSession, visible.kind == .background {
            list.append(CommandModeItem(
                id: "bg-close",
                title: "Close Overlay",
                subtitle: "Kill Background PTY",
                action: .closeOverlay(id: visible.id)
            ))
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

        // ⇧Tab toggles Normal ↔ Input (never Esc).
        if event.keyCode == 48, event.modifierFlags.contains(.shift) {
            toggleMode()
            return nil
        }

        if event.keyCode == 53 { // Escape — never flips mode
            if !filterQuery.isEmpty {
                filterQuery = ""
                rebuildItems(resetSelection: true)
            } else if phase != .root {
                leaveNestToRoot()
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
        case 125: // down — Input (and always allowed)
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

        let mods = event.modifierFlags.intersection([.control, .option, .command])
        guard mods.isEmpty,
              let chars = event.charactersIgnoringModifiers,
              chars.count == 1,
              let ch = chars.first
        else {
            return nil
        }

        if mode == .normal {
            let lower = Character(ch.lowercased())
            if lower == "j" {
                moveSelection(1)
                return nil
            }
            if lower == "k" {
                moveSelection(-1)
                return nil
            }
            if ch.isLetter || ch.isNumber {
                filterQuery.append(Character(ch.lowercased()))
                rebuildItems(resetSelection: true)
                maybeAutoRun()
                return nil
            }
        } else {
            // Input: type-to-filter
            if ch.isLetter || ch.isNumber || ch == "," || ch == "." || ch == "-" || ch == "_" || ch == " " || ch == "/" {
                filterQuery.append(ch)
                rebuildItems(resetSelection: true)
                return nil
            }
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
