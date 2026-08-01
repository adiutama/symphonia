import AppKit
import Foundation

/// Parsed Leader binding from Effective Setting strings like `cmd+shift+p` (ADR 2026-07-23-0009-leader-command-mode / P7.3).
struct LeaderKeyBinding: Equatable {
    /// Single character key (lowercase letter / digit / punctuation as produced by
    /// `NSEvent.charactersIgnoringModifiers`).
    var key: String
    /// Expected modifiers (device-independent: control / option / command / shift).
    var modifiers: NSEvent.ModifierFlags

    /// Parse a binding string. Accepts `ctrl+p`, `control+shift+k`, `⌘k`, `⌃P`, etc.
    static func parse(_ raw: String) -> LeaderKeyBinding? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        var keyToken: String?

        let tokens = trimmed
            .split(whereSeparator: { $0 == "+" || $0 == "-" || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return nil }

        for token in tokens {
            switch token {
            case "ctrl", "control", "⌃":
                modifiers.insert(.control)
            case "cmd", "command", "⌘":
                modifiers.insert(.command)
            case "alt", "option", "opt", "⌥":
                modifiers.insert(.option)
            case "shift", "⇧":
                modifiers.insert(.shift)
            default:
                // Compact glyphs glued to the key (`⌃w`, `⌘⇧p`) — parse before
                // the "last character" fallback, which would drop modifiers.
                if token.count > 1, let compact = Self.parseCompactSymbolToken(token) {
                    modifiers.formUnion(compact.modifiers)
                    keyToken = compact.key
                } else if token.count == 1 {
                    keyToken = token
                } else if Self.modifierNames.contains(token) {
                    continue
                } else if token.count > 1, let last = token.last {
                    keyToken = String(last)
                }
            }
        }

        if keyToken == nil, tokens.count == 1, let only = tokens.first,
           let compact = Self.parseCompactSymbolToken(only)
        {
            modifiers = compact.modifiers
            keyToken = compact.key
        }

        guard let key = keyToken, key.count == 1 else { return nil }
        return LeaderKeyBinding(key: key, modifiers: modifiers)
    }

    /// `⌃w` / `⌘⇧p` → modifiers + key. Returns nil when the token has no leading glyphs.
    private static func parseCompactSymbolToken(
        _ token: String
    ) -> (modifiers: NSEvent.ModifierFlags, key: String)? {
        let symbols: [(Character, NSEvent.ModifierFlags)] = [
            ("⌃", .control), ("⌘", .command), ("⌥", .option), ("⇧", .shift),
        ]
        var rest = token
        var parsedMods: NSEvent.ModifierFlags = []
        var changed = true
        while changed, let first = rest.first {
            changed = false
            for (symbol, flag) in symbols where first == symbol {
                parsedMods.insert(flag)
                rest = String(rest.dropFirst())
                changed = true
                break
            }
        }
        guard !parsedMods.isEmpty, rest.count == 1 else { return nil }
        return (parsedMods, rest)
    }

    /// Match a keyDown event against this binding (ignores caps-lock / function / numeric pad noise).
    func matches(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        let eventMods = event.modifierFlags.intersection([.control, .option, .command, .shift])
        let expected = modifiers.intersection([.control, .option, .command, .shift])
        guard eventMods == expected else { return false }

        // Prefer charactersIgnoringModifiers; fall back to keyCode for control chords
        // where AppKit sometimes yields an empty characters string.
        if let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars.count == 1
        {
            return chars == key
        }
        if let mapped = Self.keyCodeToCharacter(event.keyCode) {
            return mapped == key
        }
        return false
    }

    /// Build a binding from a keyDown event. Modifier-only presses return `nil`.
    static func from(event: NSEvent) -> LeaderKeyBinding? {
        guard event.type == .keyDown else { return nil }
        let mods = event.modifierFlags.intersection([.control, .option, .command, .shift])
        if let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars.count == 1,
           let first = chars.first,
           !first.isNewline
        {
            if event.keyCode == 53 { return nil }
            return LeaderKeyBinding(key: chars, modifiers: mods)
        }
        // Control chords can leave charactersIgnoringModifiers empty.
        guard let mapped = keyCodeToCharacter(event.keyCode) else { return nil }
        if event.keyCode == 53 { return nil }
        return LeaderKeyBinding(key: mapped, modifiers: mods)
    }

    /// Persist form: `ctrl+p`, `cmd+shift+k` (parse-compatible).
    var storageString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// Compact UI form: `⌃P`.
    var displaySymbolString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += key.uppercased()
        return s
    }

    private static let modifierNames: Set<String> = [
        "ctrl", "control", "cmd", "command", "alt", "option", "opt", "shift",
    ]

    /// US-layout letter/digit/punctuation keyCodes for control-chord fallback matching.
    private static func keyCodeToCharacter(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 4: return "h"
        case 5: return "g"
        case 6: return "z"
        case 7: return "x"
        case 8: return "c"
        case 9: return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"
        case 31: return "o"
        case 32: return "u"
        case 34: return "i"
        case 35: return "p"
        case 37: return "l"
        case 38: return "j"
        case 40: return "k"
        case 45: return "n"
        case 46: return "m"
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        default: return nil
        }
    }
}
