#!/usr/bin/env bash
set -euo pipefail
# Wait for local validation success then auto-merge pipeline-repair PRs
# Usage: ./auto-merge-post-validation.sh [CHECK_INTERVAL_SECONDS] [MAX_ATTEMPTS]
REPO="kushin77/self-hosted-runner"
LOGFILE="/tmp/local-runner-status.log"
CHECK_INTERVAL=${1:-60}
MAX_ATTEMPTS=${2:-360}
PRS=(355 354 339 338)

echo "Auto-merge watcher starting; monitoring $LOGFILE"
for i in $(seq 1 "$MAX_ATTEMPTS"); do
  ts=$(date --iso-8601=seconds)
  if [ -f "$LOGFILE" ]; then
    if grep -q "KEDA Smoke Test PASSED" "$LOGFILE" || grep -q "Phase P4 Execution COMPLETE" "$LOGFILE"; then
      echo "$ts: Validation success detected; processing PRs: ${PRS[*]}"
      for pr in "${PRS[@]}"; do
        mergeable=$(gh pr view "$pr" --repo "$REPO" --json mergeable --jq '.mergeable' 2>/dev/null || echo "UNKNOWN")
        if [ "$mergeable" = "MERGEABLE" ]; then
          echo "$ts: merging PR $pr"
          gh pr merge "$pr" --repo "$REPO" --merge --delete-branch --body "Auto-merged after local validation by self-hosted runner." || echo "merge failed for $pr"
          gh issue create --repo "$REPO" --title "PR $pr merged by self-hosted validation" --body "PR #$pr was auto-merged after local validation." --label ops || true
        else
          echo "$ts: PR $pr not mergeable (status: $mergeable); posting comment"
          gh pr comment "$pr" --repo "$REPO" --body "Automated note: validation passed on self-hosted runner; please review/resolve merge conflicts so this PR can be merged." || true
          exists=$(gh issue list --repo "$REPO" --label ops --label merge --state open --search "PR $pr requires review" --limit 100 --json number 2>/dev/null | jq 'length')
          if [ "$exists" = "0" ]; then
            gh issue create --repo "$REPO" --title "PR $pr requires review before merge" --body "PR #$pr is not mergeable post-validation; please resolve and merge." --label ops --label merge || true
          fi
        fi
      done
      echo "$ts: Auto-merge pass complete; exiting watcher"
      exit 0
    fi
  fi
  sleep "$CHECK_INTERVAL"
done

echo "Reached max attempts without detecting validation success" >&2
exit 1
