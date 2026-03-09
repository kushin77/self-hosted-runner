#!/usr/bin/env bash
set -euo pipefail

# Simple workflow monitor for GitHub Actions to auto-close issues on success.
# Uses `gh` CLI. Runs indefinitely; suitable for systemd service.

REPO="kushin77/self-hosted-runner"
SLEEP_SEC=30

declare -A MAP
# workflow filename -> issue number
MAP["phase3-revoke-keys.yml"]=1950
MAP["7day-monitoring-run.yml"]=1948

log(){ echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

while true; do
  for wf in "${!MAP[@]}"; do
    issue=${MAP[$wf]}
    # get latest run conclusion for workflow
    out=$(gh run list --repo "$REPO" --workflow "$wf" --limit 1 --json conclusion,status -q '.[] | {conclusion:.conclusion,status:.status}' 2>/dev/null || true)
    if [ -z "$out" ]; then
      log "workflow $wf: no runs found"
      continue
    fi
    concl=$(echo "$out" | jq -r '.conclusion')
    status=$(echo "$out" | jq -r '.status')
    log "workflow $wf: status=$status conclusion=$concl"
    if [ "$concl" = "success" ]; then
      # check issue state
      state=$(gh issue view "$issue" --repo "$REPO" --json state -q '.state' 2>/dev/null || echo "")
      if [ "$state" = "OPEN" ]; then
        log "Closing issue #$issue for workflow $wf"
        gh issue close "$issue" --repo "$REPO" || true
        gh issue comment "$issue" --repo "$REPO" -b "Automated: workflow $wf completed successfully; closing issue. Audit logs: logs/*.jsonl" || true
      else
        log "Issue #$issue already state=$state"
      fi
    fi
  done
  sleep "$SLEEP_SEC"
done
