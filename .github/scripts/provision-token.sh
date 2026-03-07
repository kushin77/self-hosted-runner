#!/usr/bin/env bash
set -euo pipefail

# Securely provision RUNNER_MGMT_TOKEN to the repository.
# Usage: ./scripts/provision-token.sh

REPO="kushin77/self-hosted-runner"

echo "=== RUNNER_MGMT_TOKEN Provisioning ==="
echo "This script will add your PAT to the repository as a secret."
echo "Your PAT will be sent to GitHub and stored securely (never logged or printed)."
echo ""
echo "Paste your GitHub Personal Access Token (or press Ctrl+C to cancel):"
read -rs PAT
echo ""

if [[ -z "$PAT" ]]; then
  echo "ERROR: Empty token provided."
  exit 1
fi

# Provision the secret using gh
echo "Setting RUNNER_MGMT_TOKEN in repo $REPO..."
printf '%s' "$PAT" | gh secret set RUNNER_MGMT_TOKEN --repo "$REPO"

echo "✓ Secret provisioned successfully."
echo "The credential-monitor workflow will detect it within 5 minutes and dispatch runner-self-heal."
echo "You can force immediate run: gh workflow run .github/workflows/credential-monitor.yml --repo $REPO"
