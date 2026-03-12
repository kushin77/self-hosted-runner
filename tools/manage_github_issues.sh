#!/usr/bin/env bash
set -euo pipefail

# Manage GitHub issues based on a local operations file.
# Requires: GITHUB_TOKEN and GITHUB_REPOSITORY (owner/repo)
# Usage: GITHUB_TOKEN=... GITHUB_REPOSITORY=owner/repo ./tools/manage_github_issues.sh

OPS_FILE="monitoring/ISSUES_TO_UPDATE.json"

if [ -z "${GITHUB_TOKEN:-}" ] || [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "GITHUB_TOKEN and GITHUB_REPOSITORY must be set to update GitHub issues; skipping." >&2
  exit 0
fi

if [ ! -f "$OPS_FILE" ]; then
  echo "No operations file found at $OPS_FILE; nothing to do." >&2
  exit 0
fi

echo "Reading issue operations from $OPS_FILE"
ops=$(cat "$OPS_FILE")

echo "$ops" | jq -c '.[]' | while read -r op; do
  number=$(echo "$op" | jq -r '.number')
  action=$(echo "$op" | jq -r '.action')
  comment=$(echo "$op" | jq -r '.comment')

  if [ "$action" = "close" ]; then
    echo "Closing issue #$number"
    # Post comment (if present)
    if [ -n "$comment" ] && [ "$comment" != "null" ]; then
      curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$number/comments" \
        -d "$(jq -n --arg b "$comment" '{body: $b}')" >/dev/null
    fi
    # Close the issue (idempotent)
    curl -s -X PATCH -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$number" \
      -d '{"state":"closed"}' | jq -r '.state'
  elif [ "$action" = "comment" ]; then
    echo "Commenting on issue #$number"
    curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$number/comments" \
      -d "$(jq -n --arg b "$comment" '{body: $b}')" >/dev/null
  else
    echo "Unknown action: $action for issue #$number; skipping" >&2
  fi
done

echo "Issue operations complete."
