# Agent rules (docs)

Only rules that steer how agents use or edit docs and are **not** already in `docs/README.md`, `docs/adr/README.md`, or `CONTEXT.md`.

## Finding decisions

- Use [`docs/adr/README.md`](adr/README.md). Do not bulk-read `docs/adr/`.
- Open related ADR links only if the task still needs them.
- Skip superseded/historical ADRs unless the task is about old layout or migration.

## Writing

- Prefer lists and short sentences over long prose.
- Keep ADRs short: decision + why, not a design essay.

## New ADRs

- Write one only if: hard to reverse · surprising without context · real trade-off.
- Naming and index location: follow [2026-08-02-0200-date-based-adr-ids](adr/2026-08-02-0200-date-based-adr-ids.md).
- Set an **Implementation** line (`not started` / `in progress` / `shipped`) when the feature needs a clear status answer.
