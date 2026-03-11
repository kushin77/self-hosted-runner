#!/usr/bin/env bash
set -euo pipefail

# Enable repository auto-merge for kushin77/self-hosted-runner
# Usage: GITHUB_TOKEN=<token> ./enable-auto-merge.sh

OWNER="kushin77"
REPO="self-hosted-runner"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Error: GITHUB_TOKEN environment variable is not set"
  exit 2
fi

API_URL="https://api.github.com/repos/${OWNER}/${REPO}"

# Preferred: gh CLI if available
if command -v gh >/dev/null 2>&1; then
  echo "Using gh to enable auto-merge"
  gh repo edit ${OWNER}/${REPO} --enable-auto-merge || true
else
  echo "Using GitHub API to enable auto-merge"
  curl -sS -X PATCH \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${API_URL}" \
    -d '{"allow_auto_merge":true}' \
    | jq . >/dev/stderr || true
fi

echo "Done. Please verify repository settings or check repo UI." 
