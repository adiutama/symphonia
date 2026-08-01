# Date-based ADR filenames

**Status:** accepted  
**Implementation:** shipped (docs process)

Sequential ADR numbers collide when humans or agents open parallel design PRs. ADR filenames use a UTC timestamp so parallel work stays safe and **earlier vs later is obvious** when one ADR refers to another.

## Decision

1. Filename: `docs/adr/YYYY-MM-DD-HHMM-short-slug.md` (UTC time when the ADR is drafted, 24h clock).
2. Lexicographic order of filenames is chronological order. Prefer that when reading “this amends that.”
3. **Same-minute clash** (rare): append `-2`, `-3` to the slug, or use seconds: `YYYY-MM-DD-HHMMSS-short-slug.md`.
4. **Index** every ADR in `docs/adr/README.md` (newest first is fine; within a day, HHMM keeps order clear).
5. Refer to ADRs by full filename stem in prose (e.g. `ADR 2026-08-02-0200-date-based-adr-ids`).

All ADRs in this repo use this shape. Historical files were backfilled with HHMM from their original write order.

## Considered options

1. **Date only (`YYYY-MM-DD-slug`):** parallel-safe across days; same-day order is ambiguous (slug sort ≠ write order). Rejected.
2. **Same-day ordinal (`-01`, `-02`):** ordered, but parallel agents fight over the next ordinal again.
3. **Accepted (date + UTC HHMM):** parallel-friendly; filename sorts in time order; references to “previous” ADRs stay readable.

## Consequences

- Agents never ask “what is the next ADR number?”
- When drafting an ADR that amends another from today, the earlier file’s HHMM is visibly smaller.
- `docs/AGENTS.md` describes this naming rule.
