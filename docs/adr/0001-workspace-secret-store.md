# In-app Workspace Secret Store

Symphonia ships a Workspace-scoped Secret Store and injects Enabled Env Vars into Agent CLIs, instead of relying on per-Worktree `.env` copies or external tools (mise/direnv).

Copying `.env` does not scale with Worktrees; parent-folder env tools work but sit outside the Agent lifecycle we already own. A Postman-like store keeps one source of truth per Workspace and makes inject-or-not a first-class toggle.
