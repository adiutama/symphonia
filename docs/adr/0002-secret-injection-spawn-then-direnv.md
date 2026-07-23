# Secret injection at CLI start

Symphonia injects the Workspace Secret Store's Enabled Env Vars when a Main or Background CLI **starts**. Toggles do not rewrite a live shell; restart the CLI (e.g. Reload CLI) to pick up changes.

Already-running child processes keep their start-time env until restarted.

Spawn-time injection removes the need to copy `.env` into every Worktree checkout.
