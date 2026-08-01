# Agent rules

Only put rules here that steer agent behavior and are **not** already stated in the repo. If `CONTEXT.md`, `docs/`, or code already says it, follow that; do not repeat it here.

## Conversation

- Speak in plain English with me.
- For complex topics, use a short analogy when it helps.
- Em dashes (—) are forbidden. Use commas, periods, or parentheses instead.

## Work style

- Stay on the asked task; do not expand scope.
- Temporary files → `.scratch/` (gitignored).
- Commits: Conventional Commits (`type(scope): subject`).

## What to commit

- Commit shared product material: code, `CONTEXT.md`, ADRs, vision, keymap, CHANGELOG, and other public docs.
- Keep local working notes in `.scratch/` (task maps, session notes, private runbooks). Do not commit `.scratch/`.

## Docs

- When editing or researching docs, follow [`docs/AGENTS.md`](docs/AGENTS.md).
