import Foundation

/// Exports Overlay-related Commands (Open Editor / Hide / Background) into the
/// `CommandRegistry` (ADR 0021 §2).
///
/// Matches today's hardcoded Command Mode root items and `/` slash verbs
/// (`CommandModeController.rootItems()` / `slashCommands`) — this provider is additive
/// for CC.1 and is not yet read by the palette; that swap is CC.2.
struct OverlayCommandProvider: CommandProvider {
    var commands: [Command] {
        [
            Command(
                id: "overlay.openEditor",
                title: "Open Editor",
                subtitle: "Open the Editor Overlay for the focused session",
                group: "Overlay",
                defaultAliases: ["/editor", "/e"],
                defaultShortcut: "e",
                action: .openEditor,
                isEnabled: { $0.hasFocusedSession }
            ),
            Command(
                id: "overlay.hide",
                title: "Hide Overlay",
                subtitle: "Return to Main CLI without quitting the Overlay process",
                group: "Overlay",
                defaultAliases: ["/hide", "/x", "/exit"],
                defaultShortcut: "h",
                action: .hideOverlay,
                isEnabled: { $0.hasFocusedSession && $0.overlayVisible }
            ),
            Command(
                id: "overlay.createBackground",
                title: "Create Background CLI",
                subtitle: "Peek a new Background Overlay (empty command = shell)",
                group: "Overlay",
                defaultAliases: ["/background", "/bg"],
                defaultShortcut: "b",
                action: .createBackground,
                isEnabled: { $0.hasFocusedSession }
            ),
            Command(
                id: "overlay.pickBackground",
                title: "Peek Overlay…",
                subtitle: "Pick from live Editor / Background Overlays",
                group: "Overlay",
                defaultAliases: ["/pick", "/p"],
                defaultShortcut: "p",
                action: .showBackgroundPicker,
                isEnabled: { $0.hasFocusedSession }
            ),
        ]
    }
}
