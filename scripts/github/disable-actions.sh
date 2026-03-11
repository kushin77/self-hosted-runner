#!/usr/bin/env bash
set -euo pipefail

# Disable GitHub Actions for the repository via API
# Usage: GITHUB_TOKEN=<token> ./scripts/github/disable-actions.sh

OWNER="kushin77"
REPO="self-hosted-runner"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Error: GITHUB_TOKEN environment variable is not set"
  exit 2
fi

API_URL="https://api.github.com/repos/${OWNER}/${REPO}/actions/permissions"

echo "Disabling Actions for ${OWNER}/${REPO} via API..."
curl -sS -X PUT \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "${API_URL}" \
  -d '{"enabled":false,"allowed_actions":"none"}' \
  | jq . >/dev/stderr || true

echo "Done. Verify repository Actions settings in the UI." 
