# Remove Worktree: confirm; default keep branch

Removing a Worktree always confirms in Command Center (or equivalent UI). **Default:** remove the Worktree folder and unregister the git worktree; **keep the git branch**.

Optional actions at confirm time: also delete the branch, or archive instead of delete. Silent `branch -D` is unsafe when the branch name no longer matches the Three-Word folder.
