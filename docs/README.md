# Symphonia docs

Product and architecture docs for anyone studying this project: glossary, vision, ADRs, keymap, release.

They matter even more for coding agents. Each new session starts without prior chat memory, so these files are how the project remembers itself.

| Doc | Purpose |
|-----|---------|
| [AGENTS.md](AGENTS.md) | Rules for editing these docs |
| [../CONTEXT.md](../CONTEXT.md) | Ubiquitous language (glossary only) |
| [vision.md](vision.md) | Problem, approach, non-goals |
| [keymap.md](keymap.md) | Operator keybind cheatsheet (globals, CC, sequences) |
| [release.md](release.md) | Versioning, CI vs ship, unsigned GitHub Releases |
| [../CHANGELOG.md](../CHANGELOG.md) | Per-version history |
| [../LICENSE](../LICENSE) | MIT license |
| [adr/README.md](adr/README.md) | ADR index (pick by topic, then open one file) |
| [templates/](templates/) | Blank seeds for gitignored `.scratch/` |

## Scratch (machine-local)

`.scratch/` is **gitignored**: working notes, task maps, session state, temp files, local tooling. See root `AGENTS.md` for what belongs in the shared repo.

Bootstrap once:

```bash
mkdir -p .scratch/spikes
cp docs/templates/scratch-README.md .scratch/README.md
cp docs/templates/progress.md .scratch/progress.md
```

## Feature status

| Question | Source of truth |
|----------|-----------------|
| What did we decide? | [`adr/README.md`](adr/README.md) index → open that ADR |
| What does the word mean? | [`CONTEXT.md`](../CONTEXT.md) |
| Is it built yet? | ADR **Implementation** line (`not started` / `in progress` / `shipped`) |
| What shipped for users? | [`CHANGELOG.md`](../CHANGELOG.md) |
