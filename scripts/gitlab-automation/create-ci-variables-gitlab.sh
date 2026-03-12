#!/usr/bin/env bash
set -euo pipefail

# Usage: export GITLAB_TOKEN and PROJECT_ID (or CI_PROJECT_ID), then run
# ./create-ci-variables-gitlab.sh

API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"
PROJECT_ID="${PROJECT_ID:-${CI_PROJECT_ID:-}}"
TOKEN="${GITLAB_TOKEN:-}"

if [ -z "$PROJECT_ID" ] || [ -z "$TOKEN" ]; then
  echo "Usage: set PROJECT_ID (or CI_PROJECT_ID) and GITLAB_TOKEN before running"
  exit 1
fi

declare -A vars
vars["GITLAB_TOKEN"]="$TOKEN"
vars["ASSIGNEE_USERNAME"]="${ASSIGNEE_USERNAME:-akushnir}"
vars["SKIP_ISSUE_TEST"]="true"
vars["GITLAB_API_URL"]="${GITLAB_API_URL:-https://gitlab.com/api/v4}"

echo "Creating/updating CI variables for project $PROJECT_ID..."
for key in "${!vars[@]}"; do
  value="${vars[$key]}"
  # Check if variable exists
  exists=$(curl -sSL -H "PRIVATE-TOKEN: $TOKEN" "$API_URL/projects/$PROJECT_ID/variables/$key" | jq -r '.key // empty' 2>/dev/null || true)
  if [ -n "$exists" ]; then
    echo "  ✓ Updating variable: $key"
    curl -sSL -X PUT -H "PRIVATE-TOKEN: $TOKEN" -H "Content-Type: application/json" \
      "$API_URL/projects/$PROJECT_ID/variables/$key" -d "{\"value\": \"$value\", \"protected\": false, \"masked\": false}" >/dev/null || true
  else
    echo "  + Creating variable: $key"
    curl -sSL -X POST -H "PRIVATE-TOKEN: $TOKEN" -H "Content-Type: application/json" \
      "$API_URL/projects/$PROJECT_ID/variables" -d "{\"key\": \"$key\", \"value\": \"$value\", \"protected\": false, \"masked\": false}" >/dev/null || true
  fi
done

echo "Done."
