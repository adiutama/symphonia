import Foundation

/// Builds the environment passed into Ghostty CLI spawns (Main CLI + Overlays).
///
/// Defaults English locale so tools like Git are not localized from the Mac’s UI language.
/// Enabled Secret Store values override these keys when present.
enum CLISpawnEnvironment {
    static let defaultLocale = "en_US.UTF-8"

    /// Locale defaults first; `secrets` overwrite on key collision.
    static func mergingSecrets(
        _ secrets: [(key: String, value: String)]
    ) -> [(key: String, value: String)] {
        var map: [String: String] = [
            "LANG": defaultLocale,
            "LC_ALL": defaultLocale,
            "LC_MESSAGES": defaultLocale,
        ]
        for pair in secrets {
            map[pair.key] = pair.value
        }
        return map.keys.sorted().map { key in
            (key: key, value: map[key]!)
        }
    }
}
