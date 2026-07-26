# Changelog

All notable changes to Symphonia are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/) while on **0.x** (public MVP).

Release Please updates this file when you merge a Release PR. See [docs/release.md](docs/release.md).

## [Unreleased]

## [0.1.0] - 2026-07-26

Initial public MVP (early access). Build from source is first-class; Release DMGs are unsigned.

### Added

- Workspace and Worktree lifecycle with flat Main / Worktree layout
- Main CLI on GhosttyKit; Editor and Background Overlay terminals
- Overlay Switcher; Toggle Overlay and Switch Worktree keep Overlay PTYs alive until Close
- Workspace Secret Store (TOML) with spawn-time injection
- Command Center (Leader `⌘⇧P`), sequences, recorded chords, live keymap cheatsheet
- Global and Workspace Settings (Effective Setting resolution)
