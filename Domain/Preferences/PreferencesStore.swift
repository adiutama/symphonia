import Foundation

/// Loads and saves Global Setting at `~/.symphonia/preferences.toml` (T.1).
///
/// Missing file → ``GlobalPreferences/default``. Corrupt TOML throws so the Operator
/// can fix or delete. Legacy `preferences.json` is **not** migrated — ignore or remove it.
struct PreferencesStore: Sendable {
    var fileURL: URL

    init(fileURL: URL = SymphoniaPaths.preferencesFile) {
        self.fileURL = fileURL
    }

    /// Load Global Setting. Missing file → ``GlobalPreferences/default``.
    func load() throws -> GlobalPreferences {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return .default
        }

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return try PreferencesToml.decodeGlobalPreferences(from: text)
    }

    /// Persist Global Setting as TOML. Creates `~/.symphonia` (and parents) as needed.
    func save(_ preferences: GlobalPreferences) throws {
        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let text = PreferencesToml.encode(preferences)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
