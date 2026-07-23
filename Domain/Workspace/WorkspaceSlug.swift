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

        let reserved = ["config.json", "secrets.json", "secrets.env", "main", "worktrees"]
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
