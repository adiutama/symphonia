import Foundation
import Combine

/// Observable holder for Global Setting load/save and Effective Setting resolution.
@MainActor
final class PreferencesController: ObservableObject {
    private let store: PreferencesStore

    /// Current Global Setting (editable in Settings UI).
    @Published var preferences: GlobalPreferences

    /// Last load/save error message for chrome, if any.
    @Published var lastError: String?

    /// Optional Workspace Setting overrides for Effective Setting.
    /// Loaded from the selected Workspace’s `config.json` (Phase 3).
    @Published var workspaceOverrides: WorkspaceSettingOverrides = .none

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
        do {
            self.preferences = try store.load()
            self.lastError = nil
        } catch {
            self.preferences = .default
            self.lastError = error.localizedDescription
        }
    }

    /// Effective Setting for the current Global Setting + optional Workspace overrides.
    var effective: EffectiveSettings {
        EffectiveSettings.resolve(global: preferences, workspace: workspaceOverrides)
    }

    func reload() {
        do {
            preferences = try store.load()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func save() {
        do {
            try store.save(preferences)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func resetToDefaults() {
        preferences = .default
        save()
    }
}
