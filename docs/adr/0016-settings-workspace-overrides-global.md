# Settings precedence: Workspace overrides global

Configuration is layered. A **Workspace (project) setting always overrides** the Operator-wide / app global default when both are set.

Examples: Prefix, Main CLI command, Leader key (if ever per-Workspace), Secret Store is Workspace-owned already.

Resolve as: effective value = Workspace value if present, else global default. Layers are only **global → Workspace** (no extra parent tier).
