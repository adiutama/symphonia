# Default Worktree root under ~/.symphonia (superseded)

**Historical.** Early layout parked managed checkouts under a global path such as `~/.symphonia/worktrees/<repo-name>/…`.

**Current layout:** each Workspace is self-contained under `<prefix>/<slug>/` with `main/` and Worktree folders as **flat siblings** (ADR 0012, 0014, 0015). Do not use a `worktrees/` parent folder.
