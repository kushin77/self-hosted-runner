#!/usr/bin/env bash
set -euo pipefail

OWNER="kushin77"
REPO="self-hosted-runner"
TITLE="Governance enforcement completed (2026-03-11)"
BODY="Automated governance enforcement completed: auto-merge enabled; Actions disabled; branch protection applied; prevent-releases service deployed and scheduled.\n\nSee docs/ROTATE_GITHUB_TOKEN.md for rotation playbook.\n\nService: https://prevent-releases-2tqp6t4txq-uc.a.run.app\nScheduler job: prevent-releases-poll (*/1 * * * *).\n\nThis issue records finalization and will be closed after verification."

PAYLOAD=$(jq -nc --arg t "$TITLE" --arg b "$BODY" '{title:$t, body:$b}')
echo "$PAYLOAD" > /tmp/create_issue_payload.json

curl -sS -X POST \
  -H "Authorization: Bearer $(cat /dev/fd/3)" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${OWNER}/${REPO}/issues" \
  -d @/tmp/create_issue_payload.json | jq -c .

rm -f /tmp/create_issue_payload.json
