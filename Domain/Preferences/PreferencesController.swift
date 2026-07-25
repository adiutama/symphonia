import Foundation
import Combine

/// Observable holder for Global Setting load/save and Effective Setting resolution.
@MainActor
final class PreferencesController: ObservableObject {
    private let store: PreferencesStore

    /// Current Global Setting (editable in Settings UI).
    @Published var preferences: GlobalPreferences {
        didSet { refreshEffective() }
    }

    /// Last load/save error message for chrome, if any.
    @Published var lastError: String?

    /// Optional Workspace Setting overrides for Effective Setting.
    /// Loaded from the selected Workspace’s `config.toml` (Phase 3).
    @Published var workspaceOverrides: WorkspaceSettingOverrides = .none {
        didSet { refreshEffective() }
    }

    /// Cached Effective Setting. Recomputed only when Global/Workspace inputs change —
    /// never on every keystroke (login-shell editor resolve is expensive).
    private(set) var effective: EffectiveSettings

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
        let loaded: GlobalPreferences
        do {
            loaded = try store.load()
            self.lastError = nil
        } catch {
            loaded = .default
            self.lastError = error.localizedDescription
        }
        self.preferences = loaded
        self.effective = EffectiveSettings.resolve(global: loaded, workspace: .none)
    }

    private func refreshEffective() {
        effective = EffectiveSettings.resolve(global: preferences, workspace: workspaceOverrides)
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
