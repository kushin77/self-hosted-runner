#!/usr/bin/env bash
set -euo pipefail

# list-non-org-runners.sh
# Uses GitHub CLI to list repository runners and organization runners,
# then prints runners registered at repo level that are not organization runners.

REPO="$(git rev-parse --show-toplevel | xargs basename)"
OWNER="$(git remote get-url origin 2>/dev/null || true)"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Install and authenticate first."
  exit 1
fi

echo "Listing repository runners for current repo"
repo_runners_json=$(gh api -H "Accept: application/vnd.github+json" /repos/:owner/:repo/actions/runners --jq '.runners')

echo "Listing organization runners (requires repo to be under an org and gh auth)"
org_runners_json="$(gh api /orgs/$(gh api user --jq .login 2>/dev/null || echo '')/actions/runners 2>/dev/null || echo '[]')"

echo "Repository runners summary:"
echo "$repo_runners_json" | jq -r '.[] | "- "+(.name) + " (id:" + (.id|tostring) + ") labels:" + ( [.labels[].name] | join(",") )'

echo
echo "Organization runners summary:"
echo "$org_runners_json" | jq -r '.[] | "- "+(.name) + " (id:" + (.id|tostring) + ") labels:" + ( [.labels[].name] | join(",") )'

echo
echo "Non-org repo runners (candidates for cleanup):"
# Compare names
comm -23 \
  <(echo "$repo_runners_json" | jq -r '.[].name' | sort) \
  <(echo "$org_runners_json" | jq -r '.[].name' | sort) || true

echo "To delete a repository runner:"
echo "  gh api -X DELETE /repos/:owner/:repo/actions/runners/<runner_id>"
