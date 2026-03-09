#!/bin/bash
#
# Remote Terraform Apply (runs on target worker node)
# Executed via SSH from local dev machine
#
set -euo pipefail

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DEPLOY_DIR="/opt/self-hosted-runner"
TF_DIR="${DEPLOY_DIR}/terraform/environments/staging-tenant-a"
TFPLAN_FILE="${TF_DIR}/tfplan"

echo "[${TIMESTAMP}] Starting remote terraform apply..."
echo "[${TIMESTAMP}] Working directory: ${TF_DIR}"

# Navigate to terraform directory
cd "$TF_DIR"

# Regenerate plan on this system (avoids version mismatch issues)
echo "[${TIMESTAMP}] Generating terraform plan on remote (local terraform version)..."
if ! terraform plan -out="${TFPLAN_FILE}"; then
  echo "ERROR: Failed to generate plan on remote"
  exit 1
fi

echo "[${TIMESTAMP}] Running: terraform apply -auto-approve ${TFPLAN_FILE}"

if terraform apply -auto-approve "$TFPLAN_FILE"; then
  echo "[${TIMESTAMP}] ✅ Terraform apply completed successfully"
  
  # Extract outputs
  RUNNER_SA_EMAIL=$(terraform output -raw runner_sa_email 2>/dev/null || echo "N/A")
  echo "[${TIMESTAMP}] Service Account: ${RUNNER_SA_EMAIL}"
  
  # Save results
  cat > /tmp/terraform-apply-results.txt <<RESULTS_EOF
APPLY_STATUS=SUCCESS
TIMESTAMP=${TIMESTAMP}
RUNNER_SA_EMAIL=${RUNNER_SA_EMAIL}
RESULTS_EOF
  
  exit 0
else
  echo "[${TIMESTAMP}] ❌ Terraform apply failed"
  exit 1
fi
