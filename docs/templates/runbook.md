# Symphonia implementation runbook

Durable process for building against frozen docs v0. Copy this file to `.local/runbook.md` and adjust freely — `.local/` is gitignored.

## Sources of truth

| Kind | Location | Rule |
|------|----------|------|
| Language | `CONTEXT.md` | Update when a term crystallises; no implementation detail |
| Product intent | `docs/vision.md` | Update when goals/non-goals change |
| Decisions | `docs/adr/` | New ADR only if hard to reverse + surprising + real trade-off |
| Your backlog | `.local/tasks.md` | Status lives here only |
| Session state | `.local/progress.md` | What you were doing / blockers |

If code and docs disagree, **stop and reconcile** before adding features.

## Cadence (each work session)

1. **Orient** — Read `.local/progress.md` (create if missing). Skim active phase in `.local/tasks.md`.
2. **Pick one task** — Smallest `todo` that unblocks the phase exit criteria (see tasks template). Prefer finishing a phase spike over starting three features.
3. **Mark `doing`** — Only one `doing` row at a time when possible.
4. **Implement** — Keep diffs aligned to that task ID (e.g. `P1.2`).
5. **Check language** — New UI copy or types should use `CONTEXT.md` terms (Workspace, Agent, Overlay, …).
6. **Decide** — If you hit a fork not covered by an ADR, either (a) choose the reversible default and note it in `progress.md`, or (b) write an ADR before building the irreversible path.
7. **Close the loop** — Mark task `done` or `blocked` + reason. Update `progress.md` with: done today, next up, blockers.
8. **Commit** — When the task (or a coherent slice) is shippable. Prefer unsigned only if signing is broken and you explicitly allow it.

## Phase gates (do not skip)

| From → To | Gate |
|-----------|------|
| 0 → 1 | App builds; libghostty linked or stubbed with a clear spike plan |
| 1 → 2 | Interactive shell works in-app (Phase 1 exit) |
| 2 → 3 | Global prefs + Effective Setting readable/writable |
| 3 → 4 | Can create a Workspace Data Dir with `main/` + `worktrees/` |
| 4 → 5 | Can create/focus/remove an Agent with Main CLI in the Worktree |
| 5 → 6 | Enabled secrets appear in a newly spawned CLI env |
| 6 → 7 | Editor + one Background peek/hide without killing processes |
| 7 → 8 | Leader Command Mode drives the main Operator actions |

## Spike rules

- Spikes may be messy; confine them to a branch or a clearly named spike folder.
- Before merging spike learning into main architecture, update `.local/spikes/<topic>.md` with: goal, what we tried, decision, follow-up task IDs.
- Spikes do not skip Phase 1 gate: a dead terminal blocks everything.

## When to touch committed docs

| Change | Action |
|--------|--------|
| New domain term | `CONTEXT.md` |
| Goal / non-goal shift | `docs/vision.md` |
| Hard trade-off decided | New `docs/adr/NNNN-….md` + row in `docs/README.md` |
| Task map structure wrong | Update `docs/templates/tasks.md`, then refresh your `.local/tasks.md` |

Do **not** commit secrets, machine paths with home-dir PII you care about, or `.local/` contents.

## Definition of done (feature task)

- [ ] Behavior matches the cited ADR / glossary term
- [ ] Happy path manually verified on macOS
- [ ] Failure mode is explicit (error UI or log), not silent
- [ ] `.local/tasks.md` status updated
- [ ] No secrets written into Worktree checkouts

## Recovery

- Lost place → `progress.md` + last `doing` task
- Docs drift → diff against `CONTEXT.md` / latest ADR; fix docs or code before new work
- Fresh machine → copy `docs/templates/*` into `.local/` again (see bootstrap below)
