import Foundation

/// Operator override for one Command's Normal-mode sequence, persisted by Command
/// `id` in Global Setting (`GlobalPreferences.commandBindings`, ADR 0021 CC.3 / ADR 0022).
///
/// `sequence == nil` → derive from title (or `Command.defaultSequence`).
/// `sequence == ""` → explicitly none.
struct CommandBindingOverride: Codable, Equatable, Sendable {
    /// Optional Normal-mode sequence override (min 2, no `j`/`k`).
    var sequence: String?

    init(sequence: String? = nil) {
        self.sequence = sequence
    }
}

/// Resolves **effective** Command sequences: Operator override (Global Setting)
/// if present, otherwise the Command's own default (ADR 0021 CC.3 / ADR 0022).
enum CommandBindingResolver {
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
            // Empty string = explicitly no sequence (e.g. Dismiss). Do not title-derive.
            if explicit.isEmpty { return nil }
            return CommandSequence.sanitize(explicit)
        }
        return CommandSequence.defaultFromTitle(command.title)
    }

    /// Canonical sequence key for conflict checks.
    static func sequenceConflictKey(_ raw: String) -> String? {
        let sanitized = CommandSequence.sanitize(raw)
        guard CommandSequence.isValid(sanitized) else { return nil }
        return sanitized
    }
}
