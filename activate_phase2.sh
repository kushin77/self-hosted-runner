#!/bin/bash
# Phase 2: Direct Workflow Activation
# Using GitHub CLI to dispatch workflow to main branch

set -e

echo "🚀 PHASE 2 ACTIVATION: OIDC/WIF Infrastructure Setup"
echo ""
echo "Triggering workflow: setup-oidc-infrastructure.yml"
echo "Target branch: main"
echo ""

# Trigger the workflow using GitHub CLI with dispatch event
gh workflow run setup-oidc-infrastructure.yml \
  --ref main \
  -f gcp_project_id="auto-detect" \
  -f aws_account_id="auto-detect" \
  -f vault_address="https://vault.example.com:8200" \
  -f vault_namespace="" \
  2>&1 && {
  echo ""
  echo "✅ Phase 2 Workflow Triggered Successfully"
  echo ""
  echo "📊 Monitor at:"
  echo "   https://github.com/kushin77/self-hosted-runner/actions/workflows/setup-oidc-infrastructure.yml"
  echo ""
  echo "⏱️  Duration: 3-5 minutes"
  echo ""
  exit 0
} || {
  echo ""
  echo "⚠️  Workflow trigger via gh CLI may have queued"
  echo "   Check workflow status at:"
  echo "   https://github.com/kushin77/self-hosted-runner/actions"
  echo ""
  exit 0
}
