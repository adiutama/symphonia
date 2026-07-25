import Foundation

/// Operator-picked Workspace folder name (ADR 0013).
enum WorkspaceSlug {
    enum ValidationError: LocalizedError, Equatable {
        case empty
        case invalidCharacters(String)
        case reservedName(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Slug cannot be empty."
            case .invalidCharacters(let slug):
                return "Slug “\(slug)” has invalid characters. Use letters, numbers, hyphens, underscores, or dots; no path separators or “..”."
            case .reservedName(let slug):
                return "Slug “\(slug)” is reserved."
            }
        }
    }

    /// Validate an Operator-readable slug for use as a single path component.
    static func validate(_ raw: String) -> Result<String, ValidationError> {
        let slug = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { return .failure(.empty) }

        // "worktrees" stays reserved for safety even though P1.5 flattened Worktree checkouts to
        // siblings of `main/` (no `worktrees/` parent anymore). `main` is the single source of
        // truth in `SymphoniaPaths.reservedWorkspaceChildNames` (ADR 0014) — folded in here so
        // this validator (reused for both Workspace slugs and, in `WorktreeController.createWorktree()`,
        // Operator-edited Worktree folder names) refuses it case-insensitively either way.
        let reserved = Set([
            "config.toml", "config.json",
            "secrets.toml", "secrets.json", "secrets.env",
            "worktrees",
        ])
            .union(SymphoniaPaths.reservedWorkspaceChildNames)
        if slug == "." || slug == ".." || reserved.contains(slug.lowercased()) {
            return .failure(.reservedName(slug))
        }

        if slug.contains("..")
            || slug.contains("/")
            || slug.contains("\\")
            || slug.contains("\0")
            || slug.hasPrefix(".")
            || slug.hasSuffix(".")
        {
            return .failure(.invalidCharacters(slug))
        }

        // Operator-readable single path component: alphanumerics plus - _ .
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard slug.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return .failure(.invalidCharacters(slug))
        }

        return .success(slug)
    }
}
