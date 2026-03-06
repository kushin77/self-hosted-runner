#!/usr/bin/env bash
set -euo pipefail

# trigger_yamltest_pipeline.sh
# Trigger a pipeline in GitLab to run the `YAMLtest-sovereign-runner` job.
# Requires: GITLAB_API_TOKEN (personal access token with api scope) and PROJECT_ID or PROJECT_PATH
# Usage: GITLAB_API_TOKEN=... PROJECT_ID=12345 ./scripts/ci/trigger_yamltest_pipeline.sh [ref]

GITLAB_API_TOKEN=${GITLAB_API_TOKEN:-}
PROJECT_ID=${PROJECT_ID:-}
PROJECT_PATH=${PROJECT_PATH:-}
REF=${1:-main}

if [ -z "${GITLAB_API_TOKEN}" ]; then
  echo "GITLAB_API_TOKEN not set" >&2
  exit 1
fi

if [ -z "${PROJECT_ID}" ] && [ -z "${PROJECT_PATH}" ]; then
  echo "Either PROJECT_ID or PROJECT_PATH must be set" >&2
  exit 1
fi

API_URL="https://gitlab.internal.elevatediq.com/api/v4"

if [ -n "${PROJECT_PATH}" ]; then
  # url-encode project path
  PROJ_ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "${PROJECT_PATH}")
  TARGET="$API_URL/projects/${PROJ_ENC}/pipeline"
else
  TARGET="$API_URL/projects/${PROJECT_ID}/pipeline"
fi

echo "Triggering pipeline for ref=${REF} on ${TARGET}"
curl -sS -X POST -H "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" \
  -d "ref=${REF}" \
  "${TARGET}" | jq -r '. | {id: .id, status: .status, web_url: .web_url}'

echo "Note: This triggers a full pipeline; the job `YAMLtest-sovereign-runner` will run according to `.gitlab-ci.yml` rules and tags."
