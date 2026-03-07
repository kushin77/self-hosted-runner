#!/usr/bin/env bash
set -euo pipefail

# Polls runner-self-heal workflow runs and acts when a remediation run completes.
# - Fetches latest run for runner-self-heal.yml
# - If completed and not the known '403 due to missing secrets' failure, posts logs
#   to Issue #947 and attempts to close secret-request issues (#953, #961) when
#   remediation appears to have been performed.

SLEEP=60
LOGDIR=/tmp/self-heal-watcher-logs
mkdir -p "$LOGDIR"

echo "[watcher] starting: polling every ${SLEEP}s"
while true; do
  item=$(gh run list --workflow=runner-self-heal.yml --limit 1 --json databaseId,status,conclusion 2>/dev/null | jq -r '.[0] // empty' 2>/dev/null || true)
  if [ -z "$item" ] || [ "$item" = "null" ]; then
    sleep $SLEEP
    continue
  fi

  status=$(echo "$item" | jq -r '.status // empty')
  id=$(echo "$item" | jq -r '.databaseId // empty')
  conc=$(echo "$item" | jq -r '.conclusion // empty')

  if [ "$status" = "completed" ]; then
    logfile="$LOGDIR/runner-self-heal-$id.log"
    gh run view "$id" --log > "$logfile" || true

    if grep -q "Failed to retrieve runners list via API" "$logfile"; then
      echo "[watcher] run $id shows API failure (likely missing RUNNER_MGMT_TOKEN). Will continue polling."
      sleep $SLEEP
      continue
    fi

    # Post the log (trim to 30000 chars to avoid giant comments)
    log_excerpt=$(sed -n '1,1500p' "$logfile" | sed 's/\x00//g')
    body="Automated: 
Runner-self-heal workflow run: $id
Conclusion: $conc

Log excerpt:


$log_excerpt
\n\n(Full logs archived on runner when available.)"

    gh issue comment 947 --body "$body" || true

    # Heuristic: if logs contain indicators of remediation, close secret issues
    if grep -Eiq "Ansible|restarted|Restarting|remediat|restart|playbook" "$logfile"; then
      gh issue comment 953 --body "Automation: remediation appears to have been performed in run $id, closing this request." || true
      gh issue close 953 || true
      gh issue comment 961 --body "Automation: remediation appears to have been performed in run $id, closing this request." || true
      gh issue close 961 || true
    else
      gh issue comment 953 --body "Automation: runner-self-heal run $id completed but did not indicate remediation; please review the logs attached to Issue #947." || true
    fi

    echo "[watcher] processed run $id; exiting watcher."
    exit 0
  fi

  sleep $SLEEP
done
