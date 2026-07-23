# Self-contained Workspace dirs; global root + per-Workspace prefix

A Workspace is always **one directory tree**: config, secrets, `main/`, and Worktree checkouts live together as flat siblings. Symphonia does not split Main Repo onto one path and Worktrees onto another.

**Global:** one configurable workspaces root at a time (default `~/.symphonia/workspaces`). That is what you replace when you want a different default home for all Workspaces.

**Per Workspace:** each project may override the **prefix** (the parent directory used for that Workspace’s container). Layout under the slug stays the same:

```
<prefix>/<slug>/
  config.toml
  secrets.toml
  main/
  <three-word>/
```

- Default Workspace: `prefix` = global workspaces root  
- Override example: global `~/.symphonia/workspaces`, but one Workspace uses prefix `/Volumes/Fast/sym-workspaces` → `/Volumes/Fast/sym-workspaces/<slug>/…`

Power users who clone via CLI still end up with Main Repo inside that container (`…/<slug>/main`), whether Symphonia cloned it or they pointed an override prefix at a place they prepared — not a Main Repo floating outside the Workspace container.

Supersedes the “external main path + worktrees still under ~/.symphonia” split considered earlier.

Prefix is one instance of **Workspace Setting overrides Global Setting** (ADR 0016).
