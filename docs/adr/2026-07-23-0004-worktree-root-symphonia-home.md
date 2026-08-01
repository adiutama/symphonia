# Default Worktree root under ~/.symphonia (superseded)

**Historical.** Early layout parked managed checkouts under a global path such as `~/.symphonia/worktrees/<repo-name>/…`.

**Current layout:** each Workspace is self-contained under `<prefix>/<slug>/` with `main/` and Worktree folders as **flat siblings** (ADR 2026-07-23-0012-workspace-data-dir-plaintext / 2026-07-23-0014-main-repo-dir-and-external-clone / 2026-07-23-0015-workspace-prefix-self-contained). Do not use a `worktrees/` parent folder.
