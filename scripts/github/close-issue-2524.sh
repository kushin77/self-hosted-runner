#!/usr/bin/env bash
set -euo pipefail

OWNER=${OWNER:-kushin77}
REPO=${REPO:-self-hosted-runner}
ISSUE=${ISSUE:-2524}
TOKEN=${GITHUB_TOKEN:-}
if [ -z "$TOKEN" ]; then
  echo "Set GITHUB_TOKEN env var with repo scope"
  exit 1
fi

curl -sS -X PATCH -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/$OWNER/$REPO/issues/$ISSUE \
  -d '{"state":"closed"}' | jq -r '.html_url'
