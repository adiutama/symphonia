#!/usr/bin/env bash
# Shared CFBundleVersion for Stable + Nightly releases.
#
# Sparkle compares this number (not the marketing version) to decide whether an
# update is newer. Both channels must climb the same ladder so a Nightly install
# can later receive a Stable update (and vice versa).
#
# Format: UTC YYYYMMDDHHMMSS — always increases with wall clock; rebuilds of
# either channel after an older build will sort correctly.
set -euo pipefail
date -u +%Y%m%d%H%M%S
