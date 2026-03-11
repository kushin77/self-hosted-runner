#!/usr/bin/env bash
set -euo pipefail
# Remove all GitHub Actions workflow files except the sentinel and archive them
REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"
ARCHIVE_DIR="$REPO_ROOT/archived_workflows/$(date -u +%Y-%m-%d_%H%M%SZ)"
mkdir -p "$ARCHIVE_DIR"
echo "Disabling GitHub Actions: archiving workflows to $ARCHIVE_DIR"
shopt -s nullglob
for f in "$WORKFLOWS_DIR"/*; do
  base=$(basename "$f")
  if [[ "$base" == "disable-workflows.yml" ]]; then
    echo "Keeping sentinel: $base"
    continue
  fi
  echo "Archiving: $base"
  mkdir -p "$ARCHIVE_DIR/.github/workflows"
  mv "$f" "$ARCHIVE_DIR/.github/workflows/"
done

echo "Staging archive changes and removing original workflow entries from git index"
git add -A "$ARCHIVE_DIR"
git rm -r --ignore-unmatch .github/workflows/* || true
git add .github/workflows/disable-workflows.yml
git commit -m "chore(enforce): disable GitHub Actions workflows (archive)" || true
echo "GitHub Actions disabled and archived."
exit 0
