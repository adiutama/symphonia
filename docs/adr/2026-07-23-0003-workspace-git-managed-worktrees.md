# Workspace is a git repo; Worktrees are managed checkouts

A Workspace’s Main Repo is a local git repository. Symphonia creates Worktrees with `git worktree` and stores those checkouts as siblings of `main/` inside the Workspace Data Dir (ADR 0014 / 0015).

Because the Secret Store is injected by the app, Worktrees do not need to sit next to a shared `.env` or parent mise/direnv setup.

**Clarified by ADR 0013:** A Workspace is named by slug and may exist before a repo is linked; once linked there is one repo root. Parallelism is Worktrees, not multiple clones.
