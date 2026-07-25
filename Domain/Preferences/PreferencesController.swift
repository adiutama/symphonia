import Foundation
import Combine

/// Observable holder for Global Setting load/save and Effective Setting resolution.
@MainActor
final class PreferencesController: ObservableObject {
    private let store: PreferencesStore
    private var pendingSave: DispatchWorkItem?

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
        var loaded: GlobalPreferences
        do {
            loaded = try store.load()
            self.lastError = nil
        } catch {
            loaded = .default
            self.lastError = error.localizedDescription
        }
        let didMigrate = Self.migrateBareCommandShortcuts(in: &loaded)
        self.preferences = loaded
        self.effective = EffectiveSettings.resolve(global: loaded, workspace: .none)
        if didMigrate {
            do {
                try store.save(loaded)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Rewrite legacy bare-letter Command shortcuts (`w`, `,`) to `ctrl+…` chords (L2).
    @discardableResult
    private static func migrateBareCommandShortcuts(in preferences: inout GlobalPreferences) -> Bool {
        var changed = false
        for (id, override) in preferences.commandBindings {
            guard let raw = override.shortcut, !raw.isEmpty else { continue }
            let normalized = CommandBindingResolver.normalizeShortcut(raw)
            guard normalized != raw else { continue }
            var next = override
            next.shortcut = normalized
            preferences.commandBindings[id] = next
            changed = true
        }
        return changed
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

    /// Debounced persist of Global Setting only (`preferences.toml`). Does not touch Workspace config.
    /// Empty Leader is restored to the default (`ctrl+p`) — Global must always have a binding.
    func scheduleSave(after seconds: TimeInterval = 0.35) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.preferences.leaderKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.preferences.leaderKey = GlobalPreferences.default.leaderKey
            }
            self.save()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func resetToDefaults() {
        preferences = .default
        save()
    }
}
