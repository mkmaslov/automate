#!/usr/bin/env bash
set -euo pipefail

#------------------------------------------------------------------------------
# This script inserts shared functions into template scripts.
# Input: .sh file in ../src/
# Output: .sh file in ../dist/
# Content between BEGIN_SHARED and END_SHARED tags is replaced with
# the corresponding block of code from ./shared.sh
#------------------------------------------------------------------------------

# Generate paths
PATH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATH_SRC="${PATH_ROOT}/src"
PATH_DIST="${PATH_ROOT}/dist"
PATH_SHARED="${PATH_ROOT}/build/shared.sh"

MARKER_BEGIN='# BEGIN_SHARED'
MARKER_END='# END_SHARED'

replace_shared_block() {
  local FILE_SRC="$1"
  local FILE_DIST="$2"
  awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" \
    -v shared_file="$PATH_SHARED" '
    function print_shared_block(line, in_shared) {
      in_shared = 0
      while ((getline line < shared_file) > 0) {
        if (line == begin) { in_shared = 1; continue }
        if (line == end && in_shared) break
        if (in_shared) print line
      }
      close(shared_file)
    }
    BEGIN { in_block = replaced = 0 }
    $0 == begin && !replaced {
      print_shared_block()
      in_block = replaced = 1
      next
    }
    $0 == end && in_block { in_block = 0; next }
    !in_block
    ' "$FILE_SRC" > "$FILE_DIST"
}

# Clean target directory
rm -rf "$PATH_DIST" && mkdir -p "$PATH_DIST"

find "$PATH_SRC" -type f | while IFS= read -r FILE_SRC; do
  PATH_RELATIVE="${FILE_SRC#"$PATH_SRC"/}"
  FILE_DIST="${PATH_DIST}/${PATH_RELATIVE}"
  mkdir -p "$(dirname "$FILE_DIST")"
  replace_shared_block "$FILE_SRC" "$FILE_DIST"
  chmod +x "$FILE_DIST"
done

#------------------------------------------------------------------------------