# Plaintext Workspace data dir under ~/.symphonia

Secret Store values are plaintext on disk (same honesty as `.env`), with tight file permissions and **never** written into Worktree checkouts.

Each Workspace has its own directory under `~/.symphonia/` (configurable) holding that Workspace’s secrets, config, Main Repo directory, and Worktrees. Global app prefs can still live at the `~/.symphonia` root.

Example shape (default):

```
~/.symphonia/
  preferences.toml
  workspace-index.toml
  workspaces/
    <slug>/
      config.toml
      secrets.toml          # plaintext, mode 0600
      main/                 # primary git repo (see ADR 2026-07-23-0014-main-repo-dir-and-external-clone)
      <three-word>/         # Worktree checkout (sibling of main/)
```

Supersedes the flatter “only worktrees under `~/.symphonia/worktrees/`” layout from ADR 2026-07-23-0004-worktree-root-symphonia-home. Folder name `<slug>` is Operator-picked (ADR 2026-07-23-0013-workspace-slug-no-multi-clone). Main Repo vs Worktrees separation and external CLI clones: ADR 2026-07-23-0014-main-repo-dir-and-external-clone.

**See ADR 2026-07-23-0015-workspace-prefix-self-contained** for Workspaces Root / Prefix; the container stays self-contained.
