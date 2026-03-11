#!/usr/bin/env bash
set -euo pipefail

# Helper to mark releases policy via API (best-effort). Many release controls
# require organization-level policy; this script documents intent and performs
# available repo-level settings where possible. Usage requires admin token.
# Usage: GITHUB_TOKEN=<token> ./scripts/github/disable-releases.sh

OWNER="kushin77"
REPO="self-hosted-runner"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "Error: GITHUB_TOKEN environment variable is not set"
  exit 2
fi

echo "Note: GitHub does not provide a single toggle to 'disable releases'."
echo "This script will attempt to remove automation that creates releases and"
echo "document the policy. For strict enforcement, use branch protection and"
echo "organizational policies or run a server-side hook to block release creation."

API_URL="https://api.github.com/repos/${OWNER}/${REPO}"

echo "Setting repository to disallow auto-merge for PR-based releases (if set)..."
curl -sS -X PATCH \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "${API_URL}" \
  -d '{"allow_auto_merge":false}' \
  | jq . >/dev/stderr || true

echo "Completed API attempts. Follow the governance guide for full enforcement." 
