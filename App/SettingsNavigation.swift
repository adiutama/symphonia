import Foundation
import AppKit

/// Deep-link target for the Settings window (T.5).
///
/// Sidebar / Command Center set a destination, then ask AppKit to show Settings;
/// `PreferencesSettingsView` consumes `pending` on appear / change.
@MainActor
final class SettingsNavigation: ObservableObject {
    enum Destination: Equatable, Sendable {
        case globalMainCLI
        case workspaceSettings(workspaceId: String)
        case workspaceSecrets(workspaceId: String)
    }

    @Published var pending: Destination?

    func open(_ destination: Destination) {
        pending = destination
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func openSettings() {
        pending = nil
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func consume() -> Destination? {
        let value = pending
        pending = nil
        return value
    }
}
