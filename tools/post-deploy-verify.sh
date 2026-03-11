#!/usr/bin/env bash
set -euo pipefail

# post-deploy-verify.sh
# Runs the verification script added in tools/verify-prevent-releases.sh after deployment.
# It prefers an in-environment `GITHUB_TOKEN`, else will attempt to read from
# Google Secret Manager when `GOOGLE_CLOUD_PROJECT` and `GITHUB_TOKEN_SECRET` are set.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_SCRIPT="$SCRIPT_DIR/verify-prevent-releases.sh"

if [ ! -x "$VERIFY_SCRIPT" ]; then
  echo "ERROR: verify script not found or not executable: $VERIFY_SCRIPT"
  exit 2
fi

echo "post-deploy-verify: starting"

if [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "Using GITHUB_TOKEN from environment"
  exec env GITHUB_TOKEN="$GITHUB_TOKEN" "$VERIFY_SCRIPT"
fi

if [ -n "${GOOGLE_CLOUD_PROJECT:-}" ] && [ -n "${GITHUB_TOKEN_SECRET:-}" ]; then
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "gcloud CLI not found; cannot fetch secret. Please export GITHUB_TOKEN or install gcloud."
    exit 3
  fi
  echo "Fetching GITHUB_TOKEN from Secret Manager: $GITHUB_TOKEN_SECRET (project=$GOOGLE_CLOUD_PROJECT)"
  GITHUB_TOKEN_VALUE=$(gcloud secrets versions access latest --secret="$GITHUB_TOKEN_SECRET" --project="$GOOGLE_CLOUD_PROJECT" 2>/dev/null)
  if [ -z "$GITHUB_TOKEN_VALUE" ]; then
    echo "Failed to read secret $GITHUB_TOKEN_SECRET"
    exit 4
  fi
  exec env GITHUB_TOKEN="$GITHUB_TOKEN_VALUE" "$VERIFY_SCRIPT"
fi

echo "No GITHUB_TOKEN found. Configure by either:
- exporting GITHUB_TOKEN in the deploy environment, or
- setting GOOGLE_CLOUD_PROJECT and GITHUB_TOKEN_SECRET (and installing gcloud)."
exit 1
