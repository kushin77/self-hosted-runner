#!/usr/bin/env bash
# Poll the handoff issues and run verification for any posted logs.
# This script is safe to run manually or from a background service.
# It tracks last-processed comment IDs in /tmp to avoid reprocessing.

set -euo pipefail

REPO="kushin77/self-hosted-runner"
ISSUES=(2310 2311)
WORKDIR="/tmp/handoff-verify"
mkdir -p "$WORKDIR"

for ISSUE in "${ISSUES[@]}"; do
  echo "Checking issue #$ISSUE"
  # Get comments (id + body) as JSON
  COMMENTS_JSON=$(gh issue view "$ISSUE" --repo "$REPO" --json comments --jq '.comments') || {
    echo "Failed to fetch comments for issue #$ISSUE" >&2; continue
  }

  # Iterate comments (we'll use jq if available)
  if command -v jq >/dev/null 2>&1; then
    echo "$COMMENTS_JSON" | jq -c '.[]' | while read -r c; do
      CID=$(echo "$c" | jq -r '.id')
      BODY=$(echo "$c" | jq -r '.body')
      LASTFILE="$WORKDIR/last_comment_$ISSUE"
      if [ -f "$LASTFILE" ] && [ "$(cat "$LASTFILE")" = "$CID" ]; then
        # already processed up to this comment id; continue
        continue
      fi
      # Search for attached log text or markers; if found, save and verify
      if echo "$BODY" | grep -Ei "/tmp/deploy-orchestrator|go-live-finalize|DEPLOY_COMPLETE|Terraform applied|BEGIN LOG" >/dev/null; then
        OUTFILE="$WORKDIR/issue_${ISSUE}_comment_${CID}.log"
        echo "$BODY" > "$OUTFILE"
        echo "Saved log from comment $CID to $OUTFILE"
        /home/akushnir/self-hosted-runner/scripts/orchestration/verify-handoff.sh "$ISSUE" "$OUTFILE" || true
      fi
      # update last processed id
      echo "$CID" > "$LASTFILE"
    done
  else
    # Fallback: crude parsing to find the last comment that looks like a log
    echo "$COMMENTS_JSON" | grep -Eo '"body": "[^"]{20,}' | sed -E 's/^"body": "//' | while read -r BODY; do
      if echo "$BODY" | grep -Ei "deploy-orchestrator|go-live-finalize|Terraform applied|DEPLOY_COMPLETE" >/dev/null; then
        OUTFILE="$WORKDIR/issue_${ISSUE}_manual_$(date +%s).log"
        echo "$BODY" > "$OUTFILE"
        /home/akushnir/self-hosted-runner/scripts/orchestration/verify-handoff.sh "$ISSUE" "$OUTFILE" || true
      fi
    done
  fi
done

echo "Poll complete."
