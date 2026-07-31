import AppKit
import Combine
import Foundation

/// Leader → Command Center (ADR 0009 / 0021 / 0022): Normal / Input modes, sequences, nests.
///
/// Uses an AppKit local keyDown monitor so Ghostty first-responder PTYs never see
/// Leader chords or in-mode keystrokes. Effective `leaderKey` is re-parsed each event.
/// Fixed Hotkeys live in `KeymapBindings`.
@MainActor
final class CommandCenterController: ObservableObject {
    private let preferences: PreferencesController
    private let workspaces: WorkspaceController
    private let worktrees: WorktreeController
    private let overlays: OverlayController
    private let activities: ActivityManager
    private let settingsNavigation: SettingsNavigation

    @Published private(set) var isActive = false
    @Published private(set) var phase: CommandCenterPhase = .root
    @Published private(set) var mode: CommandCenterMode = .input
    @Published private(set) var items: [CommandCenterItem] = []
    @Published var selectedIndex: Int = 0
    /// Shared buffer: filter text in Input, sequence prefix in Normal.
    @Published var filterQuery: String = ""
    /// In-palette status line (e.g. Overlay Switcher after Close Overlay). Cleared on enter.
    @Published var lastInfo: String?

    private var localMonitor: Any?
    private weak var savedFirstResponder: NSResponder?
    private var cancellables = Set<AnyCancellable>()
    private var nestCatalog: CommandCenterNestCatalog
    private let rootCatalog: CommandCenterRootCatalog

    init(
        preferences: PreferencesController,
        workspaces: WorkspaceController,
        worktrees: WorktreeController,
        overlays: OverlayController,
        activities: ActivityManager,
        settingsNavigation: SettingsNavigation,
        commandRegistry: CommandRegistry
    ) {
        self.preferences = preferences
        self.workspaces = workspaces
        self.worktrees = worktrees
        self.overlays = overlays
        self.activities = activities
        self.settingsNavigation = settingsNavigation
        self.nestCatalog = CommandCenterNestCatalog(
            workspaces: workspaces,
            worktrees: worktrees,
            overlays: overlays
        )
        self.rootCatalog = CommandCenterRootCatalog(
            commandRegistry: commandRegistry,
            preferences: preferences,
            worktrees: worktrees,
            overlays: overlays
        )

        Publishers.CombineLatest4(
            workspaces.$workspaces,
            worktrees.$worktrees,
            overlays.$sessions,
            preferences.$preferences
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive else { return }
                self.rebuildItems(resetSelection: false)
            }
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
        nestCatalog.resetSequences()

        // Peek ergonomics: while peeking, Leader opens the Overlay nest directly.
        if overlays.isShowingOverlay {
            phase = .pickBackground
            nestCatalog.assignSequences(for: .pickBackground)
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
        nestCatalog.resetSequences()
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
        nestCatalog.resetSequences()
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

    func run(_ action: CommandCenterAction) {
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
            activities.openEditor()
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
                nestCatalog.assignSequences(for: .pickBackground)
                rebuildItems(resetSelection: true)
            }
        }
    }

    private func enterNest(_ nest: CommandCenterPhase) {
        phase = nest
        filterQuery = ""
        nestCatalog.assignSequences(for: nest)
        rebuildItems(resetSelection: true)
    }

    // MARK: - Items

    private func rebuildItems(resetSelection: Bool) {
        switch phase {
        case .root:
            items = rootCatalog.items(mode: mode, filterQuery: filterQuery)
        case .pickWorkspace, .pickWorktree, .pickBackground:
            items = CommandCenterItemFilter.filter(
                nestCatalog.items(for: phase),
                mode: mode,
                query: filterQuery
            )
        }
        if resetSelection || selectedIndex >= items.count {
            selectedIndex = items.isEmpty ? 0 : min(selectedIndex, max(items.count - 1, 0))
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

    private func ensureCommandCenterThenNest(_ nest: CommandCenterPhase) {
        if !isActive {
            isActive = true
            mode = preferences.preferences.commandCenterPreferredMode
            filterQuery = ""
            lastInfo = nil
            nestCatalog.resetSequences()
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

