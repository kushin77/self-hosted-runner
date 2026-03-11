#!/usr/bin/env bash
set -euo pipefail

ISSUE_NUMBER="${1:-2558}"
OWNER="kushin77"
REPO="self-hosted-runner"

curl -sS -X PATCH \
  -H "Authorization: Bearer $(cat /dev/fd/3)" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${OWNER}/${REPO}/issues/${ISSUE_NUMBER}" \
  -d '{"state":"closed"}' | jq -c .
