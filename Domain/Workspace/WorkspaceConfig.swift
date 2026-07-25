import Foundation

/// Persisted Workspace Setting at `<workspace-data-dir>/config.toml` (T.2).
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

    /// Three-Word folder names of Worktrees soft-archived under this Workspace (P1.3, ADR 0020
    /// spirit: remove still exists; archive is softer). Archived Worktrees keep their folder and
    /// git worktree registration on disk — only the flag lives here. `nil`/missing (legacy
    /// `config.toml` written before this field existed) means none archived.
    var archivedThreeWordNames: [String]?

    /// Remote URL `main/` was cloned from at Workspace create time (P1.4). Persisted so a future
    /// heal-on-open (P1.5) can re-clone `main/` if it goes missing or stops being a git repo.
    /// `nil` means Main was created with `git init` (no known remote).
    var mainRemoteURL: String?

    enum CodingKeys: String, CodingKey {
        case slug, prefix, mainCLICommand, editorCommand, leaderKey, baseRef, archivedThreeWordNames, mainRemoteURL
    }

    init(
        slug: String,
        prefix: String? = nil,
        mainCLICommand: String? = nil,
        editorCommand: String? = nil,
        leaderKey: String? = nil,
        baseRef: String? = nil,
        archivedThreeWordNames: [String]? = nil,
        mainRemoteURL: String? = nil
    ) {
        self.slug = slug
        self.prefix = prefix
        self.mainCLICommand = mainCLICommand
        self.editorCommand = editorCommand
        self.leaderKey = leaderKey
        self.baseRef = baseRef
        self.archivedThreeWordNames = archivedThreeWordNames
        self.mainRemoteURL = mainRemoteURL
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
