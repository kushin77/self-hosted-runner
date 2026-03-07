#!/usr/bin/env bash
set -euo pipefail

REPO="kushin77/self-hosted-runner"
ISSUE=1239
POLL_INTERVAL=30

log(){ echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

log "Starting ingestion monitor for issue #${ISSUE} (poll ${POLL_INTERVAL}s)"

while true; do
  # Fetch comments bodies
  COMMENTS=$(gh api "/repos/${REPO}/issues/${ISSUE}/comments" --jq '.[].body' 2>/dev/null || true)

  if echo "$COMMENTS" | grep -Fxq "ingested: true"; then
    log "Detected ingestion comment on issue #${ISSUE}"

    # Acknowledge (idempotent): add a comment if not already present
    ACK_EXISTS=$(gh api "/repos/${REPO}/issues/${ISSUE}/comments" --jq '.[] | select(.body=="[monitor] ingestion-detected") | .id' 2>/dev/null || true)
    if [ -z "$ACK_EXISTS" ]; then
      gh issue comment ${ISSUE} --repo ${REPO} --body "[monitor] ingestion-detected" || true
      log "Posted monitor acknowledgement comment"
    else
      log "Acknowledgement comment already present"
    fi

    # List latest runs for targeted workflows and monitor them
    for WF in dr-smoke-test.yml docker-hub-weekly-dr-testing.yml; do
      log "Checking latest run for workflow: $WF"
      RUN_JSON=$(gh run list --repo ${REPO} --workflow $WF --limit 1 --json databaseId,status,conclusion,htmlUrl --jq '.[0]' 2>/dev/null || true)
      if [ -z "$RUN_JSON" ] || [ "$RUN_JSON" = "null" ]; then
        log "No runs found for $WF yet"
        continue
      fi

      RUN_ID=$(echo "$RUN_JSON" | jq -r '.databaseId')
      RUN_URL=$(echo "$RUN_JSON" | jq -r '.htmlUrl')
      log "Found run $RUN_ID for $WF: $RUN_URL"

      # Poll run until conclusion is set
      while true; do
        VIEW=$(gh run view $RUN_ID --repo ${REPO} --json status,conclusion --jq '.' 2>/dev/null || true)
        STATUS=$(echo "$VIEW" | jq -r '.status // empty')
        CONCL=$(echo "$VIEW" | jq -r '.conclusion // empty')

        log "Run $RUN_ID status=$STATUS conclusion=${CONCL:-pending}"

        if [ -n "$CONCL" ] && [ "$CONCL" != "null" ]; then
          log "Run $RUN_ID completed with conclusion: $CONCL"

          # Post summary comment to operator issue
          gh issue comment ${ISSUE} --repo ${REPO} --body "[monitor] Workflow $WF run $RUN_ID completed with conclusion: $CONCL. See: $RUN_URL" || true
          break
        fi

        sleep 10
      done
    done

    log "Monitoring after ingestion complete; will continue polling for new ingestions."
  fi

  sleep $POLL_INTERVAL
done
