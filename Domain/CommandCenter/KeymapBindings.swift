import AppKit
import Foundation

/// Single source of truth for Operator chords that are not Normal-mode sequences (ADR 0022).
///
/// Matched by `CommandCenterController`; listed by `KeymapCheatsheetView` and Settings Hotkeys.
/// Sequences come from `CommandRegistry` + `CommandBindingResolver`.
enum KeymapBindings {
    enum Scope: String {
        case global
        case commandCenterOnly
    }

    /// One chord → action binding (globals and Command Center–only).
    struct Chord: Identifiable, Equatable {
        var id: String { "\(scope.rawValue)-\(display)-\(titleFallback)" }
        let display: String
        let titleFallback: String
        let action: CommandCenterAction
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

    static func globalAction(for event: NSEvent) -> CommandCenterAction? {
        globalChords.first(where: { $0.matches(event) })?.action
    }

    static func commandCenterOnlyAction(for event: NSEvent) -> CommandCenterAction? {
        commandCenterOnlyChords.first(where: { $0.matches(event) })?.action
    }

    /// Display string for a Command's fixed modifier chord, if any (ADR 0022).
    /// Settings Hotkey column is read-only from this — Operator overrides do not apply.
    static func hotkeyDisplay(for action: CommandCenterAction) -> String? {
        if let chord = globalChords.first(where: { $0.action == action }) {
            return chord.display
        }
        return commandCenterOnlyChords.first(where: { $0.action == action })?.display
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
        _ action: CommandCenterAction,
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
