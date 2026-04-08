#!/usr/bin/env bash
# Derives a test Updater.lua from the real one by swapping GitHub URLs to localhost
# and removing param_key/param_regex (not needed for direct local serving).
#
# Usage: source patch-updater.bash

set -e

PATCH_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_PROJECT_DIR="$(dirname "$PATCH_TEST_DIR")"

patch_updater() {
  local test_pkg_name="$1"
  local dest="$PATCH_TEST_DIR/$test_pkg_name/src/scripts/Updater.lua"

  sed -e 's|https://github.com/gesslar/Mupdate/releases/latest/download/Mupdate.lua|http://localhost:18089/Mupdate.lua|' \
      -e 's|https://github.com/gesslar/__PKGNAME__/releases/latest/download/|http://localhost:18089/|' \
      -e '/param_key/d' \
      -e '/param_regex/d' \
      "$PATCH_PROJECT_DIR/Updater.lua" > "$dest"

  echo "Patched Updater.lua -> localhost URLs"
}
