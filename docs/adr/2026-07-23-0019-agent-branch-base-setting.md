# Worktree branch base is an Effective Setting

New Worktree branches are created from a configurable **base ref** (e.g. `main` or `develop`). That base is an Effective Setting: Workspace override if set, else global default (typically the Main Repo’s default branch name).

Symphonia resolves the base from settings, then creates the branch (Three-Word Name or Operator-supplied) from that ref.
