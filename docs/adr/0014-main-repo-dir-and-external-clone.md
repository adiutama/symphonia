# Main repo dir separate from worktrees (same container)

Inside each Workspace Data Dir, `main/` (primary git repo) and `worktrees/` (Agent checkouts) are siblings — never mixed in one folder.

```
<prefix>/<slug>/
  config.json
  secrets.env
  main/
  worktrees/
    <agent-slug>/
```

Symphonia may clone or `git init` into `main/`. Power users may CLI-clone into that same `main/` path (or prepare a Workspace container under a custom Prefix — ADR 0015). The Main Repo does not live outside the Workspace Data Dir.

**See ADR 0015** for Workspaces Root vs per-Workspace Prefix and the self-contained rule.
