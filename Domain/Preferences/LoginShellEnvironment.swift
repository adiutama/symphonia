import Foundation

/// Probes environment from the Operator's **login shell**, not Symphonia's GUI process env.
///
/// Symphonia is launched as a GUI app, so `ProcessInfo.processInfo.environment` rarely
/// has `VISUAL`/`EDITOR` or a Homebrew-complete `PATH`. Ghostty then runs commands under
/// `bash --noprofile --norc`, which also lacks that PATH — bare `nvim` fails even when
/// Terminal.app finds it. We probe `$SHELL -lc` (fish/zsh/bash) the way Terminal does.
enum LoginShellEnvironment {
    private static let probeTimeout: TimeInterval = 1.5

    /// Cached for the process lifetime (login exports don't change mid-session).
    private static let probed: Probed = probe()

    static var visual: String? { probed.visual }
    static var editor: String? { probed.editor }
    /// Colon-separated PATH from the login shell (for Ghostty spawn env).
    static var path: String? { probed.path }

    /// Resolve a bare executable via login-shell `command -v` (absolute path or nil).
    static func resolveOnPath(_ executable: String) -> String? {
        let trimmed = executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains("\n") else {
            return nil
        }
        // Quote-safe: executable names don't include quotes in normal use.
        let escaped = trimmed.replacingOccurrences(of: "'", with: "'\\''")
        guard let output = runLoginShell(script: "command -v '\(escaped)'"),
              !output.isEmpty,
              output.hasPrefix("/")
        else {
            return nil
        }
        return output
    }

    private struct Probed {
        var visual: String?
        var editor: String?
        var path: String?
    }

    private static func probe() -> Probed {
        let shellPath = resolvedShellPath()
        let isFish = URL(fileURLWithPath: shellPath).lastPathComponent.lowercased() == "fish"
        let separator = "\u{1}"

        let pathExpr = isFish ? "(string join : -- $PATH)" : "\"$PATH\""
        let script = """
        printf '%s\(separator)%s\(separator)%s' \"$VISUAL\" \"$EDITOR\" \(pathExpr)
        """

        guard let output = runLoginShell(script: script, shellPath: shellPath) else {
            return Probed(visual: nil, editor: nil, path: nil)
        }

        let parts = output.components(separatedBy: separator)
        let visual = parts[safe: 0]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let editor = parts[safe: 1]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = parts[safe: 2]?.trimmingCharacters(in: .whitespacesAndNewlines)

        return Probed(
            visual: visual.flatMap { $0.isEmpty ? nil : $0 },
            editor: editor.flatMap { $0.isEmpty ? nil : $0 },
            path: path.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func resolvedShellPath() -> String {
        let configuredShell = ProcessInfo.processInfo.environment["SHELL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let configuredShell, !configuredShell.isEmpty {
            return configuredShell
        }
        return "/bin/zsh"
    }

    private static func runLoginShell(script: String, shellPath: String? = nil) -> String? {
        let shell = shellPath ?? resolvedShellPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", script]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        guard waitWithTimeout(process, timeout: probeTimeout) else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty
        else {
            return nil
        }
        return output
    }

    private static func waitWithTimeout(_ process: Process, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        return semaphore.wait(timeout: .now() + timeout) == .success
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
