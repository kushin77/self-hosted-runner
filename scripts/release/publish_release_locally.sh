#!/usr/bin/env bash
set -euo pipefail

# publish_release_locally.sh
# Usage:
# 1) If you have a PAT locally: export GITHUB_TOKEN=ghp_xxx
#    then run: ./scripts/release/publish_release_locally.sh
# 2) Or, if you store PAT in GSM: SECRET_PROJECT=proj GH_TOKEN_SECRET=secret-name ./scripts/release/publish_release_locally.sh
#
# This script will push the current `release/go-live-2026-03-10` branch,
# merge it into `main` (no PR), push annotated tag `v2026.03.10`,
# create a release issue and then close it, all in a single audited run.

REPO="kushin77/self-hosted-runner"
BRANCH="release/go-live-2026-03-10"
TAG="v2026.03.10"

if [ -n "${SECRET_PROJECT:-}" ] && [ -n "${GH_TOKEN_SECRET:-}" ]; then
  echo "Loading GITHUB_TOKEN from GSM: ${GH_TOKEN_SECRET} (project=${SECRET_PROJECT})"
  GH_TOKEN=$(gcloud secrets versions access latest --secret="$GH_TOKEN_SECRET" --project="$SECRET_PROJECT")
  export GITHUB_TOKEN="$GH_TOKEN"
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: GITHUB_TOKEN not set. Export it or provide GSM secret variables." >&2
  exit 1
fi

echo "Pushing branch ${BRANCH} to origin..."
git push -u origin "$BRANCH"

echo "Merging ${BRANCH} into main (no PR)..."
git fetch origin main:main
git checkout main
git merge --no-ff "$BRANCH" -m "chore(release): go-live 2026-03-10"
git push origin main

echo "Pushing annotated tag ${TAG}..."
git tag -f -a "$TAG" -m "go-live 2026-03-10"
git push -f origin "$TAG"

echo "Creating release issue..."
issue_body=$(cat <<EOF
Release: go-live 2026-03-10

Release notes and audit entries have been committed. See release tag: ${TAG}
Audit SHA: 25103610f804fc822e99e7709a8231de449543bad442f6ab0305e0c1f291ab99
EOF
)
issue_response=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: application/json" \
  -d "{\"title\":\"Release: go-live 2026-03-10\",\"body\":$(echo "$issue_body" | jq -Rs '.') ,\"labels\": [\"release\"]}" \
  "https://api.github.com/repos/${REPO}/issues")

issue_number=$(echo "$issue_response" | jq -r '.number // empty')
if [ -n "$issue_number" ]; then
  echo "Created issue #${issue_number}. Closing it as completed..."
  curl -s -X PATCH -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: application/json" \
    -d '{"state":"closed","state_reason":"completed"}' \
    "https://api.github.com/repos/${REPO}/issues/${issue_number}" >/dev/null
  echo "Issue #${issue_number} closed."
else
  echo "Warning: issue creation failed or returned no number. Response: $issue_response"
fi

echo "Release publish complete."
