# Background CLIs: many freeform peek overlays

An Agent may have many Background CLIs — freeform shells or commands in the Worktree (e.g. Convex backend + Next.js) with the same Secret injection as the Main CLI. Creating another is a first-class, easy action.

Background CLIs use the same Overlay UX as the Editor: the Operator **peeks** (show) and **hides** them; hiding does not kill the process. Main CLI stays the home context; backgrounds are not permanent peer panes.
