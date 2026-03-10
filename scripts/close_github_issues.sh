#!/usr/bin/env bash
# Close a list of GitHub issues by commenting with the audit link and closing them.
# Requires: GITHUB_TOKEN env var with `repo` scope.
# Usage: scripts/close_github_issues.sh issues.txt "Comment body text"

set -euo pipefail

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "GITHUB_TOKEN not set; cannot close issues remotely." >&2
  exit 2
fi

ISSUE_FILE="${1:-}"; shift || true
COMMENT_BODY="${1:-}
See audit logs in repo: logs/gcp-admin-provisioning-20260310.jsonl"

if [ -z "$ISSUE_FILE" ] || [ ! -f "$ISSUE_FILE" ]; then
  echo "Usage: $0 issues.txt [optional-comment]" >&2
  exit 2
fi

ORIGIN_URL=$(git remote get-url origin 2>/dev/null || true)
if [ -z "$ORIGIN_URL" ]; then
  echo "Cannot determine origin URL; aborting." >&2
  exit 1
fi

if echo "$ORIGIN_URL" | grep -q '^git@'; then
  OWNER_REPO=$(echo "$ORIGIN_URL" | sed -E 's#git@[^:]+:##; s#\.git$##')
else
  OWNER_REPO=$(echo "$ORIGIN_URL" | sed -E 's#^https?://[^/]+/##; s#\.git$##')
fi

OWNER=$(echo "$OWNER_REPO" | cut -d'/' -f1)
REPO=$(echo "$OWNER_REPO" | cut -d'/' -f2-)

API_BASE="https://api.github.com/repos/$OWNER/$REPO"

while read -r issue; do
  issue=$(echo "$issue" | sed 's/#//g; s/[^0-9]*//g')
  if [ -z "$issue" ]; then
    continue
  fi
  echo "Posting comment and closing issue #$issue"
  payload=$(jq -nc --arg b "$COMMENT_BODY" '{body:$b}')
  curl -sS -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" -d "$payload" "$API_BASE/issues/$issue/comments" >/dev/null
  curl -sS -X PATCH -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" -d '{"state":"closed"}' "$API_BASE/issues/$issue" >/dev/null
done < "$ISSUE_FILE"

echo "Done."
