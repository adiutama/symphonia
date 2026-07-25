import Foundation

/// One opened Main CLI Ghostty surface (persists across focus switches).
struct MainCLISurfaceSlot: Identifiable, Sendable {
    /// Matches ``FocusedSession/id``.
    let id: String
    let workingDirectory: String
    /// Nil = bare shell / Ghostty default.
    let command: String?
    /// Locale defaults + Secret Store snapshot at open / respawn.
    var spawnEnvironment: [(key: String, value: String)]
    /// Bumped to force SwiftUI to recreate the surface (explicit respawn only).
    var generation: Int

    /// Stable view identity until respawn.
    var viewIdentity: String { "\(id)#\(generation)" }
}
