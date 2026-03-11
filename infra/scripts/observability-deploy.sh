#!/bin/bash
# Deploy Phase 3 Observability modules
set -e
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$INFRA_DIR/terraform"
ENVIRONMENT="${1:-dev}"
ENV_TFVARS="$TF_DIR/environments/${ENVIRONMENT}.tfvars"

if [[ ! -f "$ENV_TFVARS" ]]; then
  echo "Environment tfvars not found: $ENV_TFVARS"
  exit 1
fi

echo "Deploying observability (monitoring, logging, compliance, health) for $ENVIRONMENT"

terraform -chdir="$TF_DIR" init -upgrade
terraform -chdir="$TF_DIR" plan -var-file="$ENV_TFVARS" -out="observability-${ENVIRONMENT}.tfplan"
terraform -chdir="$TF_DIR" apply "observability-${ENVIRONMENT}.tfplan"

echo "Observability deployment complete"
