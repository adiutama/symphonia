import Foundation

/// Focusable terminal session: Main Repo or an Agent Worktree.
///
/// Owns Main CLI cwd / spawn env and scopes Overlay PTYs (Editor + Background).
enum FocusedSession: Equatable, Identifiable, Sendable {
    /// Main Repo at `<workspace>/main/` — same Editor / Background / secrets treatment as an Agent.
    case mainRepo(workspaceId: String, mainDirectory: URL, slug: String)
    /// Agent Worktree — a sibling of `main/` under `<workspace>/<three-word>/` (P1.5).
    case agent(AgentSummary)

    var id: String {
        switch self {
        case .mainRepo(let workspaceId, _, _):
            return "main:\(workspaceId)"
        case .agent(let agent):
            return "agent:\(agent.id)"
        }
    }

    /// Ghostty cwd for Main CLI and Overlay spawn.
    var workingDirectory: String {
        switch self {
        case .mainRepo(_, let mainDirectory, _):
            return mainDirectory.path
        case .agent(let agent):
            return agent.worktreeURL.path
        }
    }

    var isMainRepo: Bool {
        if case .mainRepo = self { return true }
        return false
    }

    var agent: AgentSummary? {
        if case .agent(let agent) = self { return agent }
        return nil
    }

    var workspaceId: String? {
        switch self {
        case .mainRepo(let workspaceId, _, _):
            return workspaceId
        case .agent:
            return nil
        }
    }

    /// Sidebar / chrome label.
    var displayTitle: String {
        switch self {
        case .mainRepo(_, _, let slug):
            return "Main Repo · \(slug)"
        case .agent(let agent):
            return agent.primaryLabel
        }
    }

    static func mainRepo(for workspace: WorkspaceSummary) -> FocusedSession {
        .mainRepo(
            workspaceId: workspace.id,
            mainDirectory: SymphoniaPaths.workspaceMainDirectory(in: workspace.dataDirURL),
            slug: workspace.slug
        )
    }
}

extension AgentSummary {
    /// Branch name primary; Three-Word folder as fallback when branch unknown.
    var primaryLabel: String {
        let branch = branchName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return branch.isEmpty ? threeWordName : branch
    }

    /// Subtle secondary line — folder name when branch is shown as primary.
    var secondaryLabel: String? {
        let branch = branchName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !branch.isEmpty, branch != threeWordName else { return nil }
        return threeWordName
    }
}
