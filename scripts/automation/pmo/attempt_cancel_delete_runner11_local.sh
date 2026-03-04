#!/usr/bin/env bash
set -euo pipefail
ORG="elevatediq-ai"
RUNNER_ID=11
LOG="scripts/pmo/logs/cancel_runner11_local.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
echo "=== Local Cancel+Delete Runner Script started: $(date -u) ==="

# Discover runner name (best-effort)
runner_info=$(gh api /orgs/$ORG/actions/runners/$RUNNER_ID 2>/dev/null || true)
RUNNER_NAME=$(printf '%s' "$runner_info" | jq -r '.name // empty' 2>/dev/null || true)
echo "Target runner id=$RUNNER_ID name='$RUNNER_NAME'"

ATTEMPTS=8
for attempt in $(seq 1 $ATTEMPTS); do
  echo "\n--- Attempt $attempt / $ATTEMPTS ---"
  cancelled=0
  echo "Fetching repos..."
  repos=$(gh api --paginate /orgs/$ORG/repos --jq '.[].name' 2>/dev/null || true)
  if [ -z "$repos" ]; then
    echo "No repos fetched; aborting attempt"
  fi
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    echo "Checking repo: $repo"
    # Fetch recent runs (include in_progress and recent completed)
    run_ids=$(gh api --paginate /repos/$ORG/$repo/actions/runs --jq '.workflow_runs[]? | .id' 2>/dev/null || true)
    if [ -z "$run_ids" ]; then
      echo " No runs found in $repo"
      continue
    fi
    while IFS= read -r run; do
      [ -z "$run" ] && continue
      echo "  Inspecting run $run"
      jobs_json=$(gh api /repos/$ORG/$repo/actions/runs/$run/jobs 2>/dev/null || true)
      # Find jobs that are in_progress OR assigned to our runner id/name
      job_ids=$(printf '%s' "$jobs_json" | jq -r --arg rid "$RUNNER_ID" --arg rname "$RUNNER_NAME" '.jobs[]? | select(.status=="in_progress" or (.runner_id == ($rid|tonumber) ) or (.runner_name== $rname)) | .id' 2>/dev/null || true)
      if [ -z "$job_ids" ]; then
        echo "   No matching jobs in run $run"
        continue
      fi
      while IFS= read -r jid; do
        [ -z "$jid" ] && continue
        echo "   Cancelling job $jid in $repo (run $run)"
        if gh api -X POST /repos/$ORG/$repo/actions/jobs/$jid/cancel >/dev/null 2>&1; then
          echo "    -> cancelled job $jid"
          cancelled=$((cancelled+1))
          continue
        else
          echo "    -> failed to cancel job $jid; attempting to cancel entire run $run"
        fi
        # Fallback: cancel entire run
        if gh api -X POST /repos/$ORG/$repo/actions/runs/$run/cancel >/dev/null 2>&1; then
          echo "    -> cancelled run $run"
        else
          echo "    -> failed to cancel run $run"
        fi
      done <<< "$job_ids"
    done <<< "$run_ids"
  done <<< "$repos"
  echo "Total cancelled this attempt: $cancelled"
  echo "Attempting delete of runner $RUNNER_ID"
  if gh api -X DELETE /orgs/$ORG/actions/runners/$RUNNER_ID >/dev/null 2>&1; then
    echo "Runner $RUNNER_ID deleted"
    # close local log marker
    echo "=== Runner deleted at: $(date -u) ==="
    exit 0
  else
    echo "Runner $RUNNER_ID still blocked; checking status"
    gh api /orgs/$ORG/actions/runners/$RUNNER_ID --jq '{id: .id, name: .name, status: .status, busy: .busy}' || true
  fi
  sleep 5
done
echo "Exhausted attempts; runner still blocked"
exit 2
