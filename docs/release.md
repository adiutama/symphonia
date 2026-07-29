# Shipping Symphonia

Plain-English guide to versions, builds, and GitHub Releases. Product language lives in [`CONTEXT.md`](../CONTEXT.md).

## Open source

- Symphonia is **MIT** ([`LICENSE`](../LICENSE)).
- Ghostty / libghostty stays under **its** MIT license; we only ship our app code + a pinned GhosttyKit build recipe.

## How people get the app

1. **Preferred:** clone and build (see root [`README.md`](../README.md)).
2. **Optional:** download `Symphonia-<version>.dmg` from GitHub **Releases**.

Release DMGs are **unsigned by default** (no paid Apple Developer ID). When Apple signing secrets are configured, the release workflow signs and notarizes. Open the disk image and drag Symphonia to Applications. Unsigned builds may show a macOS warning — Right‑click the app → **Open**, or build from source.

## Check ≠ ship

| What | When | Version bump? | Download? |
|------|------|---------------|-----------|
| Everyday check (CI) | Every PR / push to `main` — lint only (fast) | No | No |
| Compile + package | **`v*` tag** (Release workflow) | Already tagged | Yes (DMG) |
| Draft Release PR | **You** run the “Release Please” workflow (Actions → Run workflow) | Only on that draft PR | No |
| Ship | **You** merge the Release PR | Yes (lands on `main` + tag) | Yes (DMG on GitHub Releases) |

Everyday pushes never open a Release PR and never run the full macOS compile. Shipping is intentional: run Release Please → review the PR → merge → tag builds the DMG.

## Version numbers (0.x MVP)

| Kind of commit since last tag | New version example |
|-------------------------------|---------------------|
| `fix:` (and similar patches) | `0.1.0` → `0.1.1` |
| `feat:` | `0.1.0` → `0.2.0` |
| Breaking (`!` / `BREAKING CHANGE`) | Middle number up while still on 0.x |
| `docs:`, `chore:`, `ci:`, `test:` | No release |

Use Conventional Commits (`feat(scope): …`, `fix: …`, …) — see [`AGENTS.md`](../AGENTS.md).

The app’s marketing version (`MARKETING_VERSION` in Xcode) tracks the Git tag (`v0.1.0`). The Apple **build** number (`CFBundleVersion` / `CURRENT_PROJECT_VERSION`) is set at ship time from the GitHub Actions run number. Sparkle uses that build number to detect newer releases — keep it monotonic.

## Sparkle auto-updates

The app embeds [Sparkle](https://sparkle-project.org/) 2.x. Feed URL (in [`App/Info.plist`](../App/Info.plist)):

`https://github.com/adiutama/symphonia/releases/latest/download/appcast.xml`

Each release may attach `appcast.xml` next to the DMG. Operators use **Check for Updates…** in the app menu.

### One-time EdDSA keys (required for signed updates)

Sparkle verifies updates with an EdDSA key pair (separate from Apple code signing):

```bash
./scripts/sparkle-setup-keys.sh
```

That script:

1. Writes the **public** key into `App/Info.plist` (`SUPublicEDKey`) and `App/SUPublicEDKey.txt` — **commit these**.
2. Exports the **private** key to `.local/sparkle/ed-private.key` (gitignored).
3. You add the private key contents as GitHub Actions secret **`SPARKLE_ED_PRIVATE_KEY`**.

Without `SPARKLE_ED_PRIVATE_KEY`, the release workflow still ships the DMG but **skips** the appcast.

### Optional Apple Developer ID + notarization

If these secrets exist, release.yml signs, notarizes, and staples before packaging the DMG:

| Secret | Purpose |
|--------|---------|
| `MACOS_CERTIFICATE` | Base64-encoded Developer ID Application `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the `.p12` |
| `APPLE_API_KEY` | App Store Connect API key (`.p8` contents) |
| `APPLE_API_KEY_ID` | Key id |
| `APPLE_API_ISSUER` | Issuer UUID |

If they are missing, the workflow ships an **unsigned** DMG (current default). EdDSA appcast signing still runs when `SPARKLE_ED_PRIVATE_KEY` is set.

Helpers: [`scripts/install-sparkle.sh`](../scripts/install-sparkle.sh), [`scripts/sparkle-generate-appcast.sh`](../scripts/sparkle-generate-appcast.sh), [`scripts/notarize-app.sh`](../scripts/notarize-app.sh).

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

That creates the first GitHub Release (DMG once the release workflow finishes). Later versions come from merging Release PRs only.

## Day to day

1. Commit with `feat` / `fix` / … and open a PR.
2. CI runs fast lints (`./scripts/lint.sh`) — no full app compile.
3. Merge to `main`.
4. When you want to ship: **Actions → Release Please → Run workflow**.
5. Review the Release PR (version + changelog + Xcode marketing version) → **merge**.
6. Automation tags `vX.Y.Z`, compiles, uploads the DMG (and appcast when EdDSA is configured) to GitHub Releases.

## Workflows

| File | Role |
|------|------|
| [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) | Fast lint on PR / `main` (ShellCheck, actionlint, SwiftLint) |
| [`.github/workflows/release-please.yml`](../.github/workflows/release-please.yml) | Manual: draft Release PR / tag (workflow_dispatch only) |
| [`.github/workflows/release.yml`](../.github/workflows/release.yml) | On `v*` tag: full macOS build, DMG, optional notarize, optional Sparkle appcast |

Local lint: [`scripts/lint.sh`](../scripts/lint.sh). Full compile helper: [`scripts/ci-build.sh`](../scripts/ci-build.sh) (GhosttyKit + Sparkle + Symphonia). Zig: [`scripts/install-zig.sh`](../scripts/install-zig.sh). DMG: [`scripts/package-dmg.sh`](../scripts/package-dmg.sh).

## What Release DMGs are today

- **Unsigned** unless Apple secrets are set (then Developer ID + notarized)
- Open the DMG → drag Symphonia to Applications
- Unsigned: macOS may warn on open — Right‑click → **Open**, or build from source
- Not distributed via the Mac App Store
- In-app updates via Sparkle when appcast + EdDSA keys are configured
