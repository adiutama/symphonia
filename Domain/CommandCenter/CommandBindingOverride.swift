import Foundation

/// Operator override for one Command's alias/shortcut binding, persisted by Command
/// `id` in Global Setting (`GlobalPreferences.commandBindings`, ADR 0021 CC.3).
///
/// Both fields are independently optional so "use the Command's default" and
/// "explicitly override with an empty value" are distinguishable:
/// - `aliases == nil` → use `Command.defaultAliases`. `aliases == ""` → no aliases.
///   Any other string is split on `,` (CONTEXT.md "Command Alias" free-text form).
/// - `shortcut == nil` → use `Command.defaultShortcut`. `shortcut == ""` → explicitly
///   no shortcut. Any other string is the override shortcut key.
struct CommandBindingOverride: Codable, Equatable, Sendable {
    var aliases: String?
    var shortcut: String?

    init(aliases: String? = nil, shortcut: String? = nil) {
        self.aliases = aliases
        self.shortcut = shortcut
    }
}

/// Resolves **effective** Command aliases/shortcuts: Operator override (Global Setting)
/// if present, otherwise the Command's own default (ADR 0021 CC.3).
///
/// No Workspace-level override in this slice (ADR 0021 non-goal); conflict validation
/// across Commands is CC.4.
enum CommandBindingResolver {
    /// Effective aliases for `command` given the Operator's `overrides` map
    /// (`GlobalPreferences.commandBindings`, keyed by `Command.id`).
    static func aliases(
        for command: Command,
        overrides: [String: CommandBindingOverride]
    ) -> [String] {
        guard let raw = overrides[command.id]?.aliases else {
            return command.defaultAliases
        }
        return parseAliases(raw)
    }

    /// Effective Command Center shortcut for `command` given the Operator's `overrides`.
    /// `nil` means no shortcut; an override of `""` explicitly clears the default.
    /// Bare single-character legacy values are treated as `ctrl+<char>` (L2 migration).
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

    /// Splits Operator-facing comma-separated alias text into trimmed, non-empty aliases.
    static func parseAliases(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
