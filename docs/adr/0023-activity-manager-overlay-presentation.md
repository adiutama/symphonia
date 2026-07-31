# Activity Manager; Overlay is a Presentation

Symphonia opens craft surfaces (shells, editors, file managers, …) through a mini **launcher** and tracks them in an **Activity Manager** (Glance UI). An **Activity** is either **Overlay** (internal peekable PTY) or **External** (GUI/app outside Symphonia). Overlay is no longer the umbrella for “anything opened” — it is one Presentation state.

## Decision

**TUI / Overlay is the full experience; GUI / External is a documented escape hatch.**

- Configuring a tool asks **kind first**: TUI → command text; GUI → app file picker (path / bundle id). Presentation is stored explicitly; basename heuristics are fallback only (e.g. empty `$EDITOR`).
- **Activity Manager** actions: **Open** (spawn or reuse), **Focus**, **End**. Overlay also has **hide** via Toggle Overlay / Switch Worktree (hide ≠ kill). External has no peek/hide.
- **Glance** lists Activities Symphonia opened or adopted (e.g. Changes, Shells, Editors, Files). Main CLI is home — not a Glance row. External rows never fake Overlay semantics.
- Already-running GUI (e.g. Cursor open before Symphonia): **Open** with the Worktree path reuses the app; Glance adopts/updates the Activity; **Focus** activates. Symphonia does not require owning the process from cold start.
- When the Operator chooses GUI, remind once (Settings + first-time) that full peek/hide Glance UX is Overlay/TUI.

## Considered options

1. **CLI/TUI only** — simplest Overlay model; rejects Cursor/Finder as first-class. Too harsh for Operators who need a GUI escape.
2. **First-class GUI everywhere** — dual architecture, weak session truth in Glance. Rejected as product dilution.
3. **Middle path (accepted)** — Activity Manager for both; Overlay = internal Presentation; External = launch/focus/end only.

## Consequences

- ADR 0006–0008 remain valid for **Overlay** Activities (hide ≠ quit; switcher; editor weight). They do not define External behavior.
- Overlay Switcher stays Overlay-scoped until deliberately widened or folded into Glance.
- Implementation still early (Glance prototype; Editor already branches `terminalOverlay` vs `externalApp`); domain language and Settings/Glance shape should follow this ADR going forward.
