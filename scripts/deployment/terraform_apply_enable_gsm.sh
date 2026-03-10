#!/usr/bin/env bash
set -euo pipefail

# Idempotent helper to apply the enable-secretmanager module.
# Usage: scripts/terraform_apply_enable_gsm.sh <terraform-root-dir> <project-id>

TF_ROOT=${1:-nexusshield/infrastructure/terraform}
PROJECT=${2:-p4-platform}

echo "Applying Secret Manager enable module for project: $PROJECT"

pushd "$TF_ROOT" >/dev/null

# Initialize and apply - idempotent
terraform init -input=false
terraform apply -auto-approve -input=false -var="enable_secretmanager_project=$PROJECT"

popd >/dev/null

echo "Done. If this fails due to permissions, run with account having serviceusage.services.enable."
