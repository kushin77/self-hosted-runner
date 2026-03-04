#!/usr/bin/env bash
set -euo pipefail

# migrate-workflows-to-org-runner.sh
# Replace non-org-hosted 'runs-on' values with the org-runner label set.
# Backs up original files to .backups/workflows

WORKDIR="$(pwd)"
BACKUP_DIR="$WORKDIR/.backups/workflows"
LABEL_SET='[self-hosted, Linux, X64, fullstack]'

mkdir -p "$BACKUP_DIR"

echo "Backing up workflows to $BACKUP_DIR"
find .github/workflows -type f -name '*.yml' -o -name '*.yaml' | while read -r f; do
  cp "$f" "$BACKUP_DIR/$(basename "$f").bak"
done

echo "Patching workflows to use: $LABEL_SET"

# Replace common hosted runners with label set
grep -R --line-number "runs-on:" .github/workflows || true

for f in $(find .github/workflows -type f -name '*.yml' -o -name '*.yaml'); do
  # Only change runs-on lines that do not already reference self-hosted
  if grep -q "runs-on:.*self-hosted" "$f"; then
    echo "Skipping (already self-hosted): $f"
    continue
  fi
  # Replace ubuntu-latest / ubuntu-22.04 / ubuntu-20.04 with label set
  sed -E \
    -e "s/runs-on:\s*ubuntu-latest/runs-on: $LABEL_SET/" \
    -e "s/runs-on:\s*ubuntu-[0-9.]+/runs-on: $LABEL_SET/" \
    -e "s/runs-on:\s*\[?\s*ubuntu-[^\]]*\]?/runs-on: $LABEL_SET/" \
    -i "$f" || true
done

echo "Done. Review changes and commit when ready. Backups in $BACKUP_DIR"

echo "If you want to revert, run: for b in $BACKUP_DIR/*.bak; do mv "$b" ".github/workflows/$(basename ${b%.bak})"; done"
