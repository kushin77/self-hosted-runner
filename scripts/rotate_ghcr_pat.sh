#!/bin/bash
set -e

# Usage: GHCR_PAT=<new_pat> ./scripts/rotate_ghcr_pat.sh [--repo owner/repo] [--scope org|repo]
# Requires gh CLI authenticated as an admin that can set repo/org secrets.

REPO="$(git rev-parse --show-toplevel 2>/dev/null || echo '')"
OWNER_REPO="$(basename $(pwd))"
SCOPE="repo"

while [[ $# -gt 0 ]]; do
  case $1 in
    --repo)
      OWNER_REPO="$2"; shift 2;;
    --scope)
      SCOPE="$2"; shift 2;;
    *) shift;;
  esac
done

if [ -z "$GHCR_PAT" ]; then
  echo "Provide new token in env: GHCR_PAT=<token>"
  exit 1
fi

if ! command -v gh >/dev/null; then
  echo "gh CLI not available. Install and authenticate first."
  exit 2
fi

if [ "$SCOPE" = "org" ]; then
  echo "Setting org secret GHCR_PAT for org: $OWNER_REPO"
  gh api --method PUT /orgs/$OWNER_REPO/actions/secrets/GHCR_PAT -f value=$(echo -n "$GHCR_PAT" | gh secret encrypt -q) || true
  echo "(If above failed, ensure your gh auth has admin:org scopes and use 'gh secret set' manually)"
else
  echo "Setting repo secret GHCR_PAT for repo: $OWNER_REPO"
  echo -n "$GHCR_PAT" | gh secret set GHCR_PAT --repo "$OWNER_REPO"
fi

echo "Updated GHCR_PAT secret (scope=$SCOPE repo=$OWNER_REPO)."
