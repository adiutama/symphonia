# Three-word auto names for Worktree folders (and optional branches)

New Worktrees get a random **three-word kebab** folder name as a sibling of `main/` (e.g. `blue-frog-knight`) so the Operator can start without inventing a label. Collision-checked against existing Worktree folders; regenerate on clash.

The git **branch** may use that same string, an Operator-supplied name, or a different name afterward. Folder and branch are not required to stay in sync — see ADR 2026-07-23-0018-agent-folder-auto-branch-independent.

**Pattern:** `{word}-{word}-{word}` — lowercase, hyphen-separated, fixed word list. No product prefix on auto branch names when branch follows the auto string.
