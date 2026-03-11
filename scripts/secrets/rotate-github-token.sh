#!/usr/bin/env bash
set -euo pipefail

# rotate-github-token.sh
# Usage:
#  GCP_PROJECT=nexusshield-prod NEW_GITHUB_TOKEN="<new token>" \
#    ./rotate-github-token.sh
# If NEW_GITHUB_TOKEN is not set, reads token from stdin.

GCP_PROJECT=${GCP_PROJECT:-nexusshield-prod}
SECRET_NAME=${SECRET_NAME:-github-token}

if [ -z "${NEW_GITHUB_TOKEN:-}" ]; then
  echo "Enter new GitHub PAT (will not echo):" >&2
  read -rs NEW_GITHUB_TOKEN
  echo >&2
fi

if [ -z "$NEW_GITHUB_TOKEN" ]; then
  echo "No token provided" >&2
  exit 2
fi

echo "Adding new version to secret $SECRET_NAME in project $GCP_PROJECT"
printf '%s' "$NEW_GITHUB_TOKEN" | GCP_PROJECT="$GCP_PROJECT" ./provision-github-token-to-gsm.sh "$SECRET_NAME"

echo "Ensure orchestrator SA has access (example):"
echo "gcloud secrets add-iam-policy-binding $SECRET_NAME --project=$GCP_PROJECT --member=\"serviceAccount:nxs-automation-sa@$GCP_PROJECT.iam.gserviceaccount.com\" --role=\"roles/secretmanager.secretAccessor\""

echo "Rotation complete. Run the orchestrator (dry-run) to verify."
