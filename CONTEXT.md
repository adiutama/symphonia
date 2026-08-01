# Symphonia

A solo-developer desktop app for managing local coding agents. Terminal fidelity comes from libghostty; Symphonia owns Worktree lifecycle, workspaces, and keyboard-driven control.

## Language

### People

**Operator**:
The single person running Symphonia on their machine.
_Avoid_: User, team member, account

### Hierarchy

**Workspace**:
The Operator’s named project unit in Symphonia. Identified by a renameable **slug**. Has one Main Repo inside its Workspace Data Dir (app clone/init or CLI clone into `main/`). Owns the Secret Store and Worktrees. No multi-clone Workspaces.
_Avoid_: Project, repo (when meaning the Symphonia unit), folder, clone

**Slug**:
The Operator-picked, renameable name for a Workspace; also the default folder name under `~/.symphonia/workspaces/<slug>/`.
_Avoid_: id hash, path hash, repo folder name (when they diverge)

**Workspaces Root**:
The global default parent for Workspace containers (default `~/.symphonia/workspaces`). Only one global root is active at a time; it is configurable.
_Avoid_: Symphonia home (when meaning only the workspaces parent), per-Workspace path

**Prefix**:
The parent directory used for a given Workspace’s container. Defaults to the Workspaces Root; a Workspace may override Prefix so that project lives under a different parent. Only the Prefix changes — layout inside `<prefix>/<slug>/` stays the same.
_Avoid_: Slug, mount, root (when meaning the per-project parent)

**Workspace Data Dir**:
The self-contained directory `<prefix>/<slug>/` holding config, Secret Store file(s), `main/`, and Worktree checkouts together as **flat siblings** (P1.5 — no `worktrees/` parent folder). Never split across locations.
_Avoid_: Repo root alone, project folder (when meaning Symphonia state)

**Main Repo**:
The primary git directory for a Workspace at `<workspace-data-dir>/main/` — a **protected** sibling of Worktrees, always inside the Workspace Data Dir. Cannot be removed or archived. May be populated by the app or by a CLI clone into that path; healed (re-clone or `git init`) on open if missing or not a git repo.
_Avoid_: Worktree, external checkout outside the Workspace Data Dir

**Worktree**:
A `git worktree` checkout linked to the Main Repo, plus its managed Symphonia context (focused Main CLI, optional Background CLIs, Editor overlays). Location: `<workspace-data-dir>/<three-word-name>/` — a sibling of `main/`. The folder name stays put if the checked-out branch changes. The name `main` is reserved and refused.
_Avoid_: Project folder, clone, workspace (when meaning the git checkout); Agent (product noun — use Worktree)

**Three-Word Name**:
The auto-generated **folder** name for a new Worktree: three random lowercase words joined by hyphens (e.g. `blue-frog-knight`). Stable on-disk identity; collision-checked. Default **starting branch** uses the same string; folder and branch need not stay matched.
_Avoid_: UUID, timestamp slug, hash name

**Base Ref**:
The git ref new Worktree branches are created from. An Effective Setting (Workspace overrides global); typically `main` or `develop`.
_Avoid_: Default branch (when meaning the setting), trunk

### Terminals

**Main CLI**:
The foreground terminal running the coding-agent command the Operator steers. Resolved as Workspace override if set, otherwise the Operator-wide default. Home context — not listed as an Activity in Glance.
_Avoid_: Agent terminal, primary shell, coding shell

**Activity**:
A craft surface Symphonia opened for the focused Main Repo or Worktree — shell, editor, file manager, and later peers. Tracked so the Operator can Open, Focus, and End it.
_Avoid_: Overlay (when meaning any opened tool), tab, window, session (when meaning one craft surface)

**Activity Manager**:
The system that opens, focuses, and ends Activities — whether hosted internally or externally. Mini launcher + process/app inventory for the current Worktree context.
_Avoid_: Overlay manager, task manager, dock, app switcher (when meaning Symphonia’s inventory)

**Glance**:
The floating Activity Manager UI — compact session card (e.g. Changes, Shells, Editors, Files). Lists Activities Symphonia opened or adopted; not a project About panel.
_Avoid_: Overlay list, sidebar, inspector, HUD chip (as the product noun)

**Presentation**:
How an Activity is hosted: **Overlay** (internal) or **External** (outside Symphonia). Chosen when configuring the tool (TUI command vs GUI app), not guessed only from a basename list.
_Avoid_: Mode, backend, target (when meaning host kind)

**Overlay**:
A Presentation state: the Activity runs in a peekable PTY over Main CLI. Only one Overlay is visible at a time; **Toggle Overlay** / Switch Workspace / Switch Worktree **hide** without killing; **End** (Close Overlay) tears the PTY down. Overlay PTYs are as durable as Main CLI until End, owner removal, or app quit.
_Avoid_: Modal, popup, window, split pane, Peek (as a product noun), Hide Overlay (as the primary Command — use Toggle Overlay); Activity Manager (Overlay is not the manager)

**External**:
A Presentation state: the Activity runs outside Symphonia (typically a GUI app). Open launches or reuses the app (e.g. already-running Cursor); Focus activates it; End quits/terminates with care — no peek/hide.
_Avoid_: Overlay, native (when meaning macOS host), GUI-only (External is the Presentation name)

**Background CLI**:
A secondary shell Activity on the same Worktree for long-running or ancillary processes (servers, watchers, scripts) — not the coding agent itself. Usually Overlay Presentation; Operator-facing create title remains **Overlay Terminal** until Commands are renamed.
_Avoid_: Side terminal, aux shell, job

**Overlay Terminal**:
The Command / action that creates (or peeks) a shell Activity as an Overlay — freeform command, empty = shell.
_Avoid_: Background (as the Command title), New Background

**Editor**:
The configured editor Activity for the Worktree — TUI (Overlay, e.g. vim/helix) or GUI (External, e.g. Cursor). Full peek/hide Glance experience is Overlay; External is an escape hatch with Focus/Open/End only. Operator-facing open title is **Open Editor**.
_Avoid_: IDE, pane, split (when meaning Symphonia’s editor Activity)

**Overlay Switcher**:
The Command / nest that lists live Overlay Activities so the Operator can jump to one. Distinct from Glance (broader Activity inventory including External).
_Avoid_: Peek Overlay (as the Command title), Background picker, Activity Switcher (until renamed deliberately)

### Secrets

**Secret Store**:
The Workspace-scoped manager of Env Vars (Postman-like). Replaces per-Worktree `.env` copy and external tools like mise/direnv for Worktree CLIs. Values are injected into CLI processes by Symphonia — not written into Worktree checkouts. Stored as plaintext in the Workspace data dir with tight permissions.
_Avoid_: .env file, vault, mise, direnv (as the product mechanism)

**Env Var**:
A single named key/value in the Secret Store (e.g. `DATABASE_URL`).
_Avoid_: Secret (when meaning one key), config

**Secret Group**:
A named subset of Env Vars that can be enabled or disabled together.
_Avoid_: Profile, preset, bundle

**Enabled**:
Whether an Env Var or Secret Group is injected into Worktree CLI environments. Toggle = available in the CLI or not. The Enabled set is applied when a CLI **starts**; changing toggles does not rewrite a running shell.
_Avoid_: Active, on, visible, revealed

### Control

**Leader**:
The key that enters Command Center. Default is `⌘⇧P` (VS Code / Cursor Command Palette convention); configurable.
_Avoid_: Hotkey soup, global chord (when meaning the prefix)

**Command Center**:
A short Symphonia-owned input layer after the Leader (Raycast-like). Keys route to Commands, not the focused PTY, until it dismisses.
_Avoid_: Modal editing, vim mode (when meaning the app layer), Command Mode (preferred product term is Command Center)

**Command**:
A first-class app action with a stable id, exported by an app area. Invoked from Command Center.
_Avoid_: Slash command (as the action itself — slash is only alias text)

**Command Alias**:
Free-text match string(s) for a Command in Input mode. Slash is optional. Multiple aliases are comma-separated. **Defaults are empty**; the Operator may add aliases in Settings.
_Avoid_: Slash verb (as a separate system), stock `/editor`-style defaults

**Command Sequence**:
Normal-mode chord (min 2 letters; `j`/`k` reserved) that runs a Command. Hottest Commands use doubles (`ww`, `tt`, `ee`, …); others prefer object + action. Defaults ship with the Command; Operator may override in Settings. Full list: `docs/keymap.md`; rationale: ADR 0022.
_Avoid_: Shortcut (when meaning Normal-mode letters), title-initial auto-derive (superseded)

**Command Shortcut**:
Optional recorded chord (ctrl/opt/cmd required) for a Command — global or Command Center–scoped per ADR 0022. Distinct from Leader and from Command Sequence.
_Avoid_: Hotkey (when meaning sequence letters); empty-filter bare key (removed)

**Switch** (Workspace / Worktree):
The Operator verb for changing the current Workspace or Worktree among peers (picker or cycle). Worktree cycle includes Main.
_Avoid_: Focus (when meaning Switch Workspace / Switch Worktree), Select (as the Command title)

**Focus Main**:
The Operator verb for jumping to the Workspace’s reserved Main session (home). Not used for peer Workspace/Worktree changes.
_Avoid_: Switch Main, Goto Main (as the preferred title)

### Configuration

**Global Setting**:
An Operator-wide app default (e.g. Workspaces Root, default Main CLI command, default Leader).
_Avoid_: System setting, user preference (when meaning Symphonia globals)

**Workspace Setting**:
A per-Workspace override stored in that Workspace’s config. When set, it wins over the Global Setting for that Workspace.
_Avoid_: Project config (as a competing term), local setting

**Effective Setting**:
The value Symphonia actually uses: Workspace Setting if present, otherwise Global Setting.
_Avoid_: Merged config, resolved config (as glossary terms)

**Remove Worktree**:
The Operator action that tears down a Worktree. Confirms first; by default removes the Worktree (folder + git worktree registration) and keeps the git branch. May optionally delete the branch or archive.
_Avoid_: Delete agent, Remove Agent (legacy), destroy, kill

