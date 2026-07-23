import Foundation

/// Loads and saves Global Setting at `~/.symphonia/preferences.json` (ADR 0012).
struct PreferencesStore: Sendable {
    var fileURL: URL

    init(fileURL: URL = SymphoniaPaths.preferencesFile) {
        self.fileURL = fileURL
    }

    /// Load Global Setting. Missing file → ``GlobalPreferences/default``.
    /// Corrupt JSON throws so the Operator can fix or reset.
    func load() throws -> GlobalPreferences {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return .default
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(GlobalPreferences.self, from: data)
    }

    /// Persist Global Setting. Creates `~/.symphonia` (and parents) as needed.
    func save(_ preferences: GlobalPreferences) throws {
        let fm = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try data.write(to: fileURL, options: .atomic)
    }
}
