# Command Center: registry of Commands with configurable aliases

## Context

Command Center is the Raycast-like control surface after the Leader. Operators want **every** app action reachable there, with **user-editable aliases** (free text, optional slash, comma-separated multiples) and **shortcuts**, not hardcoded `/editor`-style verbs in the controller.

## Decision

1. **Command** is first-class: stable `id`, title, group, optional default aliases / shortcut, and a run handler gated by **context** (focused session, Overlay visible, …).
2. **App areas export Commands** via an in-process `CommandProvider` (or equivalent registrar). Command Center **discovers + filters + runs**; it does not own the action list as a private switch forever.
3. **Aliases** are free text (with or without `/`). One Command may have **many** aliases, edited/stored as **comma-separated** strings. **Default aliases are empty** (ADR 0022); Global Settings overrides bindings by Command id.
4. **Sequences** (Normal mode) and optional **shortcuts** are bound per Command id in Settings; conflicts are rejected or warned. Default sequences and global chords are defined in ADR 0022.
5. **Leader** remains only “enter Command Center” (ADR 0009); it is not an alias for a Command.

## Consequences

- Palette actions come from the registry; Settings has a Commands section for aliases / sequences / shortcuts (ADR 0022 for the default map).
- Matching: type filters titles and aliases (aliases often empty until the Operator adds them); Normal-mode sequences auto-run on unique match.

## Non-goals (this ADR)

- Extension packaging, sandboxing, or third-party install
- Workspace-overridable command bindings (Global Settings only)
- Replacing Leader with a Command
