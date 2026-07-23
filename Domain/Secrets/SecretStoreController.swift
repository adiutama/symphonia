import Foundation
import Combine

/// Observable Secret Store for the current Workspace (P5 scaffold).
@MainActor
final class SecretStoreController: ObservableObject {
    private let store: SecretStore
    private let workspaces: WorkspaceController
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var document: SecretStoreDocument = .empty
    @Published var lastError: String?

    /// Draft fields for scaffold add forms.
    @Published var draftVarKey: String = ""
    @Published var draftVarValue: String = ""
    @Published var draftVarGroupId: String?
    @Published var draftGroupName: String = ""

    /// Selection for edit / delete in scaffold UI.
    @Published var selectedVarId: String?
    @Published var selectedGroupId: String?

    init(
        workspaces: WorkspaceController,
        store: SecretStore = SecretStore()
    ) {
        self.workspaces = workspaces
        self.store = store

        workspaces.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)

        reload()
    }

    /// Enabled Env Var pairs for Ghostty spawn injection (empty when no Workspace).
    var enabledEnvironment: [(key: String, value: String)] {
        guard workspaces.current != nil else { return [] }
        return document.enabledEnvironment()
    }

    func reload() {
        guard let current = workspaces.current else {
            document = .empty
            selectedVarId = nil
            selectedGroupId = nil
            draftVarGroupId = nil
            lastError = nil
            return
        }

        do {
            document = try store.load(from: current.dataDirURL)
            lastError = nil
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
            document = .empty
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
        // Skip empty mid-edit keystrokes from scaffold TextFields.
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
        // Skip empty mid-edit keystrokes from scaffold TextFields.
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
        guard let current = workspaces.current else {
            lastError = SecretStore.StoreError.missingWorkspace.localizedDescription
            return
        }
        do {
            try store.write(next, to: current.dataDirURL)
            document = next
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
