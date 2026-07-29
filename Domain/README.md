# Domain

Global preferences, Effective Setting resolution, Workspace containers, Worktree lifecycle, and Workspace Secret Store.

## Preferences (Phase 2)

| Type | Role |
|------|------|
| `GlobalPreferences` | Codable Global Setting model for `~/.symphonia/preferences.toml` (T.1) |
| `PreferencesStore` | Load / save TOML; missing file → defaults; no JSON migration |
| `PreferencesToml` | Minimal TOML encode/decode for Global / Workspace / secrets / workspace-index |
| `WorkspaceSettingOverrides` | Optional Workspace Setting (Prefix maps to `workspacesRoot`) |
| `EffectiveSettings` | Resolver: Workspace override wins, else Global Setting |
| `EditorCommandResolver` | Empty Editor → login shell `VISUAL`/`EDITOR` (fallback `vi`); absolutizes bare cmds; GUI vs TUI hint |
| `LoginShellEnvironment` | Probes `$SHELL -lc` for `VISUAL`/`EDITOR`/`PATH` + `command -v`; soft-fails to `nil` |
| `CLISpawnEnvironment` | Locale defaults + login `PATH`; Secret Store overwrites |
| `PreferencesController` | Observable chrome binding |

Defaults: Main CLI empty (bare shell), Editor empty (login shell `VISUAL`/`EDITOR`), Leader `cmd+shift+p`, Workspaces Root `~/.symphonia/workspaces`, Base Ref `main`, `commandBindings` empty (see Command Center below, ADR 0021 CC.3).

## Workspace (Phase 3)

| Type | Role |
|------|------|
| `WorkspaceSlug` | Validate Operator-readable slug (no path separators / `..`); reserved names include `main` |
| `WorkspaceConfig` | Codable `config.toml` (slug, optional Prefix, setting fields, `mainRemoteURL`) |
| `WorkspaceStore` | Create layout, `git init`/`git clone` in `main/`, list, open, heal `main/` on open (P1.5); **rename** slug + move Data Dir |
| `WorkspaceController` | List / create / switch / **rename** / **remove** (disk + index); open/select/refresh heal `main/` |
| `SymphoniaPaths` | `~/.symphonia` paths + Workspace Data Dir helpers; reserved child names |

Layout under `<prefix>/<slug>/` (**flat siblings**, P1.5 — no `worktrees/` parent):

```
config.toml
secrets.toml              # Secret Store (mode 0600) — see below
main/                     # protected: git init/clone on create; healed on open if unhealthy
<three-word>/             # Worktree (Phase 4) — sibling of main/
<another-three-word>/
```

`main` is the one reserved name a Worktree folder can never take (case-insensitive;
`SymphoniaPaths.reservedWorkspaceChildNames`, folded into `WorkspaceSlug.validate`). **No
migration** from the older nested `worktrees/<three-word>/` layout — pre-production Operators
recreate affected Workspaces.

**Heal on open (P1.5):** `WorkspaceStore.open(at:)` calls `healMainIfNeeded(at:config:)` — if
`main/` is missing or not a git repo, it re-clones from `config.mainRemoteURL` when set (P1.4),
else `git init`s it (same as an empty local Workspace); no-op once `main/` is already a valid git
repo. `WorkspaceController.select(_:)` and `.refresh()` both call through `store.open(at:)`, so
opening, selecting, or refreshing a Workspace — including app-startup selection restore — all heal
Main for free.

Known Prefixes + last selection: `~/.symphonia/workspace-index.toml` (T.3). Legacy
`workspace-index.json` is ignored (no migration).

## Worktree (Phase 4)

| Type | Role |
|------|------|
| `FocusedSession` | Main Repo or Worktree — scopes Main CLI + Overlays |
| `MainCLISurfaceSlot` | Opened Main CLI PTY (persists across focus; tear down on remove) |
| `ThreeWordName` | Auto `{word}-{word}-{word}` folder names; collision-checked |
| `WorktreeSummary` | One Worktree ↔ one Worktree folder, sibling of `main/` (+ best-effort branch) |
| `WorktreeStore` | `git worktree add/remove` as siblings of `main/`; branch from Effective Base Ref; refuses reserved names; **rename** branch and/or folder |
| `WorktreeController` | List / create / focus / **rename** / remove; opened Main CLI surfaces |
| `CLISpawnEnvironment` | Default `en_US.UTF-8` locale; Secret Store overrides |

Create: folder = Three-Word Name, a **sibling of `main/`** directly under the Workspace Data Dir
(P1.5 — no `worktrees/` parent); refused when it's the reserved name `main` (case-insensitive,
`SymphoniaPaths.reservedWorkspaceChildNames`). Branch defaults to folder name (optional manual);
start-point = Effective Base Ref (or unborn HEAD on fresh `git init`).

`WorktreeStore.list()` only surfaces sibling folders that are themselves git checkouts (have a
`.git` file/dir) and skips reserved names — so `main/` and any stray non-checkout folder never
show up as Worktrees.

**Main is protected (P1.5):** `WorktreeController.requestRemove(_:)` / `archive(_:)` and
`WorktreeStore.remove(...)` all take an `WorktreeSummary`, which `WorktreeStore.list()` never produces for
`main/` — so Main can't be removed or archived through these APIs structurally, not just because
the UI omits the action. `WorktreeStore.remove()` also refuses a reserved name directly as
defense-in-depth.

Remove: confirm; default **keep** branch; unregister worktree + delete folder; destroy that session’s Main CLI PTY.

**Archive (Phase 6 / P1.3, ADR 0020 spirit — remove still exists; archive is softer):** a Worktree
can be soft-archived instead of removed. Archived state is a list of Three-Word folder names —
`WorkspaceConfig.archivedThreeWordNames: [String]?` in `config.toml` — **not** a folder move or
git operation; the Worktree folder and `git worktree` registration are untouched. `WorktreeController`
filters archived names out of `worktrees` / `worktrees(in:)` (sidebar default list, rail, Command Center
picker) via `WorkspaceController.archivedWorktreeNames(for:)`. `WorktreeController.archivedWorktrees(in:)`
lists archived-only entries (still on disk) for the sidebar Workspace context menu’s “Archived
Worktrees…” sheet, which offers **Unarchive** (`WorktreeController.unarchive(threeWordName:in:)`) —
`WorktreeController.allWorktrees(in:)` is the unfiltered read used by that sheet and by collision checks
in `WorktreeStore`. Archiving the focused Worktree refocuses Main Repo first. No migration: missing
`archivedThreeWordNames` in older `config.toml` (or legacy `config.json`) files decodes as `nil` (treated as empty).

Terminal: one live Main CLI PTY **per opened session** (Main or Worktree). Switching focus **hides** other PTYs (same idea as Overlay hide ≠ quit). Respawn is explicit (secrets refresh). Spawn env always includes English locale defaults unless Secret Store sets `LANG` / `LC_*`.

## Secret Store (Phase 5)

| Type | Role |
|------|------|
| `SecretStoreDocument` / `EnvVar` / `SecretGroup` | Model for `secrets.toml` (Codable still for fixtures) |
| `SecretStore` | Load / save TOML with mode 0600; compute Enabled env set |
| `SecretStoreController` | Observable CRUD + toggles for table/grid UI |

### Storage format (`secrets.toml`, mode 0600)

Plaintext in the Workspace Data Dir only (ADR 0012, T.3). **Never** written into `main/` or a Worktree
checkout (siblings under the Workspace Data Dir, P1.5) — `SecretStore.write` asserts the target
dir isn't itself a git repo. Legacy `secrets.json` is ignored (no migration).

```toml
version = 1

[groups."<uuid>"]
name = "staging"
enabled = true

[vars."<uuid>"]
key = "DATABASE_URL"
value = "postgres://…"
enabled = true
groupId = "<uuid>"

[vars."<uuid>"]
key = "UNGROUPED"
value = "ok"
enabled = false
```

**Enabled injection rule (spawn-time, ADR 0002):** an Env Var is injected when `enabled == true` **and** it is either ungrouped (`groupId` omitted) or its Secret Group is Enabled. Duplicate keys: last declaration wins.

Legacy empty `secrets.env` placeholders from Phase 3 are removed on layout ensure; non-empty legacy files are left alone (no auto-import in v1).

### Spawn injection

When a session is **first opened**, spawn env = English locale defaults (`LANG` / `LC_ALL` / `LC_MESSAGES` = `en_US.UTF-8`) merged with Enabled secrets (secrets win on conflict). Switching focus does **not** respawn. Live Secret Store edits do not rewrite a running shell (ADR 0002); use **Respawn w/ secrets** on the focused session only.

## Command Center (Phase 7 / ADR 0021)

| Type | Role |
|------|------|
| `LeaderKeyBinding` | Parse Effective `leaderKey` (`cmd+shift+p`, `⌘k`, …) and match `NSEvent` |
| `CommandCenterController` | Local keyDown monitor; enter/dismiss; run palette actions |
| `CommandCenterNestCatalog` | Nest picker rows + ephemeral nest sequences |
| `CommandCenterItem` / `CommandCenterAction` | Palette rows / run actions |
| `CommandContext` | Small availability snapshot — `hasFocusedSession`, `overlayVisible` — with a `@MainActor` init from `WorktreeController` + `OverlayController` |
| `Command` | Stable string `id`, title, optional subtitle/group, `defaultSequence`, `isEnabled(CommandContext) -> Bool`, wraps a `CommandCenterAction` |
| `CommandProvider` | Protocol an app area implements to export `[Command]` (ADR 0021) |
| `CommandRegistry` | Aggregates providers; `allCommands`, `availableCommands(context:)`, `command(id:)` |
| `OverlayCommandProvider` | Open Editor (`ee`), Toggle Overlay (`oo`), Overlay Terminal (`ot`), Overlay Switcher (`os`) |
| `WorkspaceCommandProvider` | Switch Workspace / Worktree, Focus Main, New/Discard Worktree / Workspace, … |
| `ChromeCommandProvider` | Settings, Keymap, Dismiss Command Center — no context gating |
| `KeymapBindings` | Fixed global / Command Center–only Hotkeys (ADR 0022); cheatsheet + runtime match |
| `CommandBindingOverride` | Codable Global Setting override for one Command's **sequence**, keyed by Command `id` |
| `CommandBindingResolver` | `sequence(for:overrides:)` — effective Normal-mode sequence = override ?? Command default |

**Leader** (default `cmd+shift+p`, from Effective Setting) enters **Command Center**. While active, the local monitor swallows keyDown so Main CLI / Overlay PTYs do not receive chords. Esc (or Leader again) dismisses and restores terminal first responder.

Root palette rows come from the `CommandRegistry` (ADR 0021 / CC.2). The picker phases (`pickWorkspace` / `pickWorktree` / `pickBackground`) still build their rows directly from live controller data since each row is a dynamic instance (a Workspace, a Worktree, a live Overlay), not a stable Command.

`CommandRegistry` is constructed once in `SymphoniaApp.init()` (providers: Workspace, Overlay, Chrome) and injected into `CommandCenterController`, which drives its root palette entirely from `commandRegistry.availableCommands(context:)`. Filtering matches title and subtitle via case-insensitive substring. An empty filter shows every enabled Command; Normal-mode sequences and `KeymapBindings` Hotkeys fire from the key monitor per ADR 0022.

**Operator overrides (ADR 0021 CC.3 / ADR 0022):** `GlobalPreferences.commandBindings` persists per-Command **sequence** overrides at `~/.symphonia/preferences.toml` under `[commandBindings."<id>"]`. Hotkeys are **not** overridable — they come from `KeymapBindings`. Legacy `aliases` / `shortcut` TOML keys are ignored and stripped on load. Legacy `preferences.json` is ignored.

**Settings UI:** Global → Shortcuts lists Commands (plus Leader) as Name | Sequence | Hotkey. Sequence is editable; Hotkey is read-only from `KeymapBindings` (Leader Hotkey remains editable Global Setting). Conflicts warn on duplicate sequences only.
