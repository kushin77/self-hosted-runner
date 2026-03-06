#!/usr/bin/env bash
set -euo pipefail

# create_dr_schedule.sh
# Idempotently creates a GitLab pipeline schedule for the DR dry-run template.
# Requires: GITLAB_API_URL, PROJECT_ID, GITLAB_API_TOKEN (or will read from GSM via gcloud if SECRET_PROJECT set)

usage(){
  cat <<EOF
Usage: PROJECT_ID=123 GITLAB_API_TOKEN=... ./scripts/ci/create_dr_schedule.sh

Environment:
  GITLAB_API_URL      - GitLab API url (default: https://gitlab.com/api/v4)
  PROJECT_ID          - GitLab project id where schedule will be created
  GITLAB_API_TOKEN    - Personal Access Token or CI token with schedule:create scope
  CRON                - cron schedule (default: 0 3 1 */3 *) == quarterly at 03:00 UTC on day 1
  DESCRIPTION         - schedule description
  SECRET_PROJECT      - optional GCP project name to fetch tokens from GSM
EOF
}

GITLAB_API_URL=${GITLAB_API_URL:-https://gitlab.com/api/v4}
PROJECT_ID=${PROJECT_ID:-}
CRON=${CRON:-"0 3 1 */3 *"}
DESCRIPTION=${DESCRIPTION:-"DR dry-run quarterly schedule"}

if [[ -z "${PROJECT_ID}" ]]; then
  echo "PROJECT_ID is required" >&2
  usage; exit 2
fi

if [[ -z "${GITLAB_API_TOKEN:-}" && -n "${SECRET_PROJECT:-}" ]]; then
  if command -v gcloud >/dev/null 2>&1; then
    GITLAB_API_TOKEN=$(gcloud secrets versions access latest --secret=gitlab-api-token --project=$SECRET_PROJECT || true)
  fi
fi

if [[ -z "${GITLAB_API_TOKEN:-}" ]]; then
  echo "GITLAB_API_TOKEN is required (set env or place in GSM and set SECRET_PROJECT)" >&2
  exit 3
fi

echo "Checking for existing schedule named: ${DESCRIPTION} on project ${PROJECT_ID}"
EXISTING=$(curl -s -H "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" "${GITLAB_API_URL}/projects/${PROJECT_ID}/pipeline_schedules" | jq -r --arg desc "$DESCRIPTION" '.[] | select(.description==$desc) | .id' || true)

if [[ -n "$EXISTING" ]]; then
  echo "Schedule already exists: id=$EXISTING"
  exit 0
fi

echo "Creating schedule... cron='${CRON}'"
RESP=$(curl -s -X POST -H "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" "${GITLAB_API_URL}/projects/${PROJECT_ID}/pipeline_schedules" \
  -d "description=${DESCRIPTION}" -d "ref=main" -d "cron=${CRON}" -d "cron_timezone=UTC")

ID=$(echo "$RESP" | jq -r '.id // empty')
if [[ -z "$ID" ]]; then
  echo "Failed to create schedule: $RESP" >&2
  exit 4
fi

echo "Created schedule id=$ID"
echo "$RESP" | jq '.'

exit 0
