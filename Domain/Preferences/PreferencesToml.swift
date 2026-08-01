import Foundation

/// Minimal TOML codec for Symphonia config files (T.1–T.3).
///
/// Scoped to our known shapes (string / bool / int keys, nested tables for maps) so Global /
/// Workspace / Secret Store / workspace-index TOML stays hand-editable without a C++ SPM dep.
/// Not a full TOML 1.0 implementation — extend as needed.
enum PreferencesToml {
    /// Encode Global Setting to hand-editable TOML.
    static func encode(_ preferences: GlobalPreferences) -> String {
        var lines: [String] = [
            "# Symphonia global preferences — hand-editable.",
            "# Missing file → app defaults. Corrupt file → load error (fix or delete).",
            "# Legacy preferences.json is ignored (no migration).",
            "",
            "mainCLICommand = \(stringLiteral(preferences.mainCLICommand))",
            "shellCommand = \(stringLiteral(preferences.shellCommand))",
            "editorCommand = \(stringLiteral(preferences.editorCommand))",
        ]
        if let presentation = preferences.editorPresentation {
            lines.append("editorPresentation = \(stringLiteral(presentation.tomlValue))")
        }
        lines += [
            "editorBundleID = \(stringLiteral(preferences.editorBundleID))",
            "fileManagerPresentation = \(stringLiteral(preferences.fileManagerPresentation.tomlValue))",
            "fileManagerCommand = \(stringLiteral(preferences.fileManagerCommand))",
            "fileManagerBundleID = \(stringLiteral(preferences.fileManagerBundleID))",
            "hasSeenExternalEditorReminder = \(boolLiteral(preferences.hasSeenExternalEditorReminder))",
            "leaderKey = \(stringLiteral(preferences.leaderKey))",
            "commandCenterPreferredMode = \(stringLiteral(preferences.commandCenterPreferredMode.rawValue))",
            "workspacesRoot = \(stringLiteral(preferences.workspacesRoot))",
            "baseRef = \(stringLiteral(preferences.baseRef))",
            "onboardingCompleted = \(boolLiteral(preferences.onboardingCompleted))",
            "chromeGlass = \(boolLiteral(preferences.chromeGlass))",
            "updateChannel = \(stringLiteral(preferences.updateChannel.rawValue))",
        ]

        let bindingKeys = preferences.commandBindings.keys.sorted()
        if !bindingKeys.isEmpty {
            lines.append("")
            lines.append("# Command sequences keyed by Command id (ADR 2026-07-24-0021-command-center-registry / 2026-07-25-0022-keyboard-keymap).")
            for id in bindingKeys {
                guard let override = preferences.commandBindings[id] else { continue }
                // Only sequences are Operator-overridable. Ignore leftover shortcut/alias keys.
                guard let sequence = override.sequence else { continue }
                lines.append("")
                lines.append("[commandBindings.\(quotedKey(id))]")
                lines.append("sequence = \(stringLiteral(sequence))")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Decode Global Setting from TOML. Unknown keys ignored; missing fields → defaults.
    static func decodeGlobalPreferences(from text: String) throws -> GlobalPreferences {
        let table = try parse(text)
        let root = table.root

        var bindings: [String: CommandBindingOverride] = [:]
        if let bindingTables = table.tables["commandBindings"] {
            for (id, fields) in bindingTables {
                // Ignore legacy aliases/shortcut TOML keys — Hotkeys come from KeymapBindings.
                bindings[id] = CommandBindingOverride(
                    sequence: fields.strings["sequence"]
                )
            }
        }

        let preferredModeRaw = root.strings["commandCenterPreferredMode"] ?? ""
        let preferredMode = CommandCenterMode(rawValue: preferredModeRaw)
            ?? GlobalPreferences.default.commandCenterPreferredMode

        // Existing TOML without the key → already onboarded. Missing file uses `.default` (false).
        let onboardingCompleted = root.bools["onboardingCompleted"] ?? true
        // Missing key → glass on (Sequence C default).
        let chromeGlass = root.bools["chromeGlass"] ?? true
        let updateChannelRaw = root.strings["updateChannel"] ?? ""
        let updateChannel = UpdateChannel(rawValue: updateChannelRaw) ?? .stable

        return GlobalPreferences(
            mainCLICommand: root.strings["mainCLICommand"] ?? "",
            editorCommand: root.strings["editorCommand"] ?? "",
            shellCommand: root.strings["shellCommand"] ?? "",
            editorPresentation: EditorPresentation.fromToml(root.strings["editorPresentation"]),
            editorBundleID: root.strings["editorBundleID"] ?? ActivityDefaults.editorBundleID,
            fileManagerPresentation: EditorPresentation.fromToml(root.strings["fileManagerPresentation"])
                ?? ActivityDefaults.fileManagerPresentation,
            fileManagerCommand: root.strings["fileManagerCommand"] ?? "",
            fileManagerBundleID: root.strings["fileManagerBundleID"] ?? ActivityDefaults.fileManagerBundleID,
            hasSeenExternalEditorReminder: root.bools["hasSeenExternalEditorReminder"] ?? false,
            leaderKey: root.strings["leaderKey"] ?? GlobalPreferences.default.leaderKey,
            commandCenterPreferredMode: preferredMode,
            workspacesRoot: root.strings["workspacesRoot"] ?? GlobalPreferences.default.workspacesRoot,
            baseRef: root.strings["baseRef"] ?? GlobalPreferences.default.baseRef,
            commandBindings: bindings,
            onboardingCompleted: onboardingCompleted,
            chromeGlass: chromeGlass,
            updateChannel: updateChannel
        )
    }

    /// Encode Workspace Setting to hand-editable TOML (T.2).
    static func encode(_ config: WorkspaceConfig) -> String {
        var lines: [String] = [
            "# Symphonia workspace config — hand-editable.",
            "# Legacy config.json is ignored (no migration).",
            "",
            "slug = \(stringLiteral(config.slug))",
        ]
        if let prefix = config.prefix {
            lines.append("prefix = \(stringLiteral(prefix))")
        }
        if let mainCLICommand = config.mainCLICommand {
            lines.append("mainCLICommand = \(stringLiteral(mainCLICommand))")
        }
        if let editorCommand = config.editorCommand {
            lines.append("editorCommand = \(stringLiteral(editorCommand))")
        }
        if let shellCommand = config.shellCommand {
            lines.append("shellCommand = \(stringLiteral(shellCommand))")
        }
        if let editorPresentation = config.editorPresentation {
            lines.append("editorPresentation = \(stringLiteral(editorPresentation.tomlValue))")
        }
        if let editorBundleID = config.editorBundleID {
            lines.append("editorBundleID = \(stringLiteral(editorBundleID))")
        }
        if let fileManagerPresentation = config.fileManagerPresentation {
            lines.append("fileManagerPresentation = \(stringLiteral(fileManagerPresentation.tomlValue))")
        }
        if let fileManagerCommand = config.fileManagerCommand {
            lines.append("fileManagerCommand = \(stringLiteral(fileManagerCommand))")
        }
        if let fileManagerBundleID = config.fileManagerBundleID {
            lines.append("fileManagerBundleID = \(stringLiteral(fileManagerBundleID))")
        }
        if let leaderKey = config.leaderKey {
            lines.append("leaderKey = \(stringLiteral(leaderKey))")
        }
        if let baseRef = config.baseRef {
            lines.append("baseRef = \(stringLiteral(baseRef))")
        }
        if let archived = config.archivedThreeWordNames, !archived.isEmpty {
            lines.append("archivedThreeWordNames = \(stringArrayLiteral(archived))")
        }
        if let mainRemoteURL = config.mainRemoteURL {
            lines.append("mainRemoteURL = \(stringLiteral(mainRemoteURL))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Decode Workspace Setting from TOML.
    static func decodeWorkspaceConfig(from text: String) throws -> WorkspaceConfig {
        let table = try parse(text)
        let root = table.root
        guard let slug = root.strings["slug"], !slug.isEmpty else {
            throw PreferencesTomlError.missingRequired("slug")
        }
        return WorkspaceConfig(
            slug: slug,
            prefix: root.strings["prefix"],
            mainCLICommand: root.strings["mainCLICommand"],
            editorCommand: root.strings["editorCommand"],
            shellCommand: root.strings["shellCommand"],
            editorPresentation: EditorPresentation.fromToml(root.strings["editorPresentation"]),
            editorBundleID: root.strings["editorBundleID"],
            fileManagerPresentation: EditorPresentation.fromToml(root.strings["fileManagerPresentation"]),
            fileManagerCommand: root.strings["fileManagerCommand"],
            fileManagerBundleID: root.strings["fileManagerBundleID"],
            leaderKey: root.strings["leaderKey"],
            baseRef: root.strings["baseRef"],
            archivedThreeWordNames: root.arrays["archivedThreeWordNames"],
            mainRemoteURL: root.strings["mainRemoteURL"]
        )
    }

    /// Encode Secret Store to hand-editable TOML (T.3). Mode 0600 is the caller's job.
    static func encode(_ document: SecretStoreDocument) -> String {
        var lines: [String] = [
            "# Symphonia Secret Store — hand-editable. Keep mode 0600.",
            "# Legacy secrets.json is ignored (no migration).",
            "",
            "version = \(document.version)",
        ]

        for group in document.groups {
            lines.append("")
            lines.append("[groups.\(quotedKey(group.id))]")
            lines.append("name = \(stringLiteral(group.name))")
            lines.append("enabled = \(boolLiteral(group.enabled))")
        }

        for envVar in document.vars {
            lines.append("")
            lines.append("[vars.\(quotedKey(envVar.id))]")
            lines.append("key = \(stringLiteral(envVar.key))")
            lines.append("value = \(stringLiteral(envVar.value))")
            lines.append("enabled = \(boolLiteral(envVar.enabled))")
            if let groupId = envVar.groupId {
                lines.append("groupId = \(stringLiteral(groupId))")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Decode Secret Store from TOML.
    static func decodeSecretStore(from text: String) throws -> SecretStoreDocument {
        let table = try parse(text)
        let version = table.root.ints["version"] ?? SecretStoreDocument.currentVersion

        var groups: [SecretGroup] = []
        if let groupTables = table.tables["groups"] {
            for id in orderedTableKeys(groupTables) {
                guard let fields = groupTables[id] else { continue }
                let name = fields.strings["name"] ?? ""
                let enabled = fields.bools["enabled"] ?? true
                groups.append(SecretGroup(id: id, name: name, enabled: enabled))
            }
        }

        var vars: [EnvVar] = []
        if let varTables = table.tables["vars"] {
            for id in orderedTableKeys(varTables) {
                guard let fields = varTables[id] else { continue }
                guard let key = fields.strings["key"] else { continue }
                vars.append(
                    EnvVar(
                        id: id,
                        key: key,
                        value: fields.strings["value"] ?? "",
                        enabled: fields.bools["enabled"] ?? true,
                        groupId: fields.strings["groupId"]
                    )
                )
            }
        }

        return SecretStoreDocument(version: version, groups: groups, vars: vars)
    }

    /// Encode workspace session index to hand-editable TOML (T.3).
    static func encode(_ index: WorkspaceIndexDocument) -> String {
        var lines: [String] = [
            "# Symphonia workspace index — known slugs + last selection.",
            "# Legacy workspace-index.json is ignored (no migration).",
            "",
        ]
        if let last = index.lastSelectedSlug {
            lines.append("lastSelectedSlug = \(stringLiteral(last))")
        } else {
            lines.append("# lastSelectedSlug = \"…\"")
        }

        for (offset, entry) in index.entries.enumerated() {
            lines.append("")
            lines.append("[entries.\(quotedKey(String(offset)))]")
            lines.append("slug = \(stringLiteral(entry.slug))")
            if let prefix = entry.prefix {
                lines.append("prefix = \(stringLiteral(prefix))")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Decode workspace session index from TOML.
    static func decodeWorkspaceIndex(from text: String) throws -> WorkspaceIndexDocument {
        let table = try parse(text)
        let lastSelectedSlug = table.root.strings["lastSelectedSlug"]

        var entries: [WorkspaceIndexDocument.Entry] = []
        if let entryTables = table.tables["entries"] {
            let keys = orderedTableKeys(entryTables).sorted { lhs, rhs in
                switch (Int(lhs), Int(rhs)) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs < rhs
                }
            }
            for key in keys {
                guard let fields = entryTables[key] else { continue }
                guard let slug = fields.strings["slug"], !slug.isEmpty else { continue }
                entries.append(.init(slug: slug, prefix: fields.strings["prefix"]))
            }
        }

        return WorkspaceIndexDocument(lastSelectedSlug: lastSelectedSlug, entries: entries)
    }

    // MARK: - Encode helpers

    private static func stringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func stringArrayLiteral(_ values: [String]) -> String {
        "[" + values.map(stringLiteral).joined(separator: ", ") + "]"
    }

    private static func boolLiteral(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    /// Bare keys when safe; otherwise `"dotted.id"`.
    private static func quotedKey(_ key: String) -> String {
        let bare = key.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
        }
        if bare { return key }
        return stringLiteral(key)
    }

    /// Prefer insertion order recorded during parse; fall back to sorted keys.
    private static func orderedTableKeys(_ tables: [String: FieldMap]) -> [String] {
        // Dictionary iteration order is insertion-ordered in practice for our parse path.
        Array(tables.keys)
    }

    // MARK: - Parse

    /// Strip `#` comments only when `#` is outside quoted strings (respects `\"` escapes).
    /// Full-line `#` comments become empty after trim.
    private static func stripInlineComment(_ line: String) -> String {
        var result = ""
        result.reserveCapacity(line.count)
        var inString = false
        var escaped = false
        for ch in line {
            if inString {
                result.append(ch)
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                continue
            }
            if ch == "#" { break }
            if ch == "\"" { inString = true }
            result.append(ch)
        }
        return result
    }

    private struct FieldMap {
        var strings: [String: String] = [:]
        var arrays: [String: [String]] = [:]
        var bools: [String: Bool] = [:]
        var ints: [String: Int] = [:]
    }

    private struct ParsedTable {
        var root = FieldMap()
        /// `[group."id"]` → field map
        var tables: [String: [String: FieldMap]] = [:]
    }

    private static func parse(_ text: String) throws -> ParsedTable {
        var result = ParsedTable()
        var currentGroup: String?
        var currentKey: String?

        for (lineIndex, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = lineIndex + 1
            var line = stripInlineComment(String(rawLine))
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                let header = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                let parts = try splitTableHeader(header, line: lineNumber)
                guard parts.count == 2 else {
                    throw PreferencesTomlError.unsupportedTable(header, line: lineNumber)
                }
                currentGroup = parts[0]
                currentKey = parts[1]
                if result.tables[parts[0]] == nil {
                    result.tables[parts[0]] = [:]
                }
                if result.tables[parts[0]]?[parts[1]] == nil {
                    result.tables[parts[0]]?[parts[1]] = FieldMap()
                }
                continue
            }

            guard let eq = line.firstIndex(of: "=") else {
                throw PreferencesTomlError.invalidLine(line, line: lineNumber)
            }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let valueRaw = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            if valueRaw.hasPrefix("[") {
                let array = try parseStringArray(valueRaw, line: lineNumber)
                if let group = currentGroup, let nested = currentKey {
                    result.tables[group]?[nested]?.arrays[key] = array
                } else {
                    result.root.arrays[key] = array
                }
            } else if valueRaw == "true" || valueRaw == "false" {
                let value = valueRaw == "true"
                if let group = currentGroup, let nested = currentKey {
                    result.tables[group]?[nested]?.bools[key] = value
                } else {
                    result.root.bools[key] = value
                }
            } else if let intValue = Int(valueRaw), !valueRaw.hasPrefix("\""), !valueRaw.contains(".") {
                if let group = currentGroup, let nested = currentKey {
                    result.tables[group]?[nested]?.ints[key] = intValue
                } else {
                    result.root.ints[key] = intValue
                }
            } else {
                let value = try parseStringValue(valueRaw, line: lineNumber)
                if let group = currentGroup, let nested = currentKey {
                    result.tables[group]?[nested]?.strings[key] = value
                } else {
                    result.root.strings[key] = value
                }
            }
        }

        return result
    }

    /// `commandBindings."overlay.openEditor"` → ["commandBindings", "overlay.openEditor"]
    private static func splitTableHeader(_ header: String, line: Int) throws -> [String] {
        var parts: [String] = []
        var i = header.startIndex
        while i < header.endIndex {
            if header[i] == "." {
                i = header.index(after: i)
                continue
            }
            if header[i] == "\"" {
                let start = header.index(after: i)
                guard let end = header[start...].firstIndex(of: "\"") else {
                    throw PreferencesTomlError.invalidLine(header, line: line)
                }
                parts.append(String(header[start..<end]))
                i = header.index(after: end)
                continue
            }
            let start = i
            while i < header.endIndex, header[i] != "." {
                i = header.index(after: i)
            }
            parts.append(String(header[start..<i]))
        }
        return parts.filter { !$0.isEmpty }
    }

    private static func parseStringValue(_ raw: String, line: Int) throws -> String {
        guard raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 else {
            throw PreferencesTomlError.expectedString(raw, line: line)
        }
        let inner = String(raw.dropFirst().dropLast())
        var out = ""
        var i = inner.startIndex
        while i < inner.endIndex {
            let ch = inner[i]
            if ch == "\\" {
                let next = inner.index(after: i)
                guard next < inner.endIndex else {
                    throw PreferencesTomlError.invalidLine(raw, line: line)
                }
                switch inner[next] {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "\\": out.append("\\")
                case "\"": out.append("\"")
                default:
                    throw PreferencesTomlError.invalidLine(raw, line: line)
                }
                i = inner.index(after: next)
            } else {
                out.append(ch)
                i = inner.index(after: i)
            }
        }
        return out
    }

    private static func parseStringArray(_ raw: String, line: Int) throws -> [String] {
        guard raw.hasPrefix("["), raw.hasSuffix("]") else {
            throw PreferencesTomlError.invalidLine(raw, line: line)
        }
        let inner = String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if inner.isEmpty { return [] }

        var values: [String] = []
        var i = inner.startIndex
        while i < inner.endIndex {
            while i < inner.endIndex, inner[i].isWhitespace || inner[i] == "," {
                i = inner.index(after: i)
            }
            guard i < inner.endIndex else { break }
            guard inner[i] == "\"" else {
                throw PreferencesTomlError.expectedString(raw, line: line)
            }
            let start = i
            i = inner.index(after: i)
            var escaped = false
            while i < inner.endIndex {
                let ch = inner[i]
                if escaped {
                    escaped = false
                    i = inner.index(after: i)
                    continue
                }
                if ch == "\\" {
                    escaped = true
                    i = inner.index(after: i)
                    continue
                }
                if ch == "\"" {
                    let end = inner.index(after: i)
                    values.append(try parseStringValue(String(inner[start..<end]), line: line))
                    i = end
                    break
                }
                i = inner.index(after: i)
            }
        }
        return values
    }
}

/// On-disk workspace session index (`~/.symphonia/workspace-index.toml`, T.3).
struct WorkspaceIndexDocument: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var slug: String
        var prefix: String?
    }

    var lastSelectedSlug: String?
    var entries: [Entry]

    static let empty = WorkspaceIndexDocument(lastSelectedSlug: nil, entries: [])
}

enum PreferencesTomlError: LocalizedError {
    case invalidLine(String, line: Int)
    case expectedString(String, line: Int)
    case unsupportedTable(String, line: Int)
    case missingRequired(String)

    var errorDescription: String? {
        switch self {
        case .invalidLine(let text, let line):
            return "toml:\(line): invalid line: \(text)"
        case .expectedString(let text, let line):
            return "toml:\(line): expected quoted string, got: \(text)"
        case .unsupportedTable(let header, let line):
            return "toml:\(line): unsupported table [\(header)] (expected [group.\"id\"] two-part headers)"
        case .missingRequired(let key):
            return "toml: missing required key \(key)"
        }
    }
}
