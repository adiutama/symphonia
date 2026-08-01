# Main repo dir is a protected, healable sibling of Worktrees (flat layout)

Inside each Workspace Data Dir, `main/` (the primary git repo) and Worktree checkouts are **flat
siblings** directly under the Workspace Data Dir — no `worktrees/` parent folder (superseded in
P1.5; see below).

```
<prefix>/<slug>/
  config.toml
  secrets.toml
  main/                 # Main Repo — protected
  <three-word>/         # Worktree checkout (sibling)
  <another-three-word>/
```

Symphonia may clone or `git init` into `main/`. Power users may CLI-clone into that same `main/`
path (or prepare a Workspace container under a custom Prefix — ADR 0015). The Main Repo does not
live outside the Workspace Data Dir.

**See ADR 0015** for Workspaces Root vs per-Workspace Prefix and the self-contained rule.

## P1.5: flattened, protected, and healed

**Flat siblings.** Earlier drafts of this ADR (and ADR 0003/0004/0012/0015) nested Worktree
checkouts under a `worktrees/` parent (`<data-dir>/worktrees/<three-word>/`). P1.5 removes that
extra level: Worktree checkouts are created directly as siblings of `main/` —
`<data-dir>/<three-word>/`. `SymphoniaPaths.workspaceWorktreeDirectory(in:threeWordName:)` returns
that sibling path; there is no `workspaceWorktreesDirectory` anymore. **No migration** — this is
pre-production; the Operator recreates Workspaces that used the old nested layout instead of
Symphonia moving folders on disk.

**Reserved names.** `main` is the one name a Worktree folder can never take, checked
case-insensitively. It is the single source of truth at
`SymphoniaPaths.reservedWorkspaceChildNames`, folded into `WorkspaceSlug.validate` (reused by
`WorktreeController.createWorktree()` for Operator-edited Worktree folder names) and re-checked
directly in `WorktreeStore.create()` / `WorktreeStore.remove()` so the guard holds even if a
caller bypasses that validator. `WorktreeStore.list()` also excludes it (plus any sibling folder
that isn't itself a git checkout — i.e. has no `.git` file/dir) so stray non-Worktree folders
never show up as Worktrees.

**Main is protected.** Main cannot be removed or archived — not just because the UI never offers
that action, but because both `WorktreeController.requestRemove(_:)` / `archive(_:)` and
`WorktreeStore.remove(...)` take a `WorktreeSummary`, and `WorktreeStore.list()` never produces
one for `main/`. `WorktreeStore.remove()` additionally refuses a reserved name outright as
defense in depth. Creating a Worktree named `main` (any case) is refused for the same reason.

**Heal on open.** `WorkspaceStore.open(at:)` calls `healMainIfNeeded(at:config:)`: if `main/` is
missing or not a git repository, it re-clones from `config.mainRemoteURL` when that's non-empty
(persisted at Workspace create time when a Clone URL was supplied, P1.4), otherwise it runs
`git init` — the same as an empty local Workspace. This is idempotent and a no-op once `main/` is
a valid git repo. `WorkspaceController` triggers it on the natural open/select/refresh hooks
(`select(_:)`, `refresh()`, and therefore also app-startup selection restore), so Main heals itself
without a dedicated "repair" action.
