import Foundation
import AppKit

/// Deep-link target for the Settings window (T.5) and Keymap cheatsheet (ADR 2026-07-25-0022-keyboard-keymap).
///
/// Sidebar / Command Center set a destination, then present the custom Settings
/// `Window` (not SwiftUI’s `Settings` scene — that scene forces a system titlebar
/// and blocks Raycast/Xcode-style traffic lights in the sidebar).
@MainActor
final class SettingsNavigation: ObservableObject {
    enum Destination: Equatable, Sendable {
        /// Opens Global → General (legacy leaf name; Batch 1 remapped).
        case globalMainCLI
        /// Opens Global → General.
        case globalGeneral
        /// Opens Global → Tools (Shell / Editor / Files).
        case globalTools
        /// Opens Global → Shortcuts.
        case globalCommands
        case workspaceSettings(workspaceId: String)
        case workspaceSecrets(workspaceId: String)
    }

    @Published var pending: Destination?
    /// Whether the Keymap window is currently open (for ⌘⇧/ toggle).
    @Published private(set) var isKeymapOpen = false

    /// Installed from a view that has `@Environment(\.openWindow)`.
    private var presentSettingsWindow: (() -> Void)?
    private var presentKeymapWindow: (() -> Void)?
    private var presentAboutWindow: (() -> Void)?

    func installPresenter(
        settings: @escaping () -> Void,
        keymap: @escaping () -> Void,
        about: @escaping () -> Void
    ) {
        presentSettingsWindow = settings
        presentKeymapWindow = keymap
        presentAboutWindow = about
    }

    func open(_ destination: Destination) {
        pending = destination
        presentSettingsWindow?()
    }

    /// Opens Settings on Global → General.
    func openSettings() {
        open(.globalGeneral)
    }

    func openAbout() {
        presentAboutWindow?()
    }

    /// Toggle the Keymap cheatsheet window (⌘⇧/).
    func toggleKeymap() {
        if isKeymapOpen {
            closeKeymap()
        } else {
            presentKeymapWindow?()
        }
    }

    func closeKeymap() {
        for window in NSApp.windows where window.title == "Keymap" || isKeymapWindow(window) {
            window.close()
        }
        isKeymapOpen = false
    }

    func keymapDidAppear() {
        isKeymapOpen = true
    }

    func keymapDidDisappear() {
        isKeymapOpen = false
    }

    func consume() -> Destination? {
        let value = pending
        pending = nil
        return value
    }

    private func isKeymapWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.contains(SymphoniaSceneID.keymap) == true
    }
}
