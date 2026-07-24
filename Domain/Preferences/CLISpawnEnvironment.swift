import Foundation

/// Builds the environment passed into Ghostty CLI spawns (Main CLI + Overlays).
///
/// Defaults English locale so tools like Git are not localized from the Mac’s UI language.
/// Enabled Secret Store values override these keys when present.
enum CLISpawnEnvironment {
    static let defaultLocale = "en_US.UTF-8"

    /// Locale + login-shell `PATH` first; `secrets` overwrite on key collision.
    ///
    /// Ghostty runs Overlay/Main commands under a non-login bash without the Operator's
    /// Homebrew PATH, so we inject the login-shell PATH (ADR-aligned spawn env ownership).
    static func mergingSecrets(
        _ secrets: [(key: String, value: String)]
    ) -> [(key: String, value: String)] {
        var map: [String: String] = [
            "LANG": defaultLocale,
            "LC_ALL": defaultLocale,
            "LC_MESSAGES": defaultLocale,
        ]
        if let path = LoginShellEnvironment.path, !path.isEmpty {
            map["PATH"] = path
        }
        for pair in secrets {
            map[pair.key] = pair.value
        }
        return map.keys.sorted().map { key in
            (key: key, value: map[key]!)
        }
    }
}
