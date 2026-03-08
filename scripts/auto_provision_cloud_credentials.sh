#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=${1:-true}

echo "Auto-provision cloud credentials (DRY_RUN=${DRY_RUN})"

# Idempotent, safe steps. This script attempts to provision:
#  - GCP Workload Identity Pool + Provider
#  - AWS OIDC Provider + Role
#  - HashiCorp Vault bootstrap (Helm/standalone)

if command -v gh >/dev/null 2>&1; then
  echo "gh CLI available"
else
  echo "gh CLI not found. Please install GitHub CLI to allow issue creation and secret writes."
fi

if [ "$DRY_RUN" = "true" ] || [ "$DRY_RUN" = "True" ]; then
  echo "DRY_RUN mode: no changes will be applied. Printing intended actions..."
  echo "- Check GCP provider (gcloud)"
  echo "- Check AWS provider (aws cli)"
  echo "- Plan Terraform modules under infra/* (if present)"
  exit 0
fi

# Non-dry run: attempt to run terraform in each infra folder if terraform is present
for d in infra/gcp/wif infra/aws/oidc infra/vault; do
  if [ -d "$d" ]; then
    echo "Processing $d"
    pushd "$d" >/dev/null
    if command -v terraform >/dev/null 2>&1; then
      terraform init -input=false
      terraform apply -auto-approve -input=false
    else
      echo "terraform not installed in runner. Skipping $d"
    fi
    popd >/dev/null
  else
    echo "Directory $d not found — skipping"
  fi
done

echo "Auto-provision completed (non-dry-run). Review outputs and set repository secrets as needed."
