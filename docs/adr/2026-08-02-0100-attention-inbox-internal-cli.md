# Attention Inbox for internal CLIs

**Status:** accepted  
**Implementation:** not started

When the Operator runs several coding agents in parallel (Main CLI / Overlay TUIs), OS dings and dots give no chronological order and no jump-to-source. Symphonia will own an **Attention Inbox**: capture “needs you / done” from **internal PTYs only**, keep events in time order, and navigate to the surface that raised them.

## Decision

1. **Internal only.** Attention applies to **Main CLI** and **Overlay** PTYs (CLI/TUI). **External** Activities (e.g. Cursor GUI) are out of scope (no adapters, no OS-notification scraping).
2. **Chronological Inbox.** Each raise becomes an **Attention Event** (timestamp, target session/surface, reason, optional title/body, unread). The Operator browses history and unread state; a ding alone is not enough.
3. **Navigate.** Command Center gains an **Attention** nest (pick by time). Commands: focus next / previous unread Attention (and clear that event when the Operator lands on its target). Switching Worktree/Workspace as needed is part of navigate.
4. **Two capture paths (complementary):**
   - **Passive:** Ghostty runtime actions Symphonia already receives but currently ignores. At minimum `RING_BELL` and `DESKTOP_NOTIFICATION`; optionally `COMMAND_FINISHED` / title changes under policy.
   - **Active:** a small **Notify** CLI on `PATH` (e.g. `symphonia notify "…"`) that agents, hooks, or scripts can call inside a PTY so tools that do not self-notify still raise Attention.
5. **Vendor-agnostic.** No Codex-/Claude-specific SDKs. Any CLI/TUI that bells, OSC-notifies, or calls Notify feeds the same Inbox.
6. **Not Editor weight.** ADR 2026-07-23-0008-overlay-switcher-editor-weight “attention” means Overlay UI weight (Editor > Background). That is unrelated to Attention Events.

## Considered options

1. **External + internal unified inbox:** rejected for v1; External has no reliable agent-done API and dilutes the control plane.
2. **Dings only (no Inbox):** rejected; chronological order and jump-to-source are the product.
3. **Parse PTY scrollback / agent protocols:** rejected as fragile and vendor-locked; prefer Ghostty actions + Notify.
4. **Accepted:** internal PTY signals + Notify CLI → Attention Manager → Command Center / hotkeys.

## Consequences

- New domain module (e.g. Attention Manager) wired from Ghostty `action_cb` and from Notify; Command Center nest + keymap entries; optional sidebar/Glance unread cues.
- Main CLI must be a valid Attention **target** even though it is not a Glance row (home stays home; Inbox is the inventory for urgency).
- Suppress or de-prioritize events when the target surface is already focused (policy detail at implement time).
- “Is Attention shipped?” → this ADR’s **Implementation** line. Until it reads `shipped`, the answer is **no**.
