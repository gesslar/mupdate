#!/usr/bin/env bash
set -e

TEST_PKG_NAME="MupdateTestPackage"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_PKG_DIR="$TEST_DIR/$TEST_PKG_NAME"

# shellcheck source=patch-updater.bash
source "$TEST_DIR/patch-updater.bash"

# Patch Updater.lua to point at localhost
patch_updater "$TEST_PKG_NAME"

# Build old version (0.0.1) — Mudlet watcher will auto-reinstall
cp -vf "$TEST_DIR/mfile_original" "$TEST_PKG_DIR/mfile"
pnpx @gesslar/muddy "$TEST_PKG_DIR"

echo
echo "Reset to v0.0.1. Mudlet watcher should pick up the rebuild."
