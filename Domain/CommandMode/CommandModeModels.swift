import Foundation

/// Command Center interaction mode (Path B).
enum CommandCenterMode: String, Codable, Equatable, Sendable, CaseIterable {
    /// Sequence prefix buffer; `j`/`k` move; auto-run on unique exact chord.
    case normal
    /// Title/alias filter buffer; ↑↓ move.
    case input

    var stripLabel: String {
        switch self {
        case .normal: return "NORMAL"
        case .input: return "INPUT"
        }
    }
}

/// Title → default sequence rules and ephemeral nest chords (Path B / Peek).
enum CommandSequence {
    static let minLength = 2
    /// Movement only in Normal — never part of any chord.
    static let reserved: Set<Character> = ["j", "k"]

    /// Default sequence from a command title.
    /// - Single word → double first letter (`Edit` → `ee`)
    /// - Multi word → first letter of each word (`Switch Workspace` → `sw`)
    static func defaultFromTitle(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = cleaned
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "/" })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let firstWord = words.first,
              let first = firstLetter(firstWord)
        else {
            return "xx"
        }

        let raw: String
        if words.count == 1 {
            raw = String(repeating: first, count: minLength)
        } else {
            raw = words.compactMap { firstLetter($0) }.joined()
        }
        return sanitize(raw)
    }

    /// Assign unique ≥2-char chords preferring title-initial style (workspace/worktree nests).
    static func titleStyleChords(for titles: [String], excluding reserved: Set<String> = []) -> [String] {
        var used = reserved
        var result: [String] = []
        for title in titles {
            var candidate = defaultFromTitle(title)
            if used.contains(candidate) || !isValid(candidate) {
                candidate = uniqueRandom(excluding: used)
            }
            used.insert(candidate)
            result.append(candidate)
        }
        return result
    }

    /// Assign unique random ≥2-char chords (Overlay nest siblings). Reshuffle on each enter.
    static func randomChords(count: Int, excluding reserved: Set<String> = []) -> [String] {
        var used = reserved
        var result: [String] = []
        for _ in 0..<count {
            let chord = uniqueRandom(excluding: used)
            used.insert(chord)
            result.append(chord)
        }
        return result
    }

    static func isValid(_ sequence: String) -> Bool {
        let s = sequence.lowercased()
        guard s.count >= minLength else { return false }
        return s.allSatisfy { ($0.isLetter || $0.isNumber) && !reserved.contains($0) }
    }

    static func sanitize(_ raw: String) -> String {
        var chars = Array(
            raw.lowercased().filter { ($0.isLetter || $0.isNumber) && !reserved.contains($0) }
        )
        while chars.count < minLength {
            chars.append("x")
        }
        return String(chars)
    }

    private static func firstLetter(_ word: String) -> String? {
        guard let ch = word.lowercased().first(where: { $0.isLetter || $0.isNumber }) else {
            return nil
        }
        if reserved.contains(ch) { return nil }
        return String(ch)
    }

    private static let alphabet: [Character] = Array("abcdefghilmnopqrstuvwxyz") // no j/k

    private static func uniqueRandom(excluding used: Set<String>) -> String {
        for _ in 0..<500 {
            let a = alphabet.randomElement()!
            let b = alphabet.randomElement()!
            let candidate = String([a, b])
            if !used.contains(candidate) {
                return candidate
            }
        }
        // Exhausted 2-letter space — extend.
        for len in 3...4 {
            for _ in 0..<200 {
                let candidate = String((0..<len).map { _ in alphabet.randomElement()! })
                if !used.contains(candidate) {
                    return candidate
                }
            }
        }
        return "xx"
    }
}

/// One row in the Command Mode palette.
struct CommandModeItem: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    /// Sequence chord shown on the row (Normal mode / nest). Replaces empty-filter modifier shortcuts.
    let sequence: String?
    let action: CommandModeAction

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        sequence: String? = nil,
        action: CommandModeAction
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.sequence = sequence
        self.action = action
    }

    /// Legacy alias used by older call sites / docs.
    var keybind: String? { sequence }
}

/// Actions runnable from Command Mode (ADR 0009 / 0022).
enum CommandModeAction: Equatable {
    case dismiss
    case back
    case openSettings
    case openKeymap
    case switchWorkspace(id: String)
    case focusMainRepo
    case focusWorktree(id: String)
    case newWorkspace
    case newWorktree
    case removeFocusedWorktree
    case removeCurrentWorkspace
    case renameWorkspace
    case renameFocusedWorktree
    case reloadFocusedCLI
    case openEditor
    case createBackground
    case peekBackground(id: UUID)
    case hideOverlay
    case toggleOverlay
    /// Kill a Background Overlay PTY (Overlay Switcher nest only).
    case closeOverlay(id: UUID)
    /// Toggle Status Cue list visibility (C.7).
    case toggleStatusCue
    case cycleNextWorkspace
    case cyclePrevWorkspace
    case cycleNextWorktree
    case cyclePrevWorktree

    /// Drill into a picker list (Workspace / Worktree / Overlay).
    case showWorkspacePicker
    case showWorktreePicker
    case showBackgroundPicker
}

/// Nested palette phase after Leader (root list or a picker).
enum CommandModePhase: Equatable {
    case root
    case pickWorkspace
    case pickWorktree
    case pickBackground

    var phaseTitle: String? {
        switch self {
        case .root: return nil
        case .pickWorkspace: return "Switch Workspace"
        case .pickWorktree: return "Switch Worktree"
        case .pickBackground: return "Overlay Switcher"
        }
    }
}
