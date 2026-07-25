import Foundation

/// Minimal TOML codec for Symphonia config files (T.1+).
///
/// Scoped to our known shapes (string keys, nested tables for maps) so Global /
/// Workspace / Secret Store TOML stays hand-editable without a C++ SPM dep.
/// Not a full TOML 1.0 implementation — extend as T.2–T.3 need new shapes.
enum PreferencesToml {
    /// Encode Global Setting to hand-editable TOML.
    static func encode(_ preferences: GlobalPreferences) -> String {
        var lines: [String] = [
            "# Symphonia global preferences — hand-editable.",
            "# Missing file → app defaults. Corrupt file → load error (fix or delete).",
            "# Legacy preferences.json is ignored (no migration).",
            "",
            "mainCLICommand = \(stringLiteral(preferences.mainCLICommand))",
            "editorCommand = \(stringLiteral(preferences.editorCommand))",
            "leaderKey = \(stringLiteral(preferences.leaderKey))",
            "workspacesRoot = \(stringLiteral(preferences.workspacesRoot))",
            "baseRef = \(stringLiteral(preferences.baseRef))",
        ]

        let bindingKeys = preferences.commandBindings.keys.sorted()
        if !bindingKeys.isEmpty {
            lines.append("")
            lines.append("# Command aliases / shortcuts keyed by Command id (ADR 0021).")
            for id in bindingKeys {
                guard let override = preferences.commandBindings[id] else { continue }
                lines.append("")
                lines.append("[commandBindings.\(quotedKey(id))]")
                if let aliases = override.aliases {
                    lines.append("aliases = \(stringLiteral(aliases))")
                }
                if let shortcut = override.shortcut {
                    lines.append("shortcut = \(stringLiteral(shortcut))")
                }
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
                bindings[id] = CommandBindingOverride(
                    aliases: fields.strings["aliases"],
                    shortcut: fields.strings["shortcut"]
                )
            }
        }

        return GlobalPreferences(
            mainCLICommand: root.strings["mainCLICommand"] ?? "",
            editorCommand: root.strings["editorCommand"] ?? "",
            leaderKey: root.strings["leaderKey"] ?? GlobalPreferences.default.leaderKey,
            workspacesRoot: root.strings["workspacesRoot"] ?? GlobalPreferences.default.workspacesRoot,
            baseRef: root.strings["baseRef"] ?? GlobalPreferences.default.baseRef,
            commandBindings: bindings
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
            leaderKey: root.strings["leaderKey"],
            baseRef: root.strings["baseRef"],
            archivedThreeWordNames: root.arrays["archivedThreeWordNames"],
            mainRemoteURL: root.strings["mainRemoteURL"]
        )
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

    /// Bare keys when safe; otherwise `"dotted.id"`.
    private static func quotedKey(_ key: String) -> String {
        let bare = key.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
        }
        if bare { return key }
        return stringLiteral(key)
    }

    // MARK: - Parse

    private struct FieldMap {
        var strings: [String: String] = [:]
        var arrays: [String: [String]] = [:]
    }

    private struct ParsedTable {
        var root = FieldMap()
        /// `[commandBindings."id"]` → field map
        var tables: [String: [String: FieldMap]] = [:]
    }

    private static func parse(_ text: String) throws -> ParsedTable {
        var result = ParsedTable()
        var currentGroup: String?
        var currentKey: String?

        for (lineIndex, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = lineIndex + 1
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#") {
                if !line[..<hash].contains("\"") {
                    line = String(line[..<hash])
                }
            }
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
            return "toml:\(line): unsupported table [\(header)] (only [commandBindings.\"id\"] nested tables)"
        case .missingRequired(let key):
            return "toml: missing required key \(key)"
        }
    }
}
