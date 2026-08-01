# Changelog

All notable changes to Symphonia are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/) while on **0.x** (public MVP).

Release Please updates this file when you merge a Release PR. See [docs/release.md](docs/release.md).

## [Unreleased]

## [0.1.0] - 2026-08-01

Initial public MVP (early access). Build from source is first-class; Release DMGs are unsigned unless Apple signing secrets are set.

### Added

- Workspace and Worktree lifecycle with flat Main / Worktree layout
- Main CLI on GhosttyKit; Editor and Background Overlay terminals
- Activity Manager (Glance): Open / Focus / End for Overlay and External craft surfaces; live Changes
- Tools settings and onboarding for Editor / Files Presentation (Overlay vs External)
- Overlay Switcher; Toggle Overlay and Switch Worktree keep Overlay PTYs alive until Close
- Workspace Secret Store (TOML) with spawn-time injection
- Command Center (Leader `⌘⇧P`), sequences, recorded chords, live keymap cheatsheet
- Global and Workspace Settings (Effective Setting resolution)
- About window (version, license, Ghostty credit) from the App menu
- Short first-launch onboarding sheet
- Sparkle 2 in-app updates (Check for Updates…); Stable and Nightly channels; EdDSA appcast when configured
- Nightly GitHub pre-release DMG workflow
- App icon and macOS 26 Liquid Glass chrome

### Fixed

- Main CLI / Overlay PTY exit handling with crash-loop guard and Reload CLI
- Sparkle loading in ad-hoc (unsigned) Release builds
- Terminal spawn wrapping, Ghostty theme sync, and display scale resync
