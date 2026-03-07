#!/usr/bin/env bash
set -euo pipefail

REPO="kushin77/self-hosted-runner"
LOG="/tmp/auto_remediate_monitor.log"
INTERVAL=${MONITOR_INTERVAL:-60}

echo "Starting auto-remediation monitor (interval=${INTERVAL}s)" | tee -a "$LOG"

while true; do
  echo "---- $(date -u +%Y-%m-%dT%H:%M:%SZ) ----" | tee -a "$LOG"

  # Find candidate PRs
  prs=$(gh pr list --state open --repo "$REPO" --limit 200 --json number,headRefName --jq '.[] | select(.headRefName | test("hotfix/deps/alert-|dependabot")) | .number' 2>/dev/null || true)

  if [ -z "$prs" ]; then
    echo "No candidate PRs found" | tee -a "$LOG"
  else
    echo "Found PRs: $prs" | tee -a "$LOG"
    echo "$prs" | while read -r pr; do
      if [ -z "$pr" ]; then continue; fi
      echo "Checking PR #$pr" | tee -a "$LOG"

      # Get mergeability and status checks
      info=$(gh pr view "$pr" --repo "$REPO" --json number,mergeable,mergeStateStatus,statusCheckRollup 2>/dev/null || echo "{}")

      mergeable=$(echo "$info" | jq -r '.mergeable // empty') || mergeable=""
      mergeState=$(echo "$info" | jq -r '.mergeStateStatus // empty') || mergeState=""

      # Collect status check conclusions (only completed checks)
      conclusions=$(echo "$info" | jq -r '.statusCheckRollup[]? | select(.status=="COMPLETED") | .conclusion' 2>/dev/null || true)

      all_success=true
      if [ -z "$conclusions" ]; then
        all_success=false
      else
        for c in $conclusions; do
          if [ "$c" != "SUCCESS" ]; then all_success=false; break; fi
        done
      fi

      echo "mergeable=$mergeable mergeState=$mergeState all_success=$all_success" | tee -a "$LOG"

      if [ "$mergeState" = "MERGEABLE" ] || [ "$mergeState" = "CLEAN" ]; then
        if [ "$all_success" = true ]; then
          echo "Merging PR #$pr (checks green)" | tee -a "$LOG"
          gh pr merge "$pr" --repo "$REPO" --squash --delete-branch -m "chore: auto-merge hotfix PR #$pr (auto-remediation)" || echo "Merge failed for #$pr" | tee -a "$LOG"
        else
          echo "PR #$pr not ready: checks not all successful" | tee -a "$LOG"
        fi
      else
        echo "PR #$pr not mergeable (state=$mergeState)" | tee -a "$LOG"
      fi
    done
  fi

  sleep "$INTERVAL"
done
