#!/usr/bin/env bash
set -euo pipefail

# Remove any tracked `.venv` directories by untracking them and committing the removal.
# Safe to run locally; it will only operate on paths currently tracked by git.

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git repository."
  exit 1
fi

echo "Searching for tracked .venv directories..."
mapfile -t tracked < <(git ls-files | grep '\.venv' || true)

if [ ${#tracked[@]} -eq 0 ]; then
  echo "No tracked .venv entries found. Nothing to remove."
  exit 0
fi

echo "Found ${#tracked[@]} tracked entries. Removing from index and committing." 
for f in "${tracked[@]}"; do
  echo "Removing: $f"
  git rm -r --cached --ignore-unmatch "$f"
done

git commit -m "chore: remove committed .venv directories and ensure .gitignore (#2831)"
echo "Committed removal. Please push the branch and open a PR to finalize." 

exit 0
