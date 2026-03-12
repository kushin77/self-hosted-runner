#!/usr/bin/env bash
set -euo pipefail

# Usage:
# GITHUB_TOKEN=... GITHUB_REPOSITORY=owner/repo bash .github/scripts/create_pr_and_issue.sh
# If GITHUB_REPOSITORY is not set, the script will attempt to parse it from 'git remote get-url origin'.

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "Error: GITHUB_TOKEN environment variable must be set (repo scope)." >&2
  exit 2
fi

REPO=${GITHUB_REPOSITORY:-}
if [ -z "$REPO" ]; then
  url=$(git remote get-url origin 2>/dev/null || true)
  if [ -z "$url" ]; then
    echo "Cannot determine repository. Set GITHUB_REPOSITORY=owner/repo or ensure 'origin' remote exists." >&2
    exit 3
  fi
  REPO=$(echo "$url" | sed -n 's#.*[:/]\([^/]*\/[^/]*\)\(.git\)\?$#\1#p')
fi

OWNER=$(echo "$REPO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO" | cut -d/ -f2)

PR_BODY_FILE=PR_BODY.md
ISSUE_BODY_FILE=ISSUE_CREATE.md
HEAD_BRANCH="elite/gitlab-ops-setup"
BASE_BRANCH="main"

if [ ! -f "$PR_BODY_FILE" ]; then
  echo "Missing $PR_BODY_FILE in repo root" >&2
  exit 4
fi
if [ ! -f "$ISSUE_BODY_FILE" ]; then
  echo "Missing $ISSUE_BODY_FILE in repo root" >&2
  exit 5
fi

TITLE=$(sed -n '1p' "$PR_BODY_FILE" | sed 's/^Title:\s*//')
PR_BODY_JSON=$(jq -Rs . "$PR_BODY_FILE")
ISSUE_TITLE=$(sed -n '1p' "$ISSUE_BODY_FILE" | sed 's/^Title:\s*//')
ISSUE_BODY_JSON=$(jq -Rs . "$ISSUE_BODY_FILE")

API_URL="https://api.github.com/repos/${OWNER}/${REPO_NAME}"
AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"

# Check for existing PR from the same head branch
echo "Checking for existing PR from ${OWNER}:${HEAD_BRANCH} -> ${BASE_BRANCH}..."
existing_pr=$(curl -s -H "$AUTH_HEADER" "$API_URL/pulls?head=${OWNER}:${HEAD_BRANCH}&base=${BASE_BRANCH}" | jq '.[0]')
if [ "$existing_pr" != "null" ]; then
  pr_url=$(echo "$existing_pr" | jq -r .html_url)
  echo "Found existing PR: $pr_url"
else
  echo "Creating PR..."
  create_pr_resp=$(curl -s -H "$AUTH_HEADER" -X POST "$API_URL/pulls" -d $(jq -n --arg t "$TITLE" --arg h "$HEAD_BRANCH" --arg b "$BASE_BRANCH" --arg body "$(cat $PR_BODY_FILE)" '{title:$t, head:$h, base:$b, body:$body}'))
  pr_url=$(echo "$create_pr_resp" | jq -r .html_url)
  if [ "$pr_url" = "null" ] || [ -z "$pr_url" ]; then
    echo "PR creation failed: $(echo "$create_pr_resp" | jq -r .message // "(no message)")" >&2
    exit 6
  fi
  echo "PR created: $pr_url"
fi

# Create an issue to track review (if not exists)
# Check for existing issue with same title
echo "Checking for existing issue titled: $ISSUE_TITLE"
existing_issue=$(curl -s -H "$AUTH_HEADER" "$API_URL/issues?state=open" | jq -r --arg title "$ISSUE_TITLE" '.[] | select(.title==$title) | .html_url' | head -n1 || true)
if [ -n "$existing_issue" ]; then
  echo "Found existing issue: $existing_issue"
else
  echo "Creating issue..."
  create_issue_resp=$(curl -s -H "$AUTH_HEADER" -X POST "$API_URL/issues" -d $(jq -n --arg t "$ISSUE_TITLE" --arg body "$(cat $ISSUE_BODY_FILE)" '{title:$t, body:$body}'))
  issue_url=$(echo "$create_issue_resp" | jq -r .html_url)
  if [ "$issue_url" = "null" ] || [ -z "$issue_url" ]; then
    echo "Issue creation failed: $(echo "$create_issue_resp" | jq -r .message // "(no message)")" >&2
    exit 7
  fi
  echo "Issue created: $issue_url"
fi

echo "Done. PR and Issue created or already present."
