#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPIER_DIR="$SCRIPT_DIR/Copier"

# Derive test Updater from the real Updater.lua by swapping URLs to localhost
sed -e 's|https://github.com/gesslar/Mupdate/releases/latest/download/Mupdate.lua|http://localhost:18089/Mupdate.lua|' \
    -e 's|https://github.com/gesslar/__PKGNAME__/releases/latest/download/|http://localhost:18089/|' \
    -e '/paramKey/d' \
    -e '/paramRegex/d' \
    "$PROJECT_DIR/Updater.lua" > "$COPIER_DIR/src/scripts/Copier/Updater.lua"

# Build old version (0.0.1) - watcher in Mudlet will auto-reinstall
cp -vf "$COPIER_DIR/mfile_original" "$COPIER_DIR/mfile"
pnpx @gesslar/muddy "$COPIER_DIR"

echo
echo "Reset to v0.0.1. Mudlet watcher should pick up the rebuild."
echo
