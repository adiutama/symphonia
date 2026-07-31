import AppKit
import Foundation

enum ExternalAppError: LocalizedError {
    case appNotFound(String)
    case openFailed(String)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let bundleID):
            return "No application found for bundle id “\(bundleID)”."
        case .openFailed(let detail):
            return detail
        }
    }
}

/// Result of launching / focusing an External app.
struct ExternalOpenResult: Sendable {
    /// Process id when known (best signal for “still alive”).
    var processIdentifier: pid_t?
}

/// NSWorkspace seam for External Presentation (ADR 0023).
protocol ExternalAppLaunching: Sendable {
    func displayName(forBundleID bundleID: String) -> String
    /// Process running (Finder is almost always true on macOS).
    func isRunning(bundleID: String) -> Bool
    /// Whether a specific process id is still alive.
    func isProcessRunning(pid: pid_t) -> Bool
    /// Whether the External Activity still counts as live for Glance inventory.
    /// Finder → window for Worktree; others → pid if known, else bundle running.
    func isAlive(bundleID: String, processIdentifier: pid_t?, workingDirectory: URL) -> Bool
    @discardableResult
    func open(bundleID: String, workingDirectory: URL) async throws -> ExternalOpenResult
    func activate(bundleID: String) -> Bool
    /// End the External Activity: quit app, or close Finder windows for the Worktree.
    func end(bundleID: String, workingDirectory: URL)
}

struct NSWorkspaceExternalAppLauncher: ExternalAppLaunching {
    func displayName(forBundleID bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    func isRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    func isProcessRunning(pid: pid_t) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.processIdentifier == pid }
    }

    func isAlive(bundleID: String, processIdentifier: pid_t?, workingDirectory: URL) -> Bool {
        if bundleID == ActivityDefaults.fileManagerBundleID {
            return FinderWindowBridge.hasWindow(showing: workingDirectory)
        }
        if let pid = processIdentifier {
            return isProcessRunning(pid: pid)
        }
        return isRunning(bundleID: bundleID)
    }

    @discardableResult
    func open(bundleID: String, workingDirectory: URL) async throws -> ExternalOpenResult {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ExternalAppError.appNotFound(bundleID)
        }

        // Finder: reveal the Worktree folder (never treat the folder as a document).
        if bundleID == ActivityDefaults.fileManagerBundleID {
            guard NSWorkspace.shared.open(workingDirectory) else {
                throw ExternalAppError.openFailed("Could not open “\(workingDirectory.path)” in Finder.")
            }
            let pid = NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == bundleID }?
                .processIdentifier
            return ExternalOpenResult(processIdentifier: pid)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = false

        if FolderCapableEditors.supportsFolderOpen(bundleID: bundleID) {
            let app = try await openReturningApp(
                urls: [workingDirectory],
                applicationAt: appURL,
                configuration: configuration
            )
            return ExternalOpenResult(processIdentifier: app?.processIdentifier)
        }

        // Document apps (e.g. TextEdit) often reject a folder URL — launch the app alone.
        do {
            let app = try await openReturningApp(
                urls: [workingDirectory],
                applicationAt: appURL,
                configuration: configuration
            )
            return ExternalOpenResult(processIdentifier: app?.processIdentifier)
        } catch {
            let app = try await openApplicationReturningApp(at: appURL, configuration: configuration)
            return ExternalOpenResult(processIdentifier: app?.processIdentifier)
        }
    }

    func activate(bundleID: String) -> Bool {
        let matches = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
        guard let app = matches.first else { return false }
        return app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    func end(bundleID: String, workingDirectory: URL) {
        if bundleID == ActivityDefaults.fileManagerBundleID {
            FinderWindowBridge.closeWindows(showing: workingDirectory)
            return
        }
        // `terminate()` asks the app to quit (Apple Event); not `forceTerminate()`.
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == bundleID {
            app.terminate()
        }
    }

    private func openReturningApp(
        urls: [URL],
        applicationAt appURL: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) async throws -> NSRunningApplication? {
        try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration) { app, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: app)
                }
            }
        }
    }

    private func openApplicationReturningApp(
        at appURL: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) async throws -> NSRunningApplication? {
        try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: app)
                }
            }
        }
    }
}

/// Resolve a `.app` path or bundle id string to a bundle identifier.
enum BundleIDResolver {
    static func resolve(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.hasSuffix(".app") {
            let url = URL(fileURLWithPath: SymphoniaPaths.expandingTildeInPath(trimmed).path)
            if let id = Bundle(url: url)?.bundleIdentifier, !id.isEmpty {
                return id
            }
        }
        return trimmed
    }
}

/// Editors / IDEs that treat a directory URL as a project/workspace root.
enum FolderCapableEditors {
    static let bundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", // Cursor (stable channel id may vary)
        "dev.zed.Zed",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.apple.dt.Xcode",
        "com.panic.Nova",
        "com.jetbrains.intellij",
        "com.jetbrains.WebStorm",
        "com.jetbrains.PhpStorm",
        "com.jetbrains.CLion",
        "com.google.android.studio",
        "com.github.atom", // legacy
    ]

    static func supportsFolderOpen(bundleID: String) -> Bool {
        if bundleIDs.contains(bundleID) { return true }
        let lower = bundleID.lowercased()
        if lower.contains("cursor") { return true }
        if lower.contains("vscode") { return true }
        if lower.contains("zed") { return true }
        if lower.hasPrefix("com.jetbrains.") { return true }
        return false
    }
}

/// Finder window probe / close for External Files Activities.
/// Finder never quits when windows close — process liveness is the wrong signal.
enum FinderWindowBridge {
    static func hasWindow(showing directory: URL) -> Bool {
        let path = normalizedPOSIXPath(directory)
        // Return strings — AppleScript `true`/`false` descriptors are unreliable via NSAppleScript.
        let script = """
        tell application "Finder"
          set targetPath to "\(escaped(path))"
          repeat with w in (every Finder window)
            try
              set p to POSIX path of (target of w as alias)
              if p is targetPath or p is (targetPath & "/") then return "yes"
            end try
          end repeat
        end tell
        return "no"
        """
        guard let raw = runAppleScript(script) as? String else {
            // Automation denied / script error — keep the Glance row (don't false-prune).
            return true
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "yes"
    }

    static func closeWindows(showing directory: URL) {
        let path = normalizedPOSIXPath(directory)
        let script = """
        tell application "Finder"
          set targetPath to "\(escaped(path))"
          set toClose to {}
          repeat with w in (every Finder window)
            try
              set p to POSIX path of (target of w as alias)
              if p is targetPath or p is (targetPath & "/") then
                set end of toClose to w
              end if
            end try
          end repeat
          repeat with w in toClose
            try
              close w
            end try
          end repeat
        end tell
        """
        _ = runAppleScript(script)
    }

    private static func normalizedPOSIXPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private static func escaped(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAppleScript(_ source: String) -> Any? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        if result.descriptorType == typeBoolean {
            return result.booleanValue
        }
        if result.descriptorType == typeTrue { return true }
        if result.descriptorType == typeFalse { return false }
        return result.stringValue
    }
}
