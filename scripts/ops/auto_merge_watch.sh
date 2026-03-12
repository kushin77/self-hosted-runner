#!/usr/bin/env bash
# Simple auto-merge watcher for Day-3 PRs
# Usage: GH_TOKEN=ghp_... bash scripts/ops/auto_merge_watch.sh
# Exits with non-zero if token missing or API errors.

set -euo pipefail
REPO_OWNER="kushin77"
REPO_NAME="self-hosted-runner"
PRS=(2709 2716 2718 2720 2723)

if [ -z "${GH_TOKEN:-}" ]; then
  echo "ERROR: GH_TOKEN not set. Export GH_TOKEN with a token with repo scope."
  exit 2
fi

for PR in "${PRS[@]}"; do
  echo "Checking PR #$PR..."
  REVIEWS=$(curl -s -H "Authorization: token $GH_TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/pulls/$PR/reviews")
  # Count approvals
  APPROVALS=$(echo "$REVIEWS" | jq -r '[.[] | select(.state=="APPROVED") | .user.login] | unique | length')
  echo "  Approvals: $APPROVALS"
  if [ "$APPROVALS" -ge 1 ]; then
    echo "  Attempting merge for PR #$PR..."
    RESP=$(curl -s -X PUT -H "Authorization: token $GH_TOKEN" -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/pulls/$PR/merge" -d '{"merge_method":"merge"}')
    MSG=$(echo "$RESP" | jq -r '.message // empty')
    if [ -n "$MSG" ]; then
      echo "  Merge response: $MSG"
    else
      echo "  PR #$PR merged successfully."
    fi
  else
    echo "  PR #$PR not ready to merge."
  fi
done

echo "Done."