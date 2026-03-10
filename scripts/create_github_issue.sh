#!/usr/bin/env bash
# Create a GitHub issue for this repository using the REST API.
# Usage:
#   scripts/create_github_issue.sh --title "Title" --body-file path/to/body.md

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --title "TITLE" --body-file PATH
Requires: GITHUB_TOKEN in environment with repo scope.
EOF
  exit 2
}

TITLE=""
BODY_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --title) TITLE="$2"; shift 2;;
    --body-file) BODY_FILE="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1" >&2; usage;;
  esac
done

if [ -z "$TITLE" ] || [ -z "$BODY_FILE" ]; then
  usage
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "GITHUB_TOKEN not set; skipping remote issue creation. To create an issue manually, open an issue with the contents of $BODY_FILE" >&2
  exit 0
fi

if [ ! -f "$BODY_FILE" ]; then
  echo "Body file not found: $BODY_FILE" >&2
  exit 1
fi

# Determine owner/repo from git remote
ORIGIN_URL=$(git remote get-url origin 2>/dev/null || true)
if [ -z "$ORIGIN_URL" ]; then
  echo "Could not determine origin URL from git; aborting issue create." >&2
  exit 1
fi

# Parse owner and repo
if echo "$ORIGIN_URL" | grep -q '^git@'; then
  # git@github.com:owner/repo.git
  OWNER_REPO=$(echo "$ORIGIN_URL" | sed -E 's#git@[^:]+:##; s#\.git$##')
else
  # https://github.com/owner/repo.git or https://github.com/owner/repo
  OWNER_REPO=$(echo "$ORIGIN_URL" | sed -E 's#^https?://[^/]+/##; s#\.git$##')
fi

OWNER=$(echo "$OWNER_REPO" | cut -d'/' -f1)
REPO=$(echo "$OWNER_REPO" | cut -d'/' -f2-)

API_URL="https://api.github.com/repos/$OWNER/$REPO/issues"

BODY=$(sed 's/"/\\"/g' "$BODY_FILE" | awk '{printf "%s\\n", $0}' )

payload=$(jq -nc --arg t "$TITLE" --arg b "$BODY" '{title:$t, body:$b}')

resp=$(curl -sS -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" -d "$payload" "$API_URL")

issue_url=$(echo "$resp" | jq -r .html_url // empty)

if [ -n "$issue_url" ]; then
  echo "Created issue: $issue_url"
  exit 0
else
  echo "Failed to create issue. Response:" >&2
  echo "$resp" >&2
  exit 1
fi
