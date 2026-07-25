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
| 16 | Mixed `.tag` vs `NavigationLink` selection models | open |
| 17 | Naming collision — Settings / Effective Setting / Command Center “Settings” group | open |
| 18 | Leader empty warned but not blocked on save | open |
| 19 | Prefix labeled “Path” while model/TOML use `prefix` ↔ `workspacesRoot` | open |
| 20 | Opening workspace Settings/Secrets force-selects that workspace | open |
| 21 | Search always prominent on panes where it doesn’t match content (e.g. Secret Store) | done |

## Low

| # | Finding | Status |
|---|---------|--------|
| 22 | Low-contrast captions + raw TOML path footers | open |
| 23 | Secret Store quirks — Groups copy, `KEY`/`value` casing, chrome differs | open |
| 24 | Unused `secrets` env on Settings root | open |
| 25 | Docs still mention `config.json`; no prefs/TOML unit tests | open |
| 26 | `SettingsNavigation.openSettings()` unused | done |

---

## Batches

- **Batch 1** (#1–12): TOML comment parse + Settings UI/IA polish. Stop for verify.
- **Batch 1 polish** (verify feedback): ⌘, from terminal; input focus shift; Reset only on real change; sidebar search spacing.
- **Batch 2** (#13–15): behavior / deep-links.
- **Batch 2 polish — Supacode chrome** (2026-07-25): page title → section → multi-row cards; label+description|control rows; `DirectoryPathField`; Leader `KeyChordField`; Commands + **Secret Store** on same chrome; custom Settings `Window` with traffic lights in sidebar; elevated sidebar color; **no Settings search**; main sidebar **not collapsible**.
- **Batch 3** (#16–20, #22–25): medium / low. (#21 closed — Settings search removed.)

## Later (out of Settings batches)

- Rename product/code references from **Agent** → **Worktree** in Commands and other call sites (titles, ids/aliases as needed, UI copy). Do not start until Settings batches finish unless prioritized.
- **Command shortcut vs alias UX:** plain-char shortcuts (e.g. `w`) collide with Command Center search (typing `w` both filters and is a shortcut). Discuss redesign — Raycast’s alias/hotkey recording + filter model is the reference (elegant set flow, clear filter). Not Batch 2/3 unless prioritized.

## Batch 1 acceptance

- Global sidebar: topic pages (e.g. General + Commands), not one row per field; no Effective Setting nav item.
- No awkward centered sidebar toggle (or hidden).
- Fields clearly editable; captions under labels, not fake values in the field.
- No Save / Reload / Reset Global footer; changes auto-persist (scoped: Global edits → prefs only; Workspace edits → that workspace only).
- Commands: Shortcut label doesn’t wrap as “Short-cut”.
- `key = "value" # comment` parses successfully.
