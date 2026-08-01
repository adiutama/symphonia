# Worktree folder is auto; branch name is independent

The **Worktree directory** always uses an auto **Three-Word Name** (e.g. `<workspace-data-dir>/blue-frog-knight/`). That folder is the stable on-disk identity of the Worktree — not important as a human label.

The **git branch** may be Operator-chosen at create time, left as the auto three-word, or changed afterward. Branch name is not required to match the folder name.

No product branch prefix.

Supersedes treating “branch name = folder name” as one identifier.

**Default at create:** if the Operator does not supply a branch name, create a new branch named the same as the Three-Word folder (e.g. folder `blue-frog-knight` → branch `blue-frog-knight`) from the Main Repo’s default base. Folder and branch may diverge afterward without renaming the folder.
