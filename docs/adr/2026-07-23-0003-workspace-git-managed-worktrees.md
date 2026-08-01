# Workspace is a git repo; Worktrees are managed checkouts

A Workspace’s Main Repo is a local git repository. Symphonia creates Worktrees with `git worktree` and stores those checkouts as siblings of `main/` inside the Workspace Data Dir (ADR 2026-07-23-0014-main-repo-dir-and-external-clone / 2026-07-23-0015-workspace-prefix-self-contained).

Because the Secret Store is injected by the app, Worktrees do not need to sit next to a shared `.env` or parent mise/direnv setup.

**Clarified by ADR 2026-07-23-0013-workspace-slug-no-multi-clone:** A Workspace is named by slug and may exist before a repo is linked; once linked there is one repo root. Parallelism is Worktrees, not multiple clones.
