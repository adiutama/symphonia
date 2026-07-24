import Foundation

/// How Symphonia should open the configured Editor (ADR 0006).
///
/// Overlay PTY suits TUI editors (`vim`, `nano`, …). GUI editors (`code`, `cursor`, …)
/// should launch externally so they do not sit inside a terminal Overlay. Phase 6 will
/// honor this; scaffolding only records the inference.
enum EditorPresentation: String, Equatable, Sendable {
    /// Run inside an Editor Overlay PTY (hide ≠ quit).
    case terminalOverlay
    /// Launch outside the terminal (GUI / `open`-style tools).
    case externalApp
}

/// Resolves the Editor command string and a best-effort presentation hint.
enum EditorCommandResolver {
    /// Resolve configured value: empty → login shell `VISUAL`, else `EDITOR`, else `vi`.
    ///
    /// Bare executables (e.g. `nvim`) are expanded to an absolute path via the login
    /// shell so Ghostty's `bash --noprofile --norc` spawn can still find Homebrew tools.
    /// See `LoginShellEnvironment`.
    static func resolveCommand(configured: String) -> String {
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
        return absolutizeExecutable(in: raw)
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
