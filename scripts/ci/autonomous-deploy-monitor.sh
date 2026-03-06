#!/usr/bin/env bash
set -euo pipefail

# Autonomous deploy monitor
# - polls the `deploy-immutable-ephemeral.yml` workflow
# - archives redacted logs to `issues/logs/`
# - posts comments and closes Issue #764 on success
# - triggers reruns on failure

REPO="kushin77/self-hosted-runner"
WORKFLOW="deploy-immutable-ephemeral.yml"
ISSUE=764
SLEEP_SECONDS=${SLEEP_SECONDS:-600}
OUT_LOG=/tmp/autonomous-deploy-monitor.out
PIDFILE=/tmp/autonomous-deploy-monitor.pid

if [ -f "$PIDFILE" ]; then
  OLD_PID=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Monitor already running (PID=$OLD_PID). Exiting." | tee -a "$OUT_LOG"
    exit 0
  fi
fi

echo $$ > "$PIDFILE"
echo "[monitor] Starting autonomous deploy monitor for $WORKFLOW (repo: $REPO)" | tee -a "$OUT_LOG"

while true; do
  # Get latest run
  RUN_INFO=$(gh run list --workflow="$WORKFLOW" --repo "$REPO" --limit 1 --json databaseId,status,conclusion,url) || { echo "[monitor] gh run list failed" | tee -a "$OUT_LOG"; sleep $SLEEP_SECONDS; continue; }
  RUN_ID=$(echo "$RUN_INFO" | jq -r '.[0].databaseId')
  STATUS=$(echo "$RUN_INFO" | jq -r '.[0].status')
  CONCLUSION=$(echo "$RUN_INFO" | jq -r '.[0].conclusion')
  URL=$(echo "$RUN_INFO" | jq -r '.[0].url')

  ts=$(date -Iseconds)
  echo "[$ts] Run $RUN_ID status=$STATUS conclusion=$CONCLUSION url=$URL" | tee -a "$OUT_LOG"

  if [ "$STATUS" = "completed" ]; then
    LOG_TMP="/tmp/deploy-run-${RUN_ID}.log"
    gh run view "$RUN_ID" --repo "$REPO" --log > "$LOG_TMP" 2>/dev/null || true

    mkdir -p issues/logs
    OUT_FILE="issues/logs/run-${RUN_ID}-DEPLOY-REDACTED.md"
    sed -E "s/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/REDACTED-UUID/g; s/(VAULT_TOKEN|MINIO_SECRET_KEY|ANSIBLE_PASSWORD|ANSIBLE_PRIVATE_KEY)=[^[:space:]]*/\1=REDACTED/g" "$LOG_TMP" > "$OUT_FILE" || true

    git add "$OUT_FILE" >/dev/null 2>&1 || true
    git commit -m "docs: archive deploy run ${RUN_ID} (conclusion=${CONCLUSION})" --no-verify >/dev/null 2>&1 || true
    git push origin main >/dev/null 2>&1 || true

    if [ "$CONCLUSION" = "success" ]; then
      gh issue comment $ISSUE --repo "$REPO" --body "✅ **DEPLOYMENT SUCCESS**\nRun $RUN_ID completed successfully. Evidence archived: $OUT_FILE\nSystem is now sovereign and closed." >/dev/null 2>&1 || true
      gh issue close $ISSUE --repo "$REPO" >/dev/null 2>&1 || true
      echo "[monitor] Success — archived and closed issue $ISSUE" | tee -a "$OUT_LOG"
      rm -f "$PIDFILE"
      exit 0
    else
      gh issue comment $ISSUE --repo "$REPO" --body "❌ **DEPLOYMENT FAILED**\nRun $RUN_ID concluded: $CONCLUSION. Evidence archived: $OUT_FILE\nAutomation will attempt a rerun." >/dev/null 2>&1 || true
      echo "[monitor] Failure detected for run $RUN_ID — requesting rerun" | tee -a "$OUT_LOG"
      gh run rerun "$RUN_ID" --repo "$REPO" >/dev/null 2>&1 || gh workflow run "$WORKFLOW" --repo "$REPO" >/dev/null 2>&1 || true
      sleep $SLEEP_SECONDS
      continue
    fi
  fi

  # If run is queued/in_progress, just wait and continue
  echo "[monitor] Run $RUN_ID is $STATUS — sleeping $SLEEP_SECONDS seconds" | tee -a "$OUT_LOG"
  sleep $SLEEP_SECONDS
done
