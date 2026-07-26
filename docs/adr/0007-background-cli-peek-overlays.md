# Background CLIs: many freeform peek overlays

A Worktree may have many Background CLIs — freeform shells or commands in the Worktree (e.g. Convex backend + Next.js) with the same Secret injection as the Main CLI. Creating another is a first-class, easy action (**Overlay Terminal**).

Background CLIs use the same Overlay UX as the Editor: the Operator **peeks** (show) and **hides** them via **Toggle Overlay**; hiding does not kill the process. **Switch Worktree** likewise only hides — servers keep running until **Close Overlay**, owner removal, or app quit. Main CLI stays the home context; backgrounds are not permanent peer panes.
