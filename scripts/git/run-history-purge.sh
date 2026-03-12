#!/usr/bin/env bash
set -euo pipefail

# Guarded history purge using git-filter-repo.
# Usage:
#   export MAINTENANCE_CONFIRM=yes
#   export REPO_REMOTE=origin
#   ./scripts/git/run-history-purge.sh reports/paths-to-remove.txt
# The script requires `git-filter-repo` installed and a confirmed maintenance window.

if [ "${MAINTENANCE_CONFIRM:-}" != "yes" ]; then
  echo "MAINTENANCE_CONFIRM not set to 'yes' - aborting. Set env MAINTENANCE_CONFIRM=yes to proceed."
  exit 1
fi

PATHS_FILE="$1"
if [ ! -f "$PATHS_FILE" ]; then
  echo "Paths file missing: $PATHS_FILE"
  exit 2
fi

if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "git-filter-repo not found in PATH. Install it first: https://github.com/newren/git-filter-repo"
  exit 3
fi

echo "Preparing to rewrite history. This will create a backup refs/heads/original-*"
echo "Paths to remove:"
cat "$PATHS_FILE"

read -p "Proceed with history rewrite and force-push to remote? (type 'proceed' to continue): " CONFIRM
if [ "$CONFIRM" != "proceed" ]; then
  echo "User aborted."
  exit 4
fi

TMP_ARGS=""
while IFS= read -r p; do
  [ -z "$p" ] && continue
  TMP_ARGS="$TMP_ARGS --path \"$p\""
done < "$PATHS_FILE"

echo "Running git-filter-repo..."
# shellcheck disable=SC2086
git-filter-repo --invert-paths --paths-from-file "$PATHS_FILE"

echo "Rewrite complete. Review refs/original/* and verify the repository locally before force-push."
echo "To force-push all refs: git push --force --all ${REPO_REMOTE:-origin} && git push --force --tags ${REPO_REMOTE:-origin}"

exit 0
