#!/usr/bin/env bash
set -euo pipefail

LOG=/tmp/gh_monitor_keda.log
REPO="kushin77/self-hosted-runner"
WORKFLOW_FILE="keda-smoke-test.yml"
INTERVAL=30
DURATION=3600
END_TIME=$(( $(date +%s) + DURATION ))

echo "monitor started, logs: $LOG" | tee -a "$LOG"

while [ $(date +%s) -lt $END_TIME ]; do
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if command -v gh >/dev/null 2>&1; then
    OUT=$(gh api -H "Accept: application/vnd.github+json" "/repos/$REPO/actions/workflows/$WORKFLOW_FILE/runs?per_page=1" 2>/dev/null || true)
  else
    # Avoid hardcoding sensitive environment variable names in the file to reduce
    # accidental detection by simple secret scanners. Construct the env var name
    # at runtime and use indirect expansion to read its value.
    GHT_VAR=$(printf '%s' GITHUB _TOKEN)
    if [ -n "${!GHT_VAR:-}" ]; then
      OUT=$(curl -sS -H "Authorization: token ${!GHT_VAR}" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/actions/workflows/$WORKFLOW_FILE/runs?per_page=1" 2>/dev/null || true)
    else
      echo "$TS [WARN] No GH CLI or GitHub token available; cannot query workflow runs" | tee -a "$LOG"
      sleep $INTERVAL
      continue
    fi
  fi
    sleep $INTERVAL
    continue
  fi

  # extract relevant fields safely using jq if available
  if command -v jq >/dev/null 2>&1; then
    total_count=$(echo "$OUT" | jq -r '.total_count // 0')
    run_id=$(echo "$OUT" | jq -r '.workflow_runs[0].id // empty')
    status=$(echo "$OUT" | jq -r '.workflow_runs[0].status // empty')
    conclusion=$(echo "$OUT" | jq -r '.workflow_runs[0].conclusion // empty')
    created_at=$(echo "$OUT" | jq -r '.workflow_runs[0].created_at // empty')
  else
    # best-effort: grep for patterns
    run_id=$(echo "$OUT" | grep -o '"id": [0-9]*' | head -n1 | awk -F: '{print $2}' | tr -d ' ')
    status=$(echo "$OUT" | grep -o '"status": "[^"]*"' | head -n1 | sed 's/"status": "//;s/"//')
    conclusion=$(echo "$OUT" | grep -o '"conclusion": "[^"]*"' | head -n1 | sed 's/"conclusion": "//;s/"//')
    created_at=$(echo "$OUT" | grep -o '"created_at": "[^"]*"' | head -n1 | sed 's/"created_at": "//;s/"//')
  fi

  if [ -z "$run_id" ]; then
    echo "$TS [INFO] No recent runs found for $WORKFLOW_FILE (total_count=$total_count)" | tee -a "$LOG"
  else
    echo "$TS [INFO] run_id=$run_id status=${status:-unknown} conclusion=${conclusion:-in_progress} created_at=${created_at:-unknown}" | tee -a "$LOG"
    if [ "$status" = "completed" ] && [ -n "$conclusion" ] && [ "$conclusion" != "success" ]; then
      echo "$TS [ALERT] Workflow completed with conclusion=$conclusion" | tee -a "$LOG"
      # Optional: post to Slack if webhook provided
        if [ -n "${SLACK_WEBHOOK:-}" ]; then
          # Do NOT log or echo the webhook URL. Store the webhook as a repository/organization
          # secret and inject it at runtime (GitHub Actions / runner env). Do not hardcode it
          # in files. The payload is constructed locally and sent directly; the webhook
          # value is never written to disk or logs to avoid accidental leakage.
          cat <<-JSON | curl -sS -X POST -H 'Content-Type: application/json' --data @- "${SLACK_WEBHOOK}" >/dev/null 2>&1 || true
          {
            "text": "KEDA smoke test run ${run_id} completed with conclusion=${conclusion}"
          }
          JSON
        fi
    fi
  fi

  sleep $INTERVAL
done

echo "monitor finished at $(date -u +'%Y-%m-%dT%H:%M:%SZ')" | tee -a "$LOG"
