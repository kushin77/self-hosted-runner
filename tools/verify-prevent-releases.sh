#!/usr/bin/env bash
set -euo pipefail

# verify-prevent-releases.sh
# Automated verification for the `prevent-releases` service.
# Usage:
#  GITHUB_TOKEN=<token> ./tools/verify-prevent-releases.sh
# Options:
#  DRY_RUN=1  -> skip creating the release, only print the would-be tag
#  WAIT_SEC   -> seconds to wait for the service to act (default 35)

OWNER=${OWNER:-kushin77}
REPO=${REPO:-self-hosted-runner}
WAIT_SEC=${WAIT_SEC:-35}
DRY_RUN=${DRY_RUN:-0}

if [ "$DRY_RUN" != "1" ] && [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "ERROR: GITHUB_TOKEN must be set unless DRY_RUN=1"
  exit 2
fi

TS=$(date +%s)
TAG="gov-final-verify-test-$TS"

echo "Verification run for $OWNER/$REPO -> tag=$TAG"

if [ "$DRY_RUN" = "1" ]; then
  echo "DRY_RUN=1; skipping release creation. Would create tag: $TAG"
  exit 0
fi

CREATE_RESPONSE=$(curl -sS -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$OWNER/$REPO/releases" \
  -d "{\"tag_name\":\"$TAG\",\"name\":\"$TAG\",\"body\":\"Automated verification test release\",\"draft\":false,\"prerelease\":false}") || true

echo "Create response:"
echo "$CREATE_RESPONSE" | sed -n '1,200p'

RELEASE_ID=$(echo "$CREATE_RESPONSE" | sed -n 's/.*"id": \([0-9]*\).*/\1/p' | head -n1 || true)
if [ -z "$RELEASE_ID" ]; then
  echo "Failed to create release. Inspect response above."
  exit 3
fi

echo "Created release id $RELEASE_ID. Waiting ${WAIT_SEC}s for prevent-releases to act..."
sleep "$WAIT_SEC"

HTTP_CODE=$(curl -s -o /tmp/verify_check.body -w "%{http_code}" \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$OWNER/$REPO/releases/tags/$TAG") || true

echo "HTTP_CODE=$HTTP_CODE"
if [ "$HTTP_CODE" = "404" ]; then
  echo "REMOVED: prevent-releases removed the test release"
  exit 0
else
  echo "STILL_PRESENT: prevent-releases did not remove the test release"
  echo "Release check body:"
  cat /tmp/verify_check.body
  exit 4
fi
