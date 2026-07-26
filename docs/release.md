# Shipping Symphonia

Plain-English guide to versions, builds, and GitHub Releases. Product language lives in [`CONTEXT.md`](../CONTEXT.md).

## Open source

- Symphonia is **MIT** ([`LICENSE`](../LICENSE)).
- Ghostty / libghostty stays under **its** MIT license; we only ship our app code + a pinned GhosttyKit build recipe.

## How people get the app

1. **Preferred:** clone and build (see root [`README.md`](../README.md)).
2. **Optional:** download `Symphonia-<version>.zip` from GitHub **Releases**.

Release zips are **unsigned** (no paid Apple Developer ID). macOS may show a warning. That is expected for this open-source MVP. Tell downloaders: Right‑click the app → **Open**, or build from source.

## Check ≠ ship

| What | When | Version bump? | Download? |
|------|------|---------------|-----------|
| Everyday check (CI) | Every PR / push to `main` | No | No |
| Ship (release) | You merge the **Release PR** | Yes | Yes (zip on GitHub Releases) |

You press one button (merge the Release PR). Automation then picks the version, updates the changelog, tags, builds, and uploads.

## Version numbers (0.x MVP)

| Kind of commit since last tag | New version example |
|-------------------------------|---------------------|
| `fix:` (and similar patches) | `0.1.0` → `0.1.1` |
| `feat:` | `0.1.0` → `0.2.0` |
| Breaking (`!` / `BREAKING CHANGE`) | Middle number up while still on 0.x |
| `docs:`, `chore:`, `ci:`, `test:` | No release |

Use Conventional Commits (`feat(scope): …`, `fix: …`, …) — see [`AGENTS.md`](../AGENTS.md).

The app’s marketing version (`MARKETING_VERSION` in Xcode) tracks the Git tag (`v0.1.0`). The Apple **build** number is set at ship time from the GitHub Actions run (you do not bump it by hand).

## First-time: put the repo on GitHub

This project may start with **no** `git remote`. Once:

```bash
# Create an empty public repo on GitHub (no README), then:
git remote add origin git@github.com:YOUR_USER/symphonia.git
git push -u origin main
```

Enable **GitHub Actions** for the repo. After the first push, CI should run.

### Baseline tag for 0.1.0

Release Please needs a starting point. After the shipping machinery is on `main`:

```bash
git tag v0.1.0
git push origin v0.1.0
```

That creates the first GitHub Release (unsigned zip once the release workflow finishes). Later versions come from merging Release PRs only.

## Day to day

1. Commit with `feat` / `fix` / … and merge to `main`.
2. CI compiles (no new version).
3. Release Please opens or updates a **Release PR** (proposed version + changelog + Xcode marketing version).
4. When you want to ship: review that PR → **merge**.
5. Automation tags `vX.Y.Z`, builds, uploads the zip to GitHub Releases.

## Workflows

| File | Role |
|------|------|
| [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) | Compile check on PR / `main` |
| [`.github/workflows/release-please.yml`](../.github/workflows/release-please.yml) | Draft / merge Release PR; create tag |
| [`.github/workflows/release.yml`](../.github/workflows/release.yml) | On `v*` tag: build zip and attach to the Release |

Shared build script: [`scripts/ci-build.sh`](../scripts/ci-build.sh). Zig install helper for CI: [`scripts/install-zig.sh`](../scripts/install-zig.sh).

## What Release zips are today

- **Unsigned** (no Apple Developer ID signing or notarization)
- macOS may warn on open — Right‑click → **Open**, or build from source
- Not distributed via the Mac App Store
