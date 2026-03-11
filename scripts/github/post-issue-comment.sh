#!/usr/bin/env bash
set -euo pipefail

# Post a comment to issue #1615 and close it.
# Usage: GITHUB_TOKEN=<token> ./post-issue-comment.sh

OWNER="kushin77"
REPO="self-hosted-runner"
ISSUE_NUMBER=1615

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Error: GITHUB_TOKEN environment variable is not set"
  exit 2
fi

COMMENT_API="https://api.github.com/repos/${OWNER}/${REPO}/issues/${ISSUE_NUMBER}/comments"
ISSUE_API="https://api.github.com/repos/${OWNER}/${REPO}/issues/${ISSUE_NUMBER}"

BODY_COMMENT="Auto-merge has been enabled to allow fully hands-off operation. Repository auto-merge setting was updated via automation. Closing this issue. If you need a different policy, re-open and comment.\n\nGovernance notes applied: immutable, ephemeral, idempotent, no-ops, hands-off. Credential stores: GSM/Vault/KMS. Direct development and direct deployment enforced."

# Post comment
curl -sS -X POST \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "${COMMENT_API}" \
  -d "$(jq -nc --arg b "$BODY_COMMENT" '{body:$b}')" \
  | jq . >/dev/stderr || true

# Close issue
curl -sS -X PATCH \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "${ISSUE_API}" \
  -d '{"state":"closed"}' \
  | jq . >/dev/stderr || true

echo "Comment posted and issue closed (or attempted). Verify on GitHub." 
