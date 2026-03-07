#!/usr/bin/env bash
set -euo pipefail

# prepare-filter-repo.sh
# Helper to run git-filter-repo to remove sensitive tokens/paths from history.
# Usage: ./prepare-filter-repo.sh [--dry-run]

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
fi

if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "ERROR: git-filter-repo not found. Install with: pip install git-filter-repo" >&2
  exit 2
fi

# Patterns to remove (customize as needed)
PATTERNS=(
  'ghp_'                                   # GitHub PAT-like tokens
  'GITHUB_TOKEN'                           # explicit token variable in commits
  'YOUR_TOKEN'                             # placeholder token
)

printf "Will run git-filter-repo with the following patterns:\n"
for p in "${PATTERNS[@]}"; do printf " - %s\n" "$p"; done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Running dry-run: printing refs/objects that would be removed."
  # git-filter-repo doesn't have a built-in dry-run; use --analyze to preview
  git-filter-repo --analyze --paths-glob "**" || true
  echo "Dry-run complete. Review .git/filter-repo/analysis/ for details." 
  exit 0
fi

echo "Rewriting history now. This is destructive; ensure backups and approvals."

# Build the --invert-paths or --replace-text options as necessary. Here we replace tokens with [REDACTED_SECRET]
TMPREPL=$(mktemp)
for p in "${PATTERNS[@]}"; do
  # replace any occurrence in blobs
  echo "regex:${p} => [REDACTED_SECRET]" >> "$TMPREPL"
done

git-filter-repo --replace-text "$TMPREPL"

echo "History rewrite complete. Verify locally, then push with: git push --all --force && git push --tags --force"
