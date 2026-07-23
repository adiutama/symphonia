import AppKit
import Foundation

/// Parsed Leader binding from Effective Setting strings like `ctrl+p` (ADR 0009 / P7.3).
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
                // Symbol-only tokens (⌃p without separator) already handled via lowercased split;
                // otherwise last non-modifier token is the key.
                if token.count == 1 {
                    keyToken = token
                } else if Self.modifierNames.contains(token) {
                    continue
                } else if token.count > 1 {
                    // e.g. "ctrlp" without separator — take last character as key if prefixed.
                    keyToken = String(token.last!)
                }
            }
        }

        // Compact forms: "⌃p", "⌘k" (no separator) — characters may arrive as one token after lowercasing.
        if keyToken == nil, tokens.count == 1, let only = tokens.first, only.count >= 2 {
            let symbols: [(Character, NSEvent.ModifierFlags)] = [
                ("⌃", .control), ("⌘", .command), ("⌥", .option), ("⇧", .shift),
            ]
            var rest = only
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
            if !parsedMods.isEmpty, rest.count == 1 {
                modifiers = parsedMods
                keyToken = rest
            }
        }

        guard let key = keyToken, key.count == 1 else { return nil }
        return LeaderKeyBinding(key: key, modifiers: modifiers)
    }

    /// Match a keyDown event against this binding (ignores caps-lock / function / numeric pad noise).
    func matches(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        let relevant: NSEvent.ModifierFlags = [.control, .option, .command, .shift]
        let eventMods = event.modifierFlags.intersection(relevant)
        let expected = modifiers.intersection(relevant)
        guard eventMods == expected else { return false }

        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              chars.count == 1
        else { return false }
        return chars == key
    }

    private static let modifierNames: Set<String> = [
        "ctrl", "control", "cmd", "command", "alt", "option", "opt", "shift",
    ]
}
