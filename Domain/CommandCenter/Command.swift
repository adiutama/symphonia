import Foundation

/// Context available when evaluating a Command's availability (ADR 0021).
///
/// Kept intentionally small — enough to gate Overlay-related Commands
/// (Open Editor needs a focused session; Toggle Overlay needs one too). Extend
/// as more app areas register Commands.
struct CommandContext: Equatable {
    /// A Main Repo or Worktree is focused (Overlay / CLI actions need this).
    var hasFocusedSession: Bool
    /// An Overlay is currently peeked over the Main CLI.
    var overlayVisible: Bool

    static let empty = CommandContext(hasFocusedSession: false, overlayVisible: false)
}

extension CommandContext {
    /// Snapshot the live context from the running controllers.
    @MainActor
    init(worktrees: WorktreeController, overlays: OverlayController) {
        self.hasFocusedSession = worktrees.focusedSession != nil
        self.overlayVisible = overlays.isShowingOverlay
    }
}

/// A first-class app action exported by an app area and invoked
/// from Command Center (ADR 0021 / CONTEXT.md "Command").
///
/// `run` wraps the existing `CommandModeAction` enum so today's `CommandModeController`
/// stays the single place that knows how to execute an action — the registry only adds
/// discovery, default aliases, and a default shortcut on top.
struct Command: Identifiable {
    /// Stable id, e.g. `"overlay.openEditor"`. Never shown to the Operator; used for
    /// Settings overrides (CC.3) and conflict checks (CC.4).
    let id: String
    let title: String
    let subtitle: String?
    /// Loose grouping for palette sections / Settings list (e.g. `"Overlay"`).
    let group: String?
    /// Free-text default aliases (Command Alias, CONTEXT.md). Defaults are empty (ADR 0022);
    /// slash is optional when the Operator adds aliases. Comma-separated storage is Settings-only.
    let defaultAliases: [String]
    /// Normal-mode sequence. `nil` → derive from title (fallback). `""` → no sequence (ADR 0022).
    let defaultSequence: String?
    /// Legacy empty-filter modifier chord (superseded by Normal sequences). Kept for TOML/Settings.
    let defaultShortcut: String?
    /// Existing Command Center action this Command runs.
    let action: CommandModeAction
    /// Whether this Command is available given the current `CommandContext`.
    let isEnabled: (CommandContext) -> Bool

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        group: String? = nil,
        defaultAliases: [String] = [],
        defaultSequence: String? = nil,
        defaultShortcut: String? = nil,
        action: CommandModeAction,
        isEnabled: @escaping (CommandContext) -> Bool = { _ in true }
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.group = group
        self.defaultAliases = defaultAliases
        self.defaultSequence = defaultSequence
        self.defaultShortcut = defaultShortcut
        self.action = action
        self.isEnabled = isEnabled
    }
}

/// An app area's export point for Commands (ADR 0021 §2).
///
/// Kept as a plain in-process protocol — no extension host, IPC, or install UI. A future
/// extension is "just another `CommandProvider`" per the ADR; this seam should not need to
/// change shape for that.
protocol CommandProvider {
    /// Commands this provider contributes. Availability is evaluated separately via
    /// `Command.isEnabled(_:)` against the current context. `@MainActor` because some
    /// providers (e.g. `WorkspaceCommandProvider`) compute live subtitles from
    /// MainActor-isolated controllers on every read.
    @MainActor
    var commands: [Command] { get }
}

/// Aggregates every registered `CommandProvider` into one flat Command list (ADR 0021 §2).
///
/// Command Center (CC.2) will read from this instead of owning a private, hardcoded action
/// table. For CC.1 the registry only needs to compile and be constructible — see
/// `SymphoniaApp.init()` for the app-wide instance.
@MainActor
final class CommandRegistry: ObservableObject {
    private(set) var providers: [CommandProvider]

    init(providers: [CommandProvider] = []) {
        self.providers = providers
    }

    func register(_ provider: CommandProvider) {
        providers.append(provider)
    }

    /// Every Command from every provider, in registration order.
    var allCommands: [Command] {
        providers.flatMap(\.commands)
    }

    /// Commands enabled for the given context (e.g. to drive the palette in CC.2).
    func availableCommands(context: CommandContext) -> [Command] {
        allCommands.filter { $0.isEnabled(context) }
    }

    func command(id: String) -> Command? {
        allCommands.first { $0.id == id }
    }
}
