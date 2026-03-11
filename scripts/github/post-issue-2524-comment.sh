#!/usr/bin/env bash
set -euo pipefail

# Usage: GITHUB_TOKEN=xxx ./post-issue-2524-comment.sh
OWNER=${OWNER:-kushin77}
REPO=${REPO:-self-hosted-runner}
ISSUE=${ISSUE:-2524}
TOKEN=${GITHUB_TOKEN:-}
if [ -z "$TOKEN" ]; then
  echo "Set GITHUB_TOKEN env var with repo:issues scope"
  exit 1
fi
BODY=$(sed 's/"/\\"/g' scripts/github/comment-2524.txt)

curl -sS -X POST -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/$OWNER/$REPO/issues/$ISSUE/comments \
  -d "{\"body\": \"$BODY\"}" | jq -r '.html_url'
