import Foundation

/// Exports Overlay-related Commands into the `CommandRegistry` (ADR 0021 §2 / Path B).
///
/// Titles are the keymap: keep them tight and collision-free so default sequences stay unique.
struct OverlayCommandProvider: CommandProvider {
    var commands: [Command] {
        [
            Command(
                id: "overlay.openEditor",
                title: "Edit",
                subtitle: "Open the Editor Overlay for the focused Worktree or Main",
                group: "Overlay",
                defaultAliases: ["/editor", "/e", "Open Editor"],
                action: .openEditor,
                isEnabled: { $0.hasFocusedSession }
            ),
            Command(
                id: "overlay.hide",
                title: "Hide",
                subtitle: "Return to Main CLI without quitting the Overlay process",
                group: "Overlay",
                defaultAliases: ["/hide", "/x", "/exit", "Hide Overlay"],
                action: .hideOverlay,
                isEnabled: { $0.hasFocusedSession && $0.overlayVisible }
            ),
            Command(
                id: "overlay.createBackground",
                title: "Background",
                subtitle: "Peek a new Background Overlay (empty command = shell)",
                group: "Overlay",
                defaultAliases: ["/background", "/bg", "Create Background CLI"],
                action: .createBackground,
                isEnabled: { $0.hasFocusedSession }
            ),
            Command(
                id: "overlay.pickBackground",
                title: "Peek Overlay…",
                subtitle: "Pick from live Editor / Background Overlays",
                group: "Overlay",
                defaultAliases: ["/pick", "/p"],
                action: .showBackgroundPicker,
                isEnabled: { $0.hasFocusedSession }
            ),
        ]
    }
}
