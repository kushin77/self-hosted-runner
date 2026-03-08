#!/usr/bin/env bash
# Monitor the secrets-health-multi-layer workflow run and report status
# Usage: ./scripts/monitor-health-run.sh [RUN_ID]

set -euo pipefail

REPO="kushin77/self-hosted-runner"
WORKFLOW_FILE="secrets-health-multi-layer.yml"

usage() {
  echo "Usage: $0 [RUN_ID]"
  echo "If RUN_ID is omitted, the script will locate the most recent run for ${WORKFLOW_FILE}."
}

RUN_ID="${1:-}" 

if [[ "${RUN_ID}" == "" ]]; then
  echo "Finding latest run for workflow ${WORKFLOW_FILE}..."
  api_path="/repos/${REPO}/actions/workflows/${WORKFLOW_FILE}/runs?per_page=1"
  resp=$(gh api -X GET "$api_path")
  RUN_ID=$(echo "$resp" | jq -r '.workflow_runs[0].id')
  if [[ "$RUN_ID" == "null" || -z "$RUN_ID" ]]; then
    echo "No recent runs found for ${WORKFLOW_FILE}."
    exit 2
  fi
fi

echo "Monitoring run: $RUN_ID"

# Stream logs until completion
gh run watch "$RUN_ID" -R "$REPO"

# After completion, fetch final status
conclusion=$(gh run view "$RUN_ID" -R "$REPO" --json conclusion --jq '.conclusion')
html_url=$(gh run view "$RUN_ID" -R "$REPO" --json html_url --jq '.html_url')

echo "Run finished: $html_url"
echo "Conclusion: $conclusion"

if [[ "$conclusion" == "success" ]]; then
  echo "Workflow succeeded. The auto-close workflow will handle issue closure." 
else
  echo "Workflow did not succeed. Posting diagnostic comment to issues 1688/1691/1703."
  body="Automated monitor: health-check run $html_url finished with conclusion '$conclusion'. Please investigate."
  for num in 1688 1691 1703; do
    gh issue comment $num -R "$REPO" -b "$body" || true
  done
fi

exit 0
