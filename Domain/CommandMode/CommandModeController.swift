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
    /// In-palette status line (e.g. Overlay Switcher after Close Overlay). Cleared on enter.
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
            dismiss()

        case .openKeymap:
            settingsNavigation.toggleKeymap()
            if isActive { dismiss() }

        case .showWorkspacePicker:
            ensureCommandCenterThenNest(.pickWorkspace)

        case .showWorktreePicker:
            ensureCommandCenterThenNest(.pickWorktree)

        case .showBackgroundPicker:
            openOverlaySwitcher()

        case .newWorkspace:
            workspaces.beginCreateWorkspace()
            dismiss()

        case .switchWorkspace(let id):
            if let summary = workspaces.workspaces.first(where: { $0.id == id }) {
                workspaces.select(summary)
            }
            dismiss()

        case .cycleNextWorkspace:
            workspaces.cycleWorkspace(delta: 1)
            dismiss()

        case .cyclePrevWorkspace:
            workspaces.cycleWorkspace(delta: -1)
            dismiss()

        case .cycleNextWorktree:
            worktrees.cycleWorktree(delta: 1)
            dismiss()

        case .cyclePrevWorktree:
            worktrees.cycleWorktree(delta: -1)
            dismiss()

        case .focusMainRepo:
            guard let current = workspaces.current else {
                dismiss()
                return
            }
            worktrees.focusMain(for: current)
            dismiss()

        case .focusWorktree(let id):
            if let wt = worktrees.worktrees.first(where: { $0.id == id }) {
                worktrees.focus(wt)
            }
            dismiss()

        case .newWorktree:
            guard workspaces.current != nil else {
                dismiss()
                return
            }
            worktrees.beginCreateWorktree()
            dismiss()

        case .removeFocusedWorktree:
            guard let focused = worktrees.focused else {
                dismiss()
                return
            }
            worktrees.requestRemove(focused)
            dismiss()

        case .removeCurrentWorkspace:
            guard let current = workspaces.current else {
                dismiss()
                return
            }
            workspaces.requestRemove(current)
            dismiss()

        case .renameWorkspace:
            guard let current = workspaces.current else {
                dismiss()
                return
            }
            workspaces.beginRename(current)
            dismiss()

        case .renameFocusedWorktree:
            guard let focused = worktrees.focused else {
                dismiss()
                return
            }
            worktrees.beginRename(focused)
            dismiss()

        case .reloadFocusedCLI:
            worktrees.respawnWithCurrentSecrets()
            dismiss()

        case .openEditor:
            overlays.openEditor()
            dismiss()

        case .createBackground:
            overlays.createBackgroundCLI()
            dismiss()

        case .peekBackground(let id):
            overlays.peek(id)
            dismiss()

        case .hideOverlay:
            overlays.hide()
            dismiss()

        case .toggleOverlay:
            overlays.toggle()
            dismiss()

        case .closeOverlay(let id):
            overlays.close(id)
            // Stay in Overlay Switcher with feedback when more sessions remain.
            lastInfo = "Closed Overlay"
            if overlays.focusedSessions.isEmpty {
                dismiss()
            } else {
                filterQuery = ""
                assignNestSequences(for: .pickBackground)
                rebuildItems(resetSelection: true)
            }
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
            .filter { command in
                switch command.action {
                case .dismiss,
                     .cycleNextWorkspace, .cyclePrevWorkspace,
                     .cycleNextWorktree, .cyclePrevWorktree:
                    return false
                default:
                    return true
                }
            }
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
        if let sequence = CommandBindingResolver.sequence(for: command, overrides: overrides) {
            return sequence.lowercased().contains(query)
        }
        return false
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
        case "overlay.toggle":
            return overlays.isShowingOverlay
                ? overlays.visibleSession?.title
                : "Main CLI"
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
        if let current = workspaces.current {
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
        } else {
            list.append(CommandModeItem(
                id: "wt-nows",
                title: "(select a Workspace first)",
                action: .back
            ))
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
            subtitle: "Main CLI · process stays alive",
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

        // Keymap toggle works whether Command Center is open or not.
        if KeymapBindings.isKeymapToggle(event) {
            run(.openKeymap)
            return nil
        }

        if !isActive {
            if let binding, binding.matches(event) {
                enter()
                return nil
            }
            if handleGlobalShortcut(event) {
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

        // ⌃N / ⌃P / ⌃U — both modes (ADR 0022).
        if handleCommandCenterControlKeys(event) {
            return nil
        }

        // CC-only modifier chords (ADR 0022).
        if handleCommandCenterOnlyShortcut(event) {
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

    /// ⌃N / ⌃P move selection; ⌃U clears buffer (both Normal and Input).
    private func handleCommandCenterControlKeys(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.control),
              !mods.contains(.command),
              !mods.contains(.option)
        else { return false }
        let chars = (event.charactersIgnoringModifiers ?? "").lowercased()
        switch chars {
        case "n":
            moveSelection(1)
            return true
        case "p":
            moveSelection(-1)
            return true
        case "u":
            if !filterQuery.isEmpty {
                filterQuery = ""
                rebuildItems(resetSelection: true)
            }
            return true
        default:
            return false
        }
    }

    /// Command Center–only chords from `KeymapBindings`.
    private func handleCommandCenterOnlyShortcut(_ event: NSEvent) -> Bool {
        guard let action = KeymapBindings.commandCenterOnlyAction(for: event) else { return false }
        run(action)
        return true
    }

    /// Global shortcuts when Command Center is inactive (`KeymapBindings`).
    @discardableResult
    private func handleGlobalShortcut(_ event: NSEvent) -> Bool {
        // Keymap toggle handled earlier for all states.
        guard let action = KeymapBindings.globalAction(for: event),
              action != .openKeymap
        else { return false }
        if action == .showBackgroundPicker {
            openOverlaySwitcher()
        } else {
            run(action)
        }
        return true
    }

    /// Open Command Center directly into Overlay Switcher nest.
    private func openOverlaySwitcher() {
        ensureCommandCenterThenNest(.pickBackground)
    }

    private func ensureCommandCenterThenNest(_ nest: CommandModePhase) {
        if !isActive {
            isActive = true
            mode = preferences.preferences.commandCenterPreferredMode
            filterQuery = ""
            lastInfo = nil
            nestSequences = [:]
            resignTerminalFocus()
        }
        enterNest(nest)
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

// MARK: - KeymapBindings (globals / CC-only chords; ADR 0022)

/// Single source of truth for Operator chords that are not Normal-mode sequences.
///
/// Matched by `CommandModeController`; listed by `KeymapCheatsheetView`.
/// Sequences come from `CommandRegistry` + `CommandBindingResolver`.
enum KeymapBindings {
    enum Scope: String {
        case global
        case commandCenterOnly
    }

    /// One chord → action binding (globals and CC-only).
    struct Chord: Identifiable, Equatable {
        var id: String { "\(scope.rawValue)-\(display)-\(titleFallback)" }
        let display: String
        let titleFallback: String
        let action: CommandModeAction
        let scope: Scope
        let matches: (NSEvent) -> Bool

        static func == (lhs: Chord, rhs: Chord) -> Bool {
            lhs.display == rhs.display
                && lhs.titleFallback == rhs.titleFallback
                && lhs.action == rhs.action
                && lhs.scope == rhs.scope
        }
    }

    /// Fixed Command Center navigation (not Commands).
    struct ChromeRow: Identifiable, Equatable {
        let id: String
        let title: String
        let display: String
    }

    /// macOS / AppKit window life (not Symphonia Commands).
    static let systemWindowRows: [(title: String, display: String)] = [
        ("Quit", "⌘Q"),
        ("Hide Symphonia", "⌘H"),
        ("Hide Others", "⌥⌘H"),
        ("Minimize", "⌘M"),
        ("Close Window", "⌘W"),
    ]

    static let commandCenterChrome: [ChromeRow] = [
        ChromeRow(id: "shift-tab", title: "Toggle Normal ↔ Input", display: "⇧Tab"),
        ChromeRow(id: "esc", title: "Clear / leave nest / dismiss", display: "Esc"),
        ChromeRow(id: "leader", title: "Dismiss", display: "Leader again"),
        ChromeRow(id: "arrows", title: "Move selection", display: "↑ ↓"),
        ChromeRow(id: "ctrl-np", title: "Move selection", display: "⌃N / ⌃P"),
        ChromeRow(id: "return", title: "Run selected", display: "↩"),
        ChromeRow(id: "delete", title: "Delete last char", display: "⌫"),
        ChromeRow(id: "jk", title: "Move (Normal)", display: "j / k"),
        ChromeRow(id: "ctrl-u", title: "Clear buffer", display: "⌃U"),
    ]

    static let globalChords: [Chord] = [
        chord("⌘,", "Settings", .openSettings, .global) { e in
            cmdOnly(e) && !shift(e) && char(e) == ","
        },
        chord("⌘⇧/", "Keymap", .openKeymap, .global, matches: isKeymapToggle),
        chord("⌘N", "New Workspace", .newWorkspace, .global) { e in
            cmdOnly(e) && !shift(e) && char(e) == "n"
        },
        chord("⌘T", "New Worktree", .newWorktree, .global) { e in
            cmdOnly(e) && !shift(e) && char(e) == "t"
        },
        chord("⌃⇥", "Next Workspace", .cycleNextWorkspace, .global) { e in
            ctrlTab(e) && !shift(e)
        },
        chord("⌃⇧⇥", "Previous Workspace", .cyclePrevWorkspace, .global) { e in
            ctrlTab(e) && shift(e)
        },
        chord("⌘]", "Next Worktree", .cycleNextWorktree, .global) { e in
            cmdOnly(e) && !shift(e) && char(e) == "]"
        },
        chord("⌘[", "Previous Worktree", .cyclePrevWorktree, .global) { e in
            cmdOnly(e) && !shift(e) && char(e) == "["
        },
        chord("⌘⇧M", "Focus Main", .focusMainRepo, .global) { e in
            cmdOnly(e) && shift(e) && char(e) == "m"
        },
        chord("⌘E", "Open Editor", .openEditor, .global) { e in
            cmdOnly(e) && !shift(e) && char(e) == "e"
        },
        chord("⌘J", "Overlay Terminal", .createBackground, .global) { e in
            cmdOnly(e) && !shift(e) && char(e) == "j"
        },
        chord("⌘⇧O", "Overlay Switcher", .showBackgroundPicker, .global) { e in
            cmdOnly(e) && shift(e) && char(e) == "o"
        },
        chord("⌘⇧E", "Toggle Overlay", .toggleOverlay, .global) { e in
            cmdOnly(e) && shift(e) && char(e) == "e"
        },
        chord("⌘R", "Reload CLI", .reloadFocusedCLI, .global) { e in
            cmdOnly(e) && !shift(e) && char(e) == "r"
        },
    ]

    static let commandCenterOnlyChords: [Chord] = [
        chord("⌘O", "Switch Workspace", .showWorkspacePicker, .commandCenterOnly) { e in
            cmdOnly(e) && !shift(e) && !opt(e) && char(e) == "o"
        },
        chord("⌘⇧F", "Switch Worktree", .showWorktreePicker, .commandCenterOnly) { e in
            cmdOnly(e) && shift(e) && !opt(e) && char(e) == "f"
        },
        chord("⌘⇧R", "Rename Slug", .renameWorkspace, .commandCenterOnly) { e in
            cmdOnly(e) && shift(e) && !opt(e) && char(e) == "r"
        },
        chord("⌘⌥R", "Rename Tree", .renameFocusedWorktree, .commandCenterOnly) { e in
            cmdOnly(e) && !shift(e) && opt(e) && char(e) == "r"
        },
        chord("⌘⇧⌫", "Discard Tree", .removeFocusedWorktree, .commandCenterOnly) { e in
            cmdOnly(e) && shift(e) && !opt(e) && e.keyCode == 51
        },
        chord("⌘⌥⌫", "Discard Workspace", .removeCurrentWorkspace, .commandCenterOnly) { e in
            cmdOnly(e) && !shift(e) && opt(e) && e.keyCode == 51
        },
    ]

    static func globalAction(for event: NSEvent) -> CommandModeAction? {
        globalChords.first(where: { $0.matches(event) })?.action
    }

    static func commandCenterOnlyAction(for event: NSEvent) -> CommandModeAction? {
        commandCenterOnlyChords.first(where: { $0.matches(event) })?.action
    }

    static func isKeymapToggle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command),
              mods.contains(.shift),
              !mods.contains(.control),
              !mods.contains(.option)
        else { return false }
        let chars = (event.charactersIgnoringModifiers ?? "").lowercased()
        return chars == "/" || chars == "?" || event.keyCode == 44
    }

    private static func chord(
        _ display: String,
        _ title: String,
        _ action: CommandModeAction,
        _ scope: Scope,
        matches: @escaping (NSEvent) -> Bool
    ) -> Chord {
        Chord(display: display, titleFallback: title, action: action, scope: scope, matches: matches)
    }

    private static func mods(_ event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    private static func shift(_ event: NSEvent) -> Bool { mods(event).contains(.shift) }
    private static func opt(_ event: NSEvent) -> Bool { mods(event).contains(.option) }

    private static func char(_ event: NSEvent) -> String {
        (event.charactersIgnoringModifiers ?? "").lowercased()
    }

    private static func cmdOnly(_ event: NSEvent) -> Bool {
        let m = mods(event)
        return m.contains(.command) && !m.contains(.control) && !m.contains(.option)
    }

    private static func ctrlTab(_ event: NSEvent) -> Bool {
        let m = mods(event)
        return m.contains(.control)
            && !m.contains(.command)
            && !m.contains(.option)
            && event.keyCode == 48
    }
}
