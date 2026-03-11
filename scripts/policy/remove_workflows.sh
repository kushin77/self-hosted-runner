#!/usr/bin/env bash
set -euo pipefail

# Finds any .github/workflows directories and moves them to archived_workflows/
ROOT_DIR="$(cd "$(dirname "$0")/../../" && pwd)"
ARCHIVE_DIR="$ROOT_DIR/archived_workflows/$(date -u +%Y-%m-%d_%H%M%SZ)"

echo "Searching for .github/workflows directories under $ROOT_DIR"
found=0
while IFS= read -r -d '' wf; do
  found=1
  dest="$ARCHIVE_DIR/${wf#$ROOT_DIR/}"
  mkdir -p "$(dirname "$dest")"
  echo "Archiving $wf -> $dest"
  mv "$wf" "$dest"
done < <(find "$ROOT_DIR" -type d -path "*/.github/workflows" -print0)

if [ "$found" -eq 0 ]; then
  echo "No .github/workflows directories found."
else
  echo "Archived workflows to $ARCHIVE_DIR"
  echo "Commit the archive with: git add -A && git commit -m 'chore(policy): archive GitHub workflows'"
fi

exit 0
