import Foundation

/// Operator override for one Command's alias/sequence binding, persisted by Command
/// `id` in Global Setting (`GlobalPreferences.commandBindings`, ADR 0021 CC.3 / Path B).
///
/// Fields are independently optional so "use the Command's default" and
/// "explicitly override with an empty value" are distinguishable:
/// - `aliases == nil` → use `Command.defaultAliases`. `aliases == ""` → no aliases.
/// - `sequence == nil` → derive from title (or `Command.defaultSequence`). `sequence == ""` → none.
/// - `shortcut` is legacy (empty-filter modifier chords); ignored by Path B Normal mode.
struct CommandBindingOverride: Codable, Equatable, Sendable {
    var aliases: String?
    /// Optional Normal-mode sequence override (min 2, no `j`/`k`).
    var sequence: String?
    /// Legacy empty-filter modifier chord. Kept for TOML compatibility; not the primary power path.
    var shortcut: String?

    init(aliases: String? = nil, sequence: String? = nil, shortcut: String? = nil) {
        self.aliases = aliases
        self.sequence = sequence
        self.shortcut = shortcut
    }
}

/// Resolves **effective** Command aliases/sequences: Operator override (Global Setting)
/// if present, otherwise the Command's own default (ADR 0021 CC.3 / Path B).
enum CommandBindingResolver {
    /// Effective aliases for `command` given the Operator's `overrides` map.
    static func aliases(
        for command: Command,
        overrides: [String: CommandBindingOverride]
    ) -> [String] {
        guard let raw = overrides[command.id]?.aliases else {
            return command.defaultAliases
        }
        return parseAliases(raw)
    }

    /// Effective Normal-mode sequence. `nil` means no sequence.
    static func sequence(
        for command: Command,
        overrides: [String: CommandBindingOverride]
    ) -> String? {
        if let override = overrides[command.id]?.sequence {
            if override.isEmpty { return nil }
            return CommandSequence.sanitize(override)
        }
        if let explicit = command.defaultSequence {
            return CommandSequence.sanitize(explicit)
        }
        return CommandSequence.defaultFromTitle(command.title)
    }

    /// Legacy Command Center shortcut (modifier chord). Kept for Settings migration display.
    static func shortcut(
        for command: Command,
        overrides: [String: CommandBindingOverride]
    ) -> String? {
        let raw: String?
        if let override = overrides[command.id]?.shortcut {
            raw = override.isEmpty ? nil : override
        } else {
            raw = command.defaultShortcut
        }
        guard let raw else { return nil }
        return normalizeShortcut(raw)
    }

    /// Display form for a shortcut storage string (`⌃W`).
    static func shortcutDisplay(_ raw: String?) -> String? {
        guard let raw, let binding = LeaderKeyBinding.parse(raw) else { return raw }
        return binding.displaySymbolString
    }

    /// Normalize storage: bare `w` / `,` → `ctrl+w` / `ctrl+,` (legacy empty-filter keys).
    static func normalizeShortcut(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if let binding = LeaderKeyBinding.parse(trimmed),
           !binding.modifiers.isEmpty
        {
            return binding.storageString
        }
        if trimmed.count == 1 {
            return "ctrl+\(trimmed.lowercased())"
        }
        return trimmed
    }

    /// Canonical key for conflict checks (normalized chord storage).
    static func shortcutConflictKey(_ raw: String) -> String? {
        let normalized = normalizeShortcut(raw)
        guard let binding = LeaderKeyBinding.parse(normalized),
              !binding.modifiers.intersection([.control, .option, .command]).isEmpty
        else { return nil }
        return binding.storageString
    }

    /// Canonical sequence key for conflict checks.
    static func sequenceConflictKey(_ raw: String) -> String? {
        let sanitized = CommandSequence.sanitize(raw)
        guard CommandSequence.isValid(sanitized) else { return nil }
        return sanitized
    }

    /// Splits Operator-facing comma-separated alias text into trimmed, non-empty aliases.
    static func parseAliases(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
