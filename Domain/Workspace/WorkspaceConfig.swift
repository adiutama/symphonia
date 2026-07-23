import Foundation

/// Persisted Workspace Setting at `<workspace-data-dir>/config.json` (ADR 0012, 0015, 0016).
struct WorkspaceConfig: Codable, Equatable, Sendable {
    /// Operator-picked Slug (folder name under Prefix).
    var slug: String

    /// Optional Prefix override (ADR 0015). `nil` = Global Workspaces Root.
    var prefix: String?

    /// Workspace override for Main CLI command. Empty string is a valid override (bare shell).
    var mainCLICommand: String?

    /// Workspace override for Editor command. Empty = `$EDITOR` at resolve.
    var editorCommand: String?

    /// Workspace override for Leader.
    var leaderKey: String?

    /// Workspace override for Base Ref.
    var baseRef: String?

    enum CodingKeys: String, CodingKey {
        case slug, prefix, mainCLICommand, editorCommand, leaderKey, baseRef
    }

    init(
        slug: String,
        prefix: String? = nil,
        mainCLICommand: String? = nil,
        editorCommand: String? = nil,
        leaderKey: String? = nil,
        baseRef: String? = nil
    ) {
        self.slug = slug
        self.prefix = prefix
        self.mainCLICommand = mainCLICommand
        self.editorCommand = editorCommand
        self.leaderKey = leaderKey
        self.baseRef = baseRef
    }

    /// Map to Effective Setting overrides (Prefix → `workspacesRoot`).
    var asOverrides: WorkspaceSettingOverrides {
        WorkspaceSettingOverrides(
            mainCLICommand: mainCLICommand,
            editorCommand: editorCommand,
            leaderKey: leaderKey,
            workspacesRoot: prefix,
            baseRef: baseRef
        )
    }

    /// Apply chrome edits back into the persisted config shape.
    mutating func apply(overrides: WorkspaceSettingOverrides) {
        mainCLICommand = overrides.mainCLICommand
        editorCommand = overrides.editorCommand
        leaderKey = overrides.leaderKey
        prefix = overrides.workspacesRoot
        baseRef = overrides.baseRef
    }
}

/// Lightweight list row for scaffold UI.
struct WorkspaceSummary: Equatable, Identifiable, Sendable {
    /// Stable id = absolute Workspace Data Dir path (slug alone is not unique across Prefixes).
    var id: String { dataDirURL.path }

    var slug: String
    /// Stored Prefix override, if any (`nil` means default Workspaces Root at create/open time).
    var prefix: String?
    var dataDirURL: URL
    /// Whether `main/` looks like a git repository (`.git` present).
    var mainIsGitRepo: Bool
}
