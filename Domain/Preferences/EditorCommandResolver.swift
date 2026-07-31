import Foundation

/// How Symphonia should open the configured Editor (ADR 0006 / 0023).
///
/// Overlay PTY suits TUI editors (`vim`, `nano`, …). GUI editors launch as External
/// Activities (Focus / End — no peek/hide).
enum EditorPresentation: String, Equatable, Sendable, Codable {
    /// Run inside an Overlay PTY (hide ≠ quit).
    case terminalOverlay
    /// Launch outside Symphonia as an External Activity.
    case externalApp

    /// TOML / Settings vocabulary: `overlay` | `external`.
    static func fromToml(_ raw: String?) -> EditorPresentation? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "overlay", "terminaloverlay", "terminal_overlay", "tui":
            return .terminalOverlay
        case "external", "externalapp", "external_app", "gui":
            return .externalApp
        default:
            return nil
        }
    }

    var tomlValue: String {
        switch self {
        case .terminalOverlay: return "overlay"
        case .externalApp: return "external"
        }
    }
}

/// Resolves the Editor command string and a best-effort presentation hint.
enum EditorCommandResolver {
    private static let resolveLock = NSLock()
    private static var resolveCache: [String: String] = [:]

    /// Resolve configured value: empty → login shell `VISUAL`, else `EDITOR`, else `vi`.
    ///
    /// Bare executables (e.g. `nvim`) are expanded to an absolute path via the login
    /// shell so Ghostty's `bash --noprofile --norc` spawn can still find Homebrew tools.
    /// Results are cached by configured string — Effective Setting is read often.
    static func resolveCommand(configured: String) -> String {
        let cacheKey = configured
        resolveLock.lock()
        if let hit = resolveCache[cacheKey] {
            resolveLock.unlock()
            return hit
        }
        resolveLock.unlock()

        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw: String
        if !trimmed.isEmpty {
            raw = trimmed
        } else if let visual = LoginShellEnvironment.visual {
            raw = visual
        } else if let editor = LoginShellEnvironment.editor {
            raw = editor
        } else {
            raw = "vi"
        }
        let resolved = absolutizeExecutable(in: raw)

        resolveLock.lock()
        resolveCache[cacheKey] = resolved
        resolveLock.unlock()
        return resolved
    }

    /// Replace the first path token with `command -v` when it is a bare name.
    private static func absolutizeExecutable(in command: String) -> String {
        let parts = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let exe = parts.first, !exe.isEmpty else { return command }
        if exe.hasPrefix("/") || exe.hasPrefix("~") {
            return command
        }
        guard let resolved = LoginShellEnvironment.resolveOnPath(exe) else {
            return command
        }
        var out = parts
        out[0] = resolved
        return out.joined(separator: " ")
    }

    /// Heuristic: known GUI / external launchers vs TUI Overlay editors.
    static func presentation(forCommand command: String) -> EditorPresentation {
        let executable = command
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init)?
            .lowercased() ?? ""

        let basename = URL(fileURLWithPath: executable).lastPathComponent.lowercased()

        let guiBasenames: Set<String> = [
            "code", "code-insiders", "cursor", "zed", "subl", "sublime_text",
            "atom", "bbedit", "mate", "idea", "webstorm", "phpstorm", "open",
        ]

        if guiBasenames.contains(basename) {
            return .externalApp
        }
        return .terminalOverlay
    }
}
