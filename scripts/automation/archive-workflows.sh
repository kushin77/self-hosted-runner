#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOWS_DIR="$ROOT_DIR/.github/workflows"
ARCHIVE_DIR="$ROOT_DIR/.github/workflows.disabled"

echo "Archiving GitHub Actions workflows..."
mkdir -p "$ARCHIVE_DIR"

# Move files (preserve subdirs)
shopt -s globstar nullglob
for f in "$WORKFLOWS_DIR"/**/*; do
  # Skip the archive folder itself
  if [[ "$f" == "$ARCHIVE_DIR"* ]]; then
    continue
  fi
  if [[ -f "$f" ]]; then
    relpath=${f#"$ROOT_DIR/"}
    target="$ARCHIVE_DIR/${f##*/}"
    echo "Moving $relpath -> .github/workflows.disabled/${f##*/}"
    git mv "$f" "$target" || mv "$f" "$target"
  fi
done

# Also move any top-level workflow files
for f in "$WORKFLOWS_DIR"/*.yml "$WORKFLOWS_DIR"/*.yaml; do
  [[ -e "$f" ]] || continue
  basename=$(basename "$f")
  git mv "$f" "$ARCHIVE_DIR/$basename" || mv "$f" "$ARCHIVE_DIR/$basename"
done

echo "Creating commit: chore: archive GitHub Actions workflows"
git add -A
git commit -m "chore: archive GitHub Actions workflows — migrated to direct-deploy model" || echo "No changes to commit"

echo "Workflows archived to .github/workflows.disabled/"
echo "Next: disable Actions in repository Settings → Actions → General (admin required)"
