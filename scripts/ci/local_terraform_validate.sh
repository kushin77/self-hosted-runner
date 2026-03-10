#!/usr/bin/env bash
set -euo pipefail

# Local Terraform validation script for internal runners or operator hosts.
# Runs formatting check, init (no backend), validate, and plan (optional).
# Usage: ./scripts/ci/local_terraform_validate.sh [--project PROJECT] [--env ENVIRONMENT] [--plan]

PROJECT=""
ENVIRONMENT="staging"
DO_PLAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --env) ENVIRONMENT="$2"; shift 2;;
    --plan) DO_PLAN=1; shift;;
    -h|--help) echo "Usage: $0 [--project PROJECT] [--env ENVIRONMENT] [--plan]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

export TF_VAR_gcp_project="$PROJECT"
export TF_VAR_environment="$ENVIRONMENT"

echo "Running terraform fmt -check..."
terraform fmt -check -recursive

echo "Initializing terraform (no backend)..."
terraform init -backend=false -input=false

echo "Validating terraform..."
terraform validate

if [[ "$DO_PLAN" -eq 1 ]]; then
  echo "Planning terraform (output -> tfplan)..."
  terraform plan -out=tfplan -input=false
  echo "Plan saved to tfplan"
fi

echo "Terraform validation complete."
