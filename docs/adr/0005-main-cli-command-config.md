# Main CLI command: global default + Workspace override

The Main CLI is a configured command (the coding agent), not a bare assumption of one vendor. Symphonia has an Operator-wide default; a Workspace may override it.

Starting an Agent runs that resolved command with cwd = the Worktree and the Workspace Secret Store's Enabled Env Vars injected (spawn-time in v1).
