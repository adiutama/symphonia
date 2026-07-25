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
                    aliases: fields["aliases"],
                    shortcut: fields["shortcut"]
                )
            }
        }

        return GlobalPreferences(
            mainCLICommand: root["mainCLICommand"] ?? "",
            editorCommand: root["editorCommand"] ?? "",
            leaderKey: root["leaderKey"] ?? GlobalPreferences.default.leaderKey,
            workspacesRoot: root["workspacesRoot"] ?? GlobalPreferences.default.workspacesRoot,
            baseRef: root["baseRef"] ?? GlobalPreferences.default.baseRef,
            commandBindings: bindings
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

    /// Bare keys when safe; otherwise `"dotted.id"`.
    private static func quotedKey(_ key: String) -> String {
        let bare = key.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
        }
        if bare { return key }
        return stringLiteral(key)
    }

    // MARK: - Parse

    private struct ParsedTable {
        var root: [String: String] = [:]
        /// `[commandBindings."id"]` → field map
        var tables: [String: [String: [String: String]]] = [:]
    }

    private static func parse(_ text: String) throws -> ParsedTable {
        var result = ParsedTable()
        /// Current table path: nil = root; `("commandBindings", "overlay.openEditor")` = nested.
        var currentGroup: String?
        var currentKey: String?

        for (lineIndex, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = lineIndex + 1
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#") {
                // Only treat # as comment when outside quotes — good enough for our files.
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
                    result.tables[parts[0]]?[parts[1]] = [:]
                }
                continue
            }

            guard let eq = line.firstIndex(of: "=") else {
                throw PreferencesTomlError.invalidLine(line, line: lineNumber)
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let valueRaw = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let value = try parseStringValue(valueRaw, line: lineNumber)

            if let group = currentGroup, let nested = currentKey {
                result.tables[group]?[nested]?[key] = value
            } else {
                result.root[key] = value
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
            // Bare strings / numbers not used in our schema — require quoted strings.
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
}

enum PreferencesTomlError: LocalizedError {
    case invalidLine(String, line: Int)
    case expectedString(String, line: Int)
    case unsupportedTable(String, line: Int)

    var errorDescription: String? {
        switch self {
        case .invalidLine(let text, let line):
            return "preferences.toml:\(line): invalid line: \(text)"
        case .expectedString(let text, let line):
            return "preferences.toml:\(line): expected quoted string, got: \(text)"
        case .unsupportedTable(let header, let line):
            return "preferences.toml:\(line): unsupported table [\(header)] (only [commandBindings.\"id\"] nested tables)"
        }
    }
}
