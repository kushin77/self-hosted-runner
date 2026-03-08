#!/usr/bin/env bash
# Atomic write/read helper for infrastructure state markers (GitHub repo contents)
# Usage:
#  write_state.sh write <path> <json-string>
#  write_state.sh read <path>
# Requires: `gh` CLI authenticated with repo permissions (contents write)

set -euo pipefail

OP=${1:-}
PATH_IN_REPO=${2:-}
DATA=${3:-}

if [ -z "$OP" ] || [ -z "$PATH_IN_REPO" ]; then
  echo "Usage: $0 <write|read> <infrastructure/state/file.json> [json-data]"
  exit 2
fi

OWNER=$(gh repo view --json name,owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')

API_PATH="repos/${OWNER}/${REPO}/contents/${PATH_IN_REPO}"

if [ "$OP" = "read" ]; then
  gh api "$API_PATH" --jq '.content' 2>/dev/null | base64 --decode || exit 0
  exit 0
fi

if [ "$OP" = "write" ]; then
  if [ -z "$DATA" ]; then
    echo "Missing data for write operation" >&2
    exit 2
  fi

  # Check if file exists to decide create or update
  EXISTING=$(gh api "$API_PATH" 2>/dev/null || true)
  COMMIT_MSG="state: update ${PATH_IN_REPO} by automation"

  if [ -z "$EXISTING" ]; then
    # create
    gh api -X PUT "$API_PATH" -f message="$COMMIT_MSG" -f content="$(echo -n "$DATA" | base64 -w0)" >/dev/null
  else
    SHA=$(echo "$EXISTING" | jq -r .sha)
    gh api -X PUT "$API_PATH" -f message="$COMMIT_MSG" -f content="$(echo -n "$DATA" | base64 -w0)" -f sha="$SHA" >/dev/null
  fi
  echo "wrote: $PATH_IN_REPO"
  exit 0
fi

echo "Unsupported operation: $OP" >&2
exit 2
