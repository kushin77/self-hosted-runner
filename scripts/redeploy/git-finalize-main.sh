#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMMIT_MSG="${1:-chore(redeploy): 100X redeploy governance and enforcement}"
DELETE_BRANCH="${DELETE_BRANCH:-true}"

cd "$ROOT_DIR"

current_branch="$(git branch --show-current)"

if [[ "$current_branch" == "main" ]]; then
  echo "[git-finalize] Already on main. Staging and committing current changes."
  git add -f config/redeploy/redeploy.env.example
  git add docs/redeploy/GO_LIVE_HEAD_TO_TOE_REVIEW.md scripts/redeploy scripts/nas-integration/nas-gcp-archive-backup.sh
  if git diff --cached --quiet; then
    echo "[git-finalize] Nothing staged."
    exit 0
  fi
  git commit -m "$COMMIT_MSG"
  git push origin main
  echo "[git-finalize] Pushed to main."
  exit 0
fi

feature_branch="$current_branch"
echo "[git-finalize] Finalizing feature branch $feature_branch"

git add -A
git commit -m "$COMMIT_MSG"
git push -u origin "$feature_branch"

git checkout main
git pull --ff-only origin main
git merge --no-ff "$feature_branch" -m "merge($feature_branch): $COMMIT_MSG"
git push origin main

if [[ "$DELETE_BRANCH" == "true" ]]; then
  git branch -d "$feature_branch" || true
  git push origin --delete "$feature_branch" || true
  echo "[git-finalize] Deleted feature branch: $feature_branch"
fi

echo "[git-finalize] Merge/push flow completed."
