#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: 'gh' CLI not found. Install GitHub CLI and authenticate (gh auth login)."
  exit 2
fi

REPO="akushnir/self-hosted-runner"

echo "Creating GH issues in ${REPO} (requires gh auth)..."

gh issue create --repo "$REPO" --title "Apply Terraform: GCP KMS & GCS for Vault (auto-unseal)" --body "Apply the Terraform in /terraform to provision KMS key ring, crypto key, and GCS bucket for Vault storage. Use the helper script ./scripts/terraform_apply.sh to run apply."

gh issue create --repo "$REPO" --title "Configure Workload Identity Federation for GitHub Actions" --body "Create Workload Identity Pool/Provider and bind the Vault service account to allow OIDC-based impersonation. See /terraform/workload_identity.tf and docs/TODO_INFRA_ISSUES.md for details."

gh issue create --repo "$REPO" --title "Final Production Test: Trivy Gate + Vault Auto-Unseal" --body "Run production deployment with real OIDC credentials, validate Trivy gating behavior and Vault auto-unseal. Follow acceptance criteria in docs/TODO_INFRA_ISSUES.md."

echo "Issues created."
