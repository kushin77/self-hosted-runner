#!/usr/bin/env bash
set -euo pipefail

OWNER="kushin77"
REPO="self-hosted-runner"
TITLE="$1"
BODY="$2"

PAYLOAD=$(jq -nc --arg t "$TITLE" --arg b "$BODY" '{title:$t, body:$b}')

curl -sS -X POST \
  -H "Authorization: Bearer $(cat /dev/fd/3)" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${OWNER}/${REPO}/issues" \
  -d @- <<< "$PAYLOAD" | jq -c .
