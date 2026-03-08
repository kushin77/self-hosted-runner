#!/usr/bin/env bash
set -euo pipefail

# Helper: trigger the Deploy Alertmanager workflow if SLACK_WEBHOOK_URL is present
if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
  echo "SLACK_WEBHOOK_URL not set in environment. Will not dispatch workflow."
  exit 1
fi

WORKFLOW_FILE="deploy-alertmanager.yml"
REPO="${GITHUB_REPOSITORY:-kushin77/self-hosted-runner}"

echo "Dispatching workflow ${WORKFLOW_FILE} for ${REPO}"
gh workflow run "${WORKFLOW_FILE}" --repo "$REPO"
echo "Dispatched. Use 'gh run list --repo ${REPO}' to monitor."
