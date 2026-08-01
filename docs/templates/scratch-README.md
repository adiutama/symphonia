# Scratch (`.scratch/`)

Gitignored. Machine-local working area. Do not commit.

## Use for

- Task map (`tasks.md`)
- Runbook (`runbook.md`)
- Session notes (`progress.md`)
- Spike notes (`spikes/`)
- Temporary agent files
- Machine-local tooling / keys (e.g. Sparkle)

## Keep in the shared repo instead

- ADRs, CHANGELOG, CONTEXT, vision, keymap, and other public docs

## Bootstrap

```bash
mkdir -p .scratch/spikes
cp docs/templates/scratch-README.md .scratch/README.md
cp docs/templates/progress.md .scratch/progress.md
```

Optional: keep a local `tasks.md` / `runbook.md` here. Do not add those under `docs/`.
