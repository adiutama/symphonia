import Foundation

/// On-disk Secret Store document (Workspace Data Dir `secrets.json`, mode 0600).
///
/// Format version 1 — see Domain README. Values are plaintext (ADR 0012).
struct SecretStoreDocument: Codable, Equatable, Sendable {
    var version: Int
    var groups: [SecretGroup]
    var vars: [EnvVar]

    static let currentVersion = 1

    static let empty = SecretStoreDocument(
        version: currentVersion,
        groups: [],
        vars: []
    )
}

/// Named subset of Env Vars that can be Enabled or disabled together.
struct SecretGroup: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    /// When false, member Env Vars are not injected even if individually Enabled.
    var enabled: Bool

    init(id: String = UUID().uuidString, name: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.enabled = enabled
    }
}

/// Single named key/value in the Secret Store.
struct EnvVar: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var key: String
    var value: String
    /// Per-var Enabled toggle (also gated by parent group when `groupId` is set).
    var enabled: Bool
    /// Optional Secret Group membership; nil = ungrouped.
    var groupId: String?

    init(
        id: String = UUID().uuidString,
        key: String,
        value: String,
        enabled: Bool = true,
        groupId: String? = nil
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.enabled = enabled
        self.groupId = groupId
    }
}

extension SecretStoreDocument {
    /// Env Vars that should be injected at CLI spawn (ADR 0002).
    ///
    /// A var is included when it is Enabled and either ungrouped or its group is Enabled.
    /// Later declarations of the same key win (last write).
    func enabledEnvironment() -> [(key: String, value: String)] {
        let groupEnabled: [String: Bool] = Dictionary(
            uniqueKeysWithValues: groups.map { ($0.id, $0.enabled) }
        )

        var ordered: [(key: String, value: String)] = []
        var indexByKey: [String: Int] = [:]

        for envVar in vars {
            let key = envVar.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, envVar.enabled else { continue }

            if let groupId = envVar.groupId {
                guard groupEnabled[groupId] == true else { continue }
            }

            let pair = (key: key, value: envVar.value)
            if let existing = indexByKey[key] {
                ordered[existing] = pair
            } else {
                indexByKey[key] = ordered.count
                ordered.append(pair)
            }
        }

        return ordered
    }
}
