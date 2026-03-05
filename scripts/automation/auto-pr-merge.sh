#!/usr/bin/env bash
set -euo pipefail
# Auto PR mergeer: polls a PR until it becomes mergeable and merges it.
# Usage: ./auto-pr-merge.sh [PR_NUMBER] [POLL_INTERVAL_SECONDS] [MAX_ATTEMPTS]

REPO="kushin77/self-hosted-runner"
PR=${1:-337}
POLL_INTERVAL=${2:-600}
MAX_ATTEMPTS=${3:-6}

for i in $(seq 1 "$MAX_ATTEMPTS"); do
  ts=$(date --iso-8601=seconds)
  echo "$ts: attempt $i checking PR $PR"
  mergeable=$(gh pr view "$PR" --repo "$REPO" --json mergeable --jq '.mergeable' 2>/dev/null || echo "UNKNOWN")
  echo "$ts: mergeable=$mergeable"
  if [ "$mergeable" = "MERGEABLE" ]; then
    echo "$ts: merging PR $PR"
    gh pr merge "$PR" --repo "$REPO" --merge --delete-branch --body "Auto-merged by ops agent when mergeable." && \
      gh issue create --repo "$REPO" --title "PR $PR merged by agent" --body "PR #$PR was merged automatically by the ops agent." --label ops || true
    exit 0
  else
    echo "$ts: PR $PR not mergeable; posting reminder comment"
    gh pr comment "$PR" --repo "$REPO" --body "Automated reminder: PR #$PR needs review before merging. Will auto-merge when mergeable." || true
    exists=$(gh issue list --repo "$REPO" --label ops --label merge --state open --search "PR $PR requires review" --limit 100 --json number 2>/dev/null | jq 'length')
    if [ "$exists" = "0" ]; then
      gh issue create --repo "$REPO" --title "PR $PR requires review before merge" --body "PR #$PR is not mergeable; requesting human review. Linked issue #325 for Ops checklist." --label ops --label merge || true
      echo "$ts: created follow-up issue for PR $PR"
    else
      echo "$ts: follow-up issue already exists for PR $PR"
    fi
  fi
  sleep "$POLL_INTERVAL"
done

echo "Reached max attempts without merging PR $PR" >&2
exit 1
