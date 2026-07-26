# Editor Overlay: hide, don't quit

The Editor is a terminal editor (e.g. vim, nano) in an Overlay PTY on the Worktree. Leaving the Overlay **hides** it and returns focus to the Main CLI; the editor process stays alive so the Operator can show it again with buffer/state intact.

**Switch Worktree** also only hides — the Editor PTY stays alive until the Operator **Close Overlay**s it, the owning Worktree / Workspace is removed, or the app quits. Overlay processes are as durable as Main CLI for that session.

Quitting the editor (e.g. `:q`) is an explicit Operator action, not the default of **Toggle Overlay**.
