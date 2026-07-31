import Foundation

/// Validates Operator-pasted git remotes for clone (HTTPS, HTTP, SSH, scp-like).
///
/// Auto-detects form — no protocol picker. Accepts what `git clone` typically takes.
enum GitRemoteURL {
    enum Kind: String, Equatable {
        case https
        case http
        case ssh
        case git
    }

    enum ValidationError: LocalizedError, Equatable {
        case empty
        case invalid

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Repository URL is required."
            case .invalid:
                return "Enter an https, http, ssh, or git@host:path URL."
            }
        }
    }

    struct Parsed: Equatable {
        let normalized: String
        let kind: Kind
    }

    /// Trim and validate a remote URL. Returns normalized string + detected kind.
    static func validate(_ raw: String) -> Result<Parsed, ValidationError> {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return .failure(.empty) }
        // Reject whitespace mid-string / control characters.
        if url.contains(where: { $0.isWhitespace || $0.isNewline }) {
            return .failure(.invalid)
        }

        let lower = url.lowercased()

        if lower.hasPrefix("https://") {
            return validateURLScheme(url, kind: .https, requireHostPath: true)
        }
        if lower.hasPrefix("http://") {
            return validateURLScheme(url, kind: .http, requireHostPath: true)
        }
        if lower.hasPrefix("ssh://") {
            return validateURLScheme(url, kind: .ssh, requireHostPath: true)
        }
        if lower.hasPrefix("git://") {
            return validateURLScheme(url, kind: .git, requireHostPath: true)
        }

        // scp-like: git@github.com:org/repo.git  or  user@host:path
        if looksLikeSSHSCP(url) {
            return .success(Parsed(normalized: url, kind: .ssh))
        }

        return .failure(.invalid)
    }

    private static func validateURLScheme(
        _ url: String,
        kind: Kind,
        requireHostPath: Bool
    ) -> Result<Parsed, ValidationError> {
        guard let components = URLComponents(string: url),
              let host = components.host,
              !host.isEmpty
        else {
            return .failure(.invalid)
        }
        if requireHostPath {
            let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // Allow host-only only for rare cases; prefer a path (org/repo).
            // Empty path is still a technically valid URL but useless for clone — require path.
            if path.isEmpty {
                return .failure(.invalid)
            }
        }
        _ = kind // used by caller
        return .success(Parsed(normalized: url, kind: kind))
    }

    /// `user@host:path` with at least one `/` in the path segment.
    private static func looksLikeSSHSCP(_ url: String) -> Bool {
        // Must not look like a normal URL scheme.
        if url.contains("://") { return false }
        guard let at = url.firstIndex(of: "@") else { return false }
        let afterAt = url[url.index(after: at)...]
        guard let colon = afterAt.firstIndex(of: ":") else { return false }
        let host = afterAt[..<colon]
        let path = afterAt[afterAt.index(after: colon)...]
        guard !host.isEmpty, host.contains(".") || host == "localhost" else { return false }
        // path should look like org/repo(.git)
        let pathString = String(path)
        guard !pathString.isEmpty, pathString.contains("/") else { return false }
        // Reject windows drive confusion like C:\...
        if pathString.contains("\\") { return false }
        return true
    }
}
