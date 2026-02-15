#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COPIER_DIR="$SCRIPT_DIR/Copier"
SERVE_DIR="$SCRIPT_DIR/serve"

# Clean up serve directory
rm -rf "$SERVE_DIR"
mkdir -p "$SERVE_DIR"

# Derive test Updater from the real Updater.lua by swapping URLs to localhost
sed -e 's|https://github.com/gesslar/Mupdate/releases/latest/download/Mupdate.lua|http://localhost:18089/Mupdate.lua|' \
    -e 's|https://github.com/gesslar/__PKGNAME__/releases/latest/download/|http://localhost:18089/|' \
    -e '/paramKey/d' \
    -e '/paramRegex/d' \
    "$PROJECT_DIR/Updater.lua" > "$COPIER_DIR/src/scripts/Copier/Updater.lua"
echo "Patched Updater.lua -> localhost URLs"

# Build new version (5.0.0) - this is what the server will serve
cp -vf "$COPIER_DIR/mfile_new_version" "$COPIER_DIR/mfile"
pnpx @gesslar/muddy "$COPIER_DIR"

# Read package name from .output
PACKAGE_NAME=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$COPIER_DIR/.output','utf8')).name)")

# Stage new version for serving
cp -vf "$COPIER_DIR/build/$PACKAGE_NAME.mpackage" "$SERVE_DIR/"
echo "5.0.0" > "$SERVE_DIR/${PACKAGE_NAME}_version.txt"
cp -vf "$PROJECT_DIR/Mupdate.lua" "$SERVE_DIR/"

echo
echo "New version files staged in $SERVE_DIR:"
ls -la "$SERVE_DIR"
echo

# Build old version (0.0.1) - this is what you install in Mudlet
cp -vf "$COPIER_DIR/mfile_original" "$COPIER_DIR/mfile"
pnpx @gesslar/muddy "$COPIER_DIR"

echo
echo "============================================"
echo "  Test ready!"
echo "============================================"
echo
echo "Install this package in Mudlet (v0.0.1):"
echo "  $COPIER_DIR/build/$PACKAGE_NAME.mpackage"
echo
echo "Starting HTTP server on port 18089..."
echo

node "$SCRIPT_DIR/serve.js"
