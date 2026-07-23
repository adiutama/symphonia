# Workspace data dir id is an Operator slug

The Workspace Data Dir folder name is an **Operator-picked slug** (readable, renameable), not a hash of the repo path.

Symphonia does not aim to support multiple clones of the same project as separate Workspaces — parallelism is Worktrees inside one Workspace. Path-hash ids optimized for multi-clone are unnecessary complexity.

A Workspace may be created (and named) before a git repo exists; the slug can change when the Operator settles the repo name. Binding to a repo root is a step in the Workspace lifecycle, not the only way to create one.

**See ADR 0014** for Main Repo vs Worktrees layout and linking an external CLI clone.
