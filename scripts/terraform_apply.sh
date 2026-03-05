#!/usr/bin/env bash
set -euo pipefail

# You can load credentials from GSM using the helper:
# SECRET_PROJECT=proj GCP_SA_SECRET=sa-key GH_TOKEN_SECRET=gh-token PROJECT_ID_SECRET=proj-id \
#   ./scripts/load_gsm_secrets.sh
# This will export GOOGLE_APPLICATION_CREDENTIALS and PROJECT_ID.
if [ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
  echo "ERROR: GOOGLE_APPLICATION_CREDENTIALS not set. Export path to SA JSON file or use load_gsm_secrets.sh."
  exit 2
fi

if [ -z "${PROJECT_ID:-}" ]; then
  echo "Usage: PROJECT_ID=your-project-id $0"
  exit 2
fi

cd "$(dirname "$0")/../terraform"

echo "Initializing Terraform..."
terraform init

echo "Planning for project: $PROJECT_ID"
terraform plan -var="project_id=$PROJECT_ID"

# Non-interactive mode: set AUTO_APPROVE=1 to skip prompt
if [ "${AUTO_APPROVE:-0}" = "1" ]; then
  terraform apply -var="project_id=$PROJECT_ID" -auto-approve
  echo "Apply complete. Run 'terraform output' to view outputs."
else
  read -p "Apply changes? (y/N): " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    terraform apply -var="project_id=$PROJECT_ID" -auto-approve
    echo "Apply complete. Run 'terraform output' to view outputs."
  else
    echo "Aborting apply."; exit 0
  fi
fi
