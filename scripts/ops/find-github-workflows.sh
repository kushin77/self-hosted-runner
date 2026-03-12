#!/usr/bin/env bash
set -euo pipefail

# Lists GitHub Actions workflow files in the repository
# Usage: ./scripts/ops/find-github-workflows.sh

echo "Searching for .github/workflows files..."

if [ -d ".github/workflows" ]; then
  find .github/workflows -type f -maxdepth 2 || true
else
  echo "No .github/workflows directory found." >&2
fi

# Also check archived_workflows folders
if find archived_workflows -maxdepth 4 -type f | grep -q .; then
  echo
  echo "Found archived_workflows entries:" 
  find archived_workflows -type f -maxdepth 6 || true
fi

echo
echo "Done."