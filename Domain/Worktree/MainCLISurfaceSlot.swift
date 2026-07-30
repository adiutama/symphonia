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
    /// True after crash-loop guard stops auto-reload; Operator must Reload CLI.
    var processExited: Bool

    /// Stable view identity until respawn.
    var viewIdentity: String { "\(id)#\(generation)" }

    init(
        id: String,
        workingDirectory: String,
        command: String?,
        spawnEnvironment: [(key: String, value: String)],
        generation: Int,
        processExited: Bool = false
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.command = command
        self.spawnEnvironment = spawnEnvironment
        self.generation = generation
        self.processExited = processExited
    }
}
