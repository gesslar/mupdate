#!/usr/bin/env bash
set -e

TEST_PKG_NAME="MupdateTestPackage"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_PKG_DIR="$TEST_DIR/$TEST_PKG_NAME"
SERVE_DIR="$TEST_DIR/serve"

# shellcheck source=patch-updater.bash
source "$TEST_DIR/patch-updater.bash"

# Prepare serve directory
rm -rf "$SERVE_DIR"
mkdir -p "$SERVE_DIR"

# Patch Updater.lua to point at localhost
patch_updater "$TEST_PKG_NAME"

# Build new version (5.0.0) — this is what the server will serve
cp -vf "$TEST_DIR/mfile_new_version" "$TEST_PKG_DIR/mfile"
pnpx @gesslar/muddy "$TEST_PKG_DIR"

# Read built package name from muddy output
PACKAGE_NAME=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$TEST_PKG_DIR/.output','utf8')).name)")

# Stage files for the HTTP server
cp -vf "$TEST_PKG_DIR/build/$PACKAGE_NAME.mpackage" "$SERVE_DIR/"
echo "5.0.0" > "$SERVE_DIR/${PACKAGE_NAME}_version.txt"
cp -vf "$TEST_DIR/../Mupdate.lua" "$SERVE_DIR/"

echo
echo "Staged in $SERVE_DIR:"
ls -1 "$SERVE_DIR"
echo

# Build old version (0.0.1) — install this in Mudlet
cp -vf "$TEST_DIR/mfile_original" "$TEST_PKG_DIR/mfile"
pnpx @gesslar/muddy "$TEST_PKG_DIR"

echo
echo "============================================"
echo "  Test ready!"
echo "============================================"
echo
echo "v0.0.1 package: $TEST_PKG_DIR/build/$PACKAGE_NAME.mpackage"
echo "Starting HTTP server on port 18089..."
echo

node "$TEST_DIR/serve.js"
