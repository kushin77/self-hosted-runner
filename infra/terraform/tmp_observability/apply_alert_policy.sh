#!/usr/bin/env bash
set -euo pipefail

# Apply Terraform for synthetic health-check alert policy
# Usage: ./apply_alert_policy.sh PROJECT_ID

PROJECT_ID=${1:-nexusshield-prod}
TF_DIR="$(dirname "$0")"

echo "Applying Terraform for synthetic health alert policy..."
echo "Project: $PROJECT_ID"
echo "Working directory: $TF_DIR"

# Initialize Terraform (safe to run multiple times)
terraform -chdir="$TF_DIR" init -upgrade=false 2>&1 | grep -v "already been initialized" || true

# Plan
echo "Planning changes..."
terraform -chdir="$TF_DIR" plan -var="project=$PROJECT_ID" -out=tfplan || {
  echo "Terraform plan failed" >&2
  exit 1
}

# Apply
echo "Applying changes..."
terraform -chdir="$TF_DIR" apply -auto-approve tfplan || {
  echo "Terraform apply failed" >&2
  exit 1
}

echo "Alert policy applied successfully"

# Show outputs
echo ""
echo "Current alert policy:"
terraform -chdir="$TF_DIR" output -raw alert_policy_id 2>/dev/null || echo "(no output defined)"
