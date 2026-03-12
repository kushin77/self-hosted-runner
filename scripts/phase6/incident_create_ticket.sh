#!/usr/bin/env bash
set -euo pipefail

# Create an incident ticket via GitHub Issues (fallback) or external tracker
# Requires: GITHUB_TOKEN and GITHUB_REPOSITORY

TITLE="[INCIDENT] $1"
BODY="$2"

if [ -z "${GITHUB_TOKEN:-}" ] || [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "GITHUB_TOKEN and GITHUB_REPOSITORY required to create incident ticket" >&2
  exit 2
fi

echo "Creating incident issue: $TITLE"
curl -s -X POST "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues" \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  -d "$(jq -n --arg t "$TITLE" --arg b "$BODY" '{title:$t, body:$b, labels:["incident"]}')" | jq -r '.html_url'
