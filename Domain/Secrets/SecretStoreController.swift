import Foundation
import Combine

/// Observable Secret Store for a Workspace Data Dir (P5).
///
/// App-wide instance (wired in `SymphoniaApp`) tracks Main’s current Workspace for spawn env.
/// Settings may create a **dataDir-scoped** instance to edit another Workspace’s `secrets.toml`
/// without calling `workspaces.select` (L3).
@MainActor
final class SecretStoreController: ObservableObject {
    private let store: SecretStore
    private let workspaces: WorkspaceController?
    /// When set, load/persist this Data Dir only (Settings editor). Ignores `workspaces.current`.
    private let fixedDataDirURL: URL?
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var document: SecretStoreDocument = .empty
    /// Bumps after a successful write so Settings can refresh the spawn-bound controller.
    @Published private(set) var revision: Int = 0
    @Published var lastError: String?

    /// Draft fields for scaffold add forms.
    @Published var draftVarKey: String = ""
    @Published var draftVarValue: String = ""
    @Published var draftVarGroupId: String?
    @Published var draftGroupName: String = ""

    /// Selection for edit / delete in scaffold UI.
    @Published var selectedVarId: String?
    @Published var selectedGroupId: String?

    /// App-wide spawn-bound controller (follows `workspaces.current`).
    init(
        workspaces: WorkspaceController,
        store: SecretStore = SecretStore()
    ) {
        self.workspaces = workspaces
        self.store = store
        self.fixedDataDirURL = nil

        workspaces.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.reload()
                }
            }
            .store(in: &cancellables)

        // Initial load is fine here — App.init runs before any SwiftUI body.
        reload()
    }

    /// Settings editor scoped to one Workspace Data Dir (does not follow Main selection).
    init(dataDirURL: URL, store: SecretStore = SecretStore()) {
        self.workspaces = nil
        self.store = store
        self.fixedDataDirURL = dataDirURL.standardizedFileURL
        reload()
    }

    private var activeDataDirURL: URL? {
        if let fixedDataDirURL { return fixedDataDirURL }
        return workspaces?.current?.dataDirURL
    }

    /// Enabled Env Var pairs for Ghostty spawn injection (empty when no Workspace).
    /// Only meaningful on the app-wide (spawn) controller.
    var enabledEnvironment: [(key: String, value: String)] {
        guard activeDataDirURL != nil else { return [] }
        return document.enabledEnvironment()
    }

    func reload() {
        guard let dataDir = activeDataDirURL else {
            if document != .empty { document = .empty }
            if selectedVarId != nil { selectedVarId = nil }
            if selectedGroupId != nil { selectedGroupId = nil }
            if draftVarGroupId != nil { draftVarGroupId = nil }
            if lastError != nil { lastError = nil }
            return
        }

        do {
            let loaded = try store.load(from: dataDir)
            if loaded != document { document = loaded }
            if lastError != nil { lastError = nil }
            if let selectedVarId,
               !document.vars.contains(where: { $0.id == selectedVarId })
            {
                self.selectedVarId = nil
            }
            if let selectedGroupId,
               !document.groups.contains(where: { $0.id == selectedGroupId })
            {
                self.selectedGroupId = nil
            }
            if let draftVarGroupId,
               !document.groups.contains(where: { $0.id == draftVarGroupId })
            {
                self.draftVarGroupId = nil
            }
        } catch {
            lastError = error.localizedDescription
            if document != .empty { document = .empty }
        }
    }

    // MARK: - Groups

    func addGroup() {
        let name = draftGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            lastError = "Group name cannot be empty."
            return
        }
        var next = document
        let group = SecretGroup(name: name, enabled: true)
        next.groups.append(group)
        persist(next)
        draftGroupName = ""
        selectedGroupId = group.id
    }

    func renameGroup(_ id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = document
        guard let index = next.groups.firstIndex(where: { $0.id == id }) else { return }
        next.groups[index].name = trimmed
        persist(next)
    }

    func setGroupEnabled(_ id: String, enabled: Bool) {
        var next = document
        guard let index = next.groups.firstIndex(where: { $0.id == id }) else { return }
        next.groups[index].enabled = enabled
        persist(next)
    }

    func deleteGroup(_ id: String) {
        var next = document
        next.groups.removeAll { $0.id == id }
        for i in next.vars.indices where next.vars[i].groupId == id {
            next.vars[i].groupId = nil
        }
        if selectedGroupId == id { selectedGroupId = nil }
        if draftVarGroupId == id { draftVarGroupId = nil }
        persist(next)
    }

    // MARK: - Env Vars

    func addVar() {
        switch SecretStore.validateKey(draftVarKey) {
        case .failure(let error):
            lastError = error.localizedDescription
            return
        case .success(let key):
            var next = document
            let envVar = EnvVar(
                key: key,
                value: draftVarValue,
                enabled: true,
                groupId: draftVarGroupId
            )
            next.vars.append(envVar)
            persist(next)
            draftVarKey = ""
            draftVarValue = ""
            selectedVarId = envVar.id
        }
    }

    func updateVar(_ id: String, key: String, value: String, groupId: String?) {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        switch SecretStore.validateKey(trimmedKey) {
        case .failure(let error):
            lastError = error.localizedDescription
            return
        case .success(let validatedKey):
            var next = document
            guard let index = next.vars.firstIndex(where: { $0.id == id }) else { return }
            next.vars[index].key = validatedKey
            next.vars[index].value = value
            next.vars[index].groupId = groupId
            persist(next)
        }
    }

    func setVarEnabled(_ id: String, enabled: Bool) {
        var next = document
        guard let index = next.vars.firstIndex(where: { $0.id == id }) else { return }
        next.vars[index].enabled = enabled
        persist(next)
    }

    func deleteVar(_ id: String) {
        var next = document
        next.vars.removeAll { $0.id == id }
        if selectedVarId == id { selectedVarId = nil }
        persist(next)
    }

    // MARK: - Private

    private func persist(_ next: SecretStoreDocument) {
        guard let dataDir = activeDataDirURL else {
            lastError = SecretStore.StoreError.missingWorkspace.localizedDescription
            return
        }
        do {
            try store.write(next, to: dataDir)
            document = next
            revision += 1
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
