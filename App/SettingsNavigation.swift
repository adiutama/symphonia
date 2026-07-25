import Foundation
import AppKit

/// Deep-link target for the Settings window (T.5).
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
        /// Opens Global → Commands.
        case globalCommands
        case workspaceSettings(workspaceId: String)
        case workspaceSecrets(workspaceId: String)
    }

    @Published var pending: Destination?

    /// Installed from a view that has `@Environment(\.openWindow)`.
    private var presentWindow: (() -> Void)?

    func installPresenter(_ present: @escaping () -> Void) {
        presentWindow = present
    }

    func open(_ destination: Destination) {
        pending = destination
        presentWindow?()
    }

    /// Opens Settings on Global → General.
    func openSettings() {
        open(.globalGeneral)
    }

    func consume() -> Destination? {
        let value = pending
        pending = nil
        return value
    }
}
