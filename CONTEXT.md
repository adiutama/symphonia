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
The foreground terminal running the coding-agent command the Operator steers. Resolved as Workspace override if set, otherwise the Operator-wide default.
_Avoid_: Agent terminal, primary shell, coding shell

**Background CLI**:
A secondary terminal on the same Worktree for long-running or ancillary processes (servers, watchers, scripts) — not the coding agent itself. A Worktree may have many; each is easy to create. Shown by peeking an Overlay; hide keeps the process alive. Operator-facing create Command title is **Overlay Terminal**.
_Avoid_: Side terminal, aux shell, job

**Overlay Terminal**:
The Command / action that creates (or peeks) a Background CLI Overlay — freeform command, empty = shell.
_Avoid_: Background (as the Command title), New Background

**Editor**:
A terminal editor (e.g. vim, nano) running in an Overlay on the Worktree — not a peer of the Main CLI. Same peek/hide rules as Background CLIs; quitting the editor is explicit. Operator-facing open Command title is **Open Editor**.
_Avoid_: IDE, pane, split (when meaning the overlay editor)

**Overlay**:
A full-focus layer over the Worktree’s Main CLI — used for the Editor and for Background CLIs. Only one Overlay is visible at a time; a switcher jumps between live ones. **Toggle Overlay** and **Switch Worktree** show or hide without destroying the process — Overlay PTYs are as durable as Main CLI until the Operator **Close Overlay**s, the owning Worktree / Workspace is removed, or the app quits. Editor Overlays are high-attention; Background Overlays are lighter — same mechanics, different UI weight. You *peek* an Overlay (verb); Overlay is the product noun.
_Avoid_: Modal, popup, window, split pane, Peek (as a product noun), Hide Overlay (as the primary Command — use Toggle Overlay)

**Overlay Switcher**:
The Command / nest that lists live Editor and Background Overlays so the Operator can jump to one.
_Avoid_: Peek Overlay (as the Command title), Background picker

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
A short Symphonia-owned input layer after the Leader (Raycast-like). Keys route to Commands, not the focused PTY, until it dismisses. Some Swift types still use the older name `CommandMode*` (implementation only).
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

