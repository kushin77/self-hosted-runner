#!/usr/bin/env bash
set -euo pipefail

# Usage: persist-secret.sh <NAME> <VALUE> [repo]
NAME=${1:-}
VALUE=${2:-}
REPO=${3:-${GITHUB_REPOSITORY:-}}

if [ -z "$NAME" ] || [ -z "$VALUE" ]; then
  echo "Usage: $0 <NAME> <VALUE> [repo]" >&2
  exit 2
fi

if [ -z "$REPO" ]; then
  echo "Repository not specified and GITHUB_REPOSITORY not set" >&2
  exit 2
fi

if [ -z "${GITHUB_ADMIN_TOKEN-}" ]; then
  echo "GITHUB_ADMIN_TOKEN must be set in environment to persist secrets" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found; installing to /tmp/gh"
  ARCH=$(uname -s | tr '[:upper:]' '[:lower:]')
  curl -fsSL https://github.com/cli/cli/releases/latest/download/gh_${ARCH}_amd64.tar.gz -o /tmp/gh.tar.gz
  tar -xzf /tmp/gh.tar.gz -C /tmp
  sudo mv /tmp/gh_*_amd64/bin/gh /usr/local/bin/gh
fi

export GH_TOKEN="$GITHUB_ADMIN_TOKEN"

echo "Persisting secret $NAME to $REPO"
gh secret set "$NAME" --repo "$REPO" --body "$VALUE"

echo "$NAME persisted"
