#!/usr/bin/env bash
set -euo pipefail

# Usage: PROJECT_ID and GITLAB_TOKEN required.
# Example: PROJECT_ID=123 GITLAB_TOKEN=tok ./create-schedule-gitlab.sh "SLA Monitor" "0 */4 * * *" main

API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"
PROJECT_ID="${PROJECT_ID:-${CI_PROJECT_ID:-}}"
TOKEN="${GITLAB_TOKEN:-}"

if [ -z "$PROJECT_ID" ] || [ -z "$TOKEN" ]; then
  echo "Usage: set PROJECT_ID (or CI_PROJECT_ID) and GITLAB_TOKEN, then provide (description, cron, ref) args"
  echo "Example: ./create-schedule-gitlab.sh 'SLA Monitor' '0 */4 * * *' main"
  exit 1
fi

DESCRIPTION="${1:-SLA Monitor}"
CRON="${2:-0 */4 * * *}"
REF="${3:-main}"

payload=$(jq -n --arg d "$DESCRIPTION" --arg r "$REF" --arg c "$CRON" '{description:$d, ref:$r, cron:$c, cron_timezone:"UTC"}')

echo "Creating pipeline schedule: $DESCRIPTION ($CRON) -> $REF"
res=$(curl -sSL -X POST -H "PRIVATE-TOKEN: $TOKEN" -H "Content-Type: application/json" \
  "$API_URL/projects/$PROJECT_ID/pipeline_schedules" -d "$payload")

if echo "$res" | jq -e '.id' >/dev/null 2>&1; then
  echo "  ✓ Created schedule id: $(echo "$res" | jq -r .id)"
else
  echo "  ✗ Failed to create schedule. Response: $res"
fi
