import Foundation

/// Probes `VISUAL` / `EDITOR` from the Operator's **login shell**, not Symphonia's own
/// process environment.
///
/// Symphonia is launched as a GUI app (Finder / `open` / Xcode), so
/// `ProcessInfo.processInfo.environment` reflects launchd's environment, not the
/// exports an Operator's `.zshrc` / `.bash_profile` set up. Terminal.app runs a login
/// shell, which is why an Operator sees `nvim` there but Symphonia would otherwise
/// fall back to `vi`. Running `$SHELL -lc` sources the same rc files Terminal does.
enum LoginShellEnvironment {
    private static let probeTimeout: TimeInterval = 1.5

    /// Cached for the process lifetime: login shell exports don't change while
    /// Symphonia is running, and spawning a shell on every read (Effective Setting is
    /// recomputed on most renders) would be wasteful.
    private static let probed: (visual: String?, editor: String?) = probe()

    static var visual: String? { probed.visual }
    static var editor: String? { probed.editor }

    private static func probe() -> (visual: String?, editor: String?) {
        let configuredShell = ProcessInfo.processInfo.environment["SHELL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shellPath = (configuredShell?.isEmpty == false) ? configuredShell! : "/bin/zsh"

        // Separator unlikely to appear in an editor command; keeps this a single spawn.
        let separator = "\u{1}"
        let script = "printf '%s\(separator)%s' \"$VISUAL\" \"$EDITOR\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = ["-lc", script]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return (nil, nil)
        }

        guard waitWithTimeout(process, timeout: probeTimeout) else {
            process.terminate()
            return (nil, nil)
        }
        guard process.terminationStatus == 0 else {
            return (nil, nil)
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return (nil, nil)
        }

        let parts = output.components(separatedBy: separator)
        let visual = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let editor = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil

        return (
            visual?.isEmpty == false ? visual : nil,
            editor?.isEmpty == false ? editor : nil
        )
    }

    /// Soft-fail helper: waits for `process` to exit without blocking forever if the
    /// login shell hangs (e.g. a broken rc file prompting for input).
    private static func waitWithTimeout(_ process: Process, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        return semaphore.wait(timeout: .now() + timeout) == .success
    }
}
