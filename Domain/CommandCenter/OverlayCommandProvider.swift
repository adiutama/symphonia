import Foundation

/// Exports Overlay-related Commands into the `CommandRegistry` (ADR 2026-07-24-0021-command-center-registry §2 / ADR 2026-07-25-0022-keyboard-keymap).
struct OverlayCommandProvider: CommandProvider {
    var commands: [Command] {
        [
            Command(
                id: "overlay.openEditor",
                title: "Open Editor",
                subtitle: "Open the Editor Overlay for the focused Worktree or Main",
                group: "Overlay",
                defaultSequence: "ee",
                action: .openEditor,
                isEnabled: { $0.hasFocusedSession }
            ),
            Command(
                id: "overlay.toggle",
                title: "Toggle Overlay",
                subtitle: "Show or hide the last Overlay without quitting its process",
                group: "Overlay",
                defaultSequence: "oo",
                action: .toggleOverlay,
                isEnabled: { $0.hasFocusedSession }
            ),
            Command(
                id: "overlay.createBackground",
                title: "Overlay Terminal",
                subtitle: "Peek a new Background Overlay (empty command = shell)",
                group: "Overlay",
                defaultSequence: "ot",
                action: .createBackground,
                isEnabled: { $0.hasFocusedSession }
            ),
            Command(
                id: "overlay.pickBackground",
                title: "Overlay Switcher",
                subtitle: "Pick from live Editor / Background Overlays",
                group: "Overlay",
                defaultSequence: "os",
                action: .showBackgroundPicker,
                isEnabled: { $0.hasFocusedSession }
            ),
        ]
    }
}
