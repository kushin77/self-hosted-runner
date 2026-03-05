#!/usr/bin/env bash
set -euo pipefail

# Watch Issue for an approval comment and dispatch the apply workflow automatically.
# Usage: ./auto-apply-on-approval.sh [issue_number] [poll_interval_seconds]

REPO="kushin77/self-hosted-runner"
ISSUE=${1:-246}
POLL=${2:-15}
LAST_FILE="/tmp/auto-apply-last-comment-id"
LOG="/tmp/auto-apply.log"

echo "Auto-apply monitor starting for issue $ISSUE (repo: $REPO)" >> "$LOG"

last_seen=0
if [ -f "$LAST_FILE" ]; then
  last_seen=$(cat "$LAST_FILE" || echo 0)
fi

while true; do
  comments=$(gh api repos/$REPO/issues/$ISSUE/comments 2>/dev/null || true)
  if [ -z "$comments" ] || [ "$comments" = "null" ]; then
    sleep "$POLL"
    continue
  fi

  # Get last comment id and body
  last_comment_id=$(echo "$comments" | jq -r '.[-1].id // 0')
  last_comment_body=$(echo "$comments" | jq -r '.[-1].body // ""')

  if [ "$last_comment_id" -gt "$last_seen" ]; then
    echo "Detected new comment id=$last_comment_id" >> "$LOG"
    # Check for approval tokens
    if echo "$last_comment_body" | grep -qi "\bplan approved\b\|✅ plan approved\|✅ Plan approved"; then
      echo "Approval detected in comment id=$last_comment_id; dispatching apply workflow" >> "$LOG"
      gh workflow run terraform-plan-apply.yml --repo "$REPO" --ref main -f auto_apply=true >> "$LOG" 2>&1 || true
      gh issue comment "$ISSUE" --body "Auto-apply dispatched after approval comment (id: $last_comment_id)." >> "$LOG" 2>&1 || true
      echo "$last_comment_id" > "$LAST_FILE"
      break
    fi
    echo "$last_comment_id" > "$LAST_FILE"
    last_seen=$last_comment_id
  fi

  sleep "$POLL"
done

echo "Auto-apply monitor exiting" >> "$LOG"
