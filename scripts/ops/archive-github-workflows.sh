#!/usr/bin/env bash
set -euo pipefail

# Archive GitHub Actions workflows into archived_workflows/<timestamp>/
# This script performs git mv operations; run locally and push the branch.
# Usage: ./scripts/ops/archive-github-workflows.sh

TS=$(date -u +%Y-%m-%d_%H%M%SZ)
DEST="archived_workflows/${TS}"

mkdir -p "$DEST/.github/workflows"

if [ -d ".github/workflows" ] && [ "$(ls -A .github/workflows)" ]; then
  echo "Archiving .github/workflows to $DEST/.github/workflows"
  git mv .github/workflows/* "$DEST/.github/workflows/" || true
  # create placeholder to prevent accidental re-enable
  mkdir -p .github/workflows
  echo "# workflows archived to $DEST" > .github/workflows/README.md
  git add "$DEST" .github/workflows/README.md
  echo "Archival changes staged. Commit and push the branch to create a PR."
else
  echo "No workflows to archive." >&2
fi

# List archived files
echo "Archived files under $DEST:"
ls -R "$DEST" || true
