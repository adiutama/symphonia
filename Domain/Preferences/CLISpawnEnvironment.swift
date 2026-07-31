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
        return map.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) }
    }
}

/// Formats Operator command strings for Ghostty surface `command` (macOS).
///
/// Ghostty wraps as `login … bash --noprofile --norc -c exec -l <command>`. The first
/// token after `exec -l` must be a real executable — not a bare tool alone in a way that
/// breaks `-c`, and not shell builtins like `set`. Wrapping in `/bin/zsh -c '…'` matches
/// Create Project bootstrap.
enum GhosttySpawnCommand {
    /// Wrap a freeform command for Ghostty. Empty → nil (bare shell).
    static func wrap(_ command: String?) -> String? {
        guard let command else { return nil }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isAlreadyWrapped(trimmed) {
            return trimmed
        }
        return "/bin/zsh -c \(shellSingleQuoted(trimmed))"
    }

    /// Non-optional wrap for known non-empty scripts.
    static func wrapScript(_ script: String) -> String {
        wrap(script) ?? "/bin/zsh -c \(shellSingleQuoted(script))"
    }

    static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func isAlreadyWrapped(_ command: String) -> Bool {
        command.hasPrefix("/bin/zsh -c ")
            || command.hasPrefix("/bin/bash -c ")
            || command.hasPrefix("/bin/sh -c ")
    }
}
