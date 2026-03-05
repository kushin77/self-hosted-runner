#!/usr/bin/env bash
# Close pull requests inactive for >30 days and label them 'stale'
# Requires GH CLI configured with repo access.

days=${1:-30}
echo "Closing PRs inactive for $days days"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI required" >&2
  exit 1
fi

for pr in $(gh pr list --state open --json number,updatedAt --jq ".[] | select((now - (.updatedAt | fromdateiso8601)) > ($days*24*3600)) | .number"); do
  echo "Closing stale PR #$pr"
  gh pr close "$pr" --comment "Automatically closing due to inactivity (>$days days)" || true
done
