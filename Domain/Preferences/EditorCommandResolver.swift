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
    /// Symphonia's own process environment (`ProcessInfo.processInfo.environment`) is a
    /// GUI-launch environment and rarely has `VISUAL`/`EDITOR` set even when an
    /// Operator's Terminal does — see `LoginShellEnvironment`.
    static func resolveCommand(configured: String) -> String {
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let visual = LoginShellEnvironment.visual {
            return visual
        }
        if let editor = LoginShellEnvironment.editor {
            return editor
        }
        return "vi"
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
