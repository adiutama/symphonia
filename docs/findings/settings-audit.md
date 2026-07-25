# Settings audit findings

Confirmed 2026-07-25. Fix in batches; verify between batches. Raycast/Supacode Settings is the UI reference (topic categories, no footer Save chrome, auto-apply). Product decision (2026-07-25): Settings has no sidebar search; main window sidebar is not collapsible.

Status: `open` · `batch1` · `done` · `defer`

---

## Critical

| # | Finding | Status |
|---|---------|--------|
| 1 | TOML inline `#` after quoted strings breaks parse (`PreferencesToml`) | done |

## High — UI / IA

| # | Finding | Status |
|---|---------|--------|
| 2 | Categories wrong — Global one nav leaf per field; use topic pages (Raycast-style) | done |
| 3 | Remove “Effective Setting” from Settings nav | done |
| 4 | Layout — sparse one-field pages, nested card, dead space | done |
| 5 | Title spam — same label 3–5× (sidebar / window / form / field) | done |
| 6 | Weak field affordance — empty/filled values look non-editable | done |
| 7 | Centered sidebar toggle from `NavigationSplitView` | done |
| 8 | Search misaligned — detail/toolbar `.searchable` vs sidebar (Raycast: search in sidebar) | done |
| 9 | Placeholders bad — prompts read as values (`empty = $EDITOR`, `inherit Global`) | done |
| 10 | Commands UI — dual search + “Short-cut” wrap / column misalignment | done |
| 11 | Save / Reload / Reset chrome wrong (auto-apply; Raycast-style) | done |
| 12 | Save also writes Global + Workspace every time | done |

## High — behavior

| # | Finding | Status |
|---|---------|--------|
| 13 | Workspace Main CLI empty → inherit; can’t force bare shell (`""` vs `nil`) | done |
| 14 | Prefix edit is metadata-only (no Data Dir move / index sync) | done |
| 15 | Deep-links incomplete; `/settings` bypasses `SettingsNavigation` | done |

## Medium

| # | Finding | Status |
|---|---------|--------|
| 16 | Mixed `.tag` vs `NavigationLink` selection models | done |
| 17 | Naming collision — Settings / Effective Setting / Command Center “Settings” group | done |
| 18 | Leader empty warned but not blocked on save | done |
| 19 | Prefix labeled “Path” while model/TOML use `prefix` ↔ `workspacesRoot` | done |
| 20 | Opening workspace Settings/Secrets force-selects that workspace | done |
| 21 | Search always prominent on panes where it doesn’t match content (e.g. Secret Store) | done |

## Low

| # | Finding | Status |
|---|---------|--------|
| 22 | Low-contrast captions + raw TOML path footers | done |
| 23 | Secret Store quirks — Groups copy, `KEY`/`value` casing (chrome aligned in Batch 2 polish) | done |
| 24 | Unused `secrets` env on Settings root | done |
| 25 | Docs still mention `config.json`; no prefs/TOML unit tests | done |
| 26 | `SettingsNavigation.openSettings()` unused | done |

---

## Batches

- **Batch 1** (#1–12): TOML comment parse + Settings UI/IA polish. Stop for verify.
- **Batch 1 polish** (verify feedback): ⌘, from terminal; input focus shift; Reset only on real change; sidebar search spacing.
- **Batch 2** (#13–15): behavior / deep-links.
- **Batch 2 polish — Supacode chrome** (2026-07-25): page title → section → multi-row cards; label+description|control rows; `DirectoryPathField`; Leader `KeyChordField`; Commands + **Secret Store** on same chrome; custom Settings `Window` with traffic lights in sidebar; elevated sidebar color; **no Settings search**; main sidebar **not collapsible**. Also closed #16 (selection is `.tag` only) and #19 (Prefix label).
- **Batch 3** (#17–18, #20, #22–25): remaining medium / low. Closed between batches: #16, #19, #21.

### Batch 3 notes

- **#17:** Command Center groups — Open Settings / Dismiss → `App`; Toggle Status Cue → `View`. Domain “Effective Setting” kept (resolver term, not a Settings page).
- **#18:** Empty Global Leader restores default `ctrl+p` on autosave.
- **#20:** Workspace **Settings** loads/saves by id without changing Main selection. (**Secret Store** force-select removed later in L3.)

## Later (out of Settings batches)

Expanded 2026-07-25 after Settings audit closed. **All shipped 2026-07-25** (order L2 → L1 A+B → L3 → L1 C).

### L1 — Agent → Worktree rename — done

| Phase | Status |
|-------|--------|
| **A** Glossary merge Agent → Worktree; Remove Worktree | done |
| **B** Command ids `worktree.*` + `commandBindings` migration | done |
| **C** Domain types `WorktreeController` / `WorktreeSummary` / `Domain/Worktree/` | done |

ADRs keep historical `Agent*` names. “coding agent” (CLI tool) unchanged.

### L2 — Command shortcut vs alias UX — done

Bare letters always filter; shortcuts are recorded chords (⌃/⌥/⌘); Settings uses Record; defaults `ctrl+…`; legacy bare prefs migrate.

### L3 — Secret Store without force-selecting Main — done

DataDir-scoped editor; spawn controller stays current-bound and reloads when editing current; sidebar Secrets/Settings open without pre-select.

## Batch 1 acceptance

- Global sidebar: topic pages (e.g. General + Commands), not one row per field; no Effective Setting nav item.
- No awkward centered sidebar toggle (or hidden).
- Fields clearly editable; captions under labels, not fake values in the field.
- No Save / Reload / Reset Global footer; changes auto-persist (scoped: Global edits → prefs only; Workspace edits → that workspace only).
- Commands: Shortcut label doesn’t wrap as “Short-cut”.
- `key = "value" # comment` parses successfully.
