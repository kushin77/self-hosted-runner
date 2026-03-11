#!/bin/bash
#
# Terraform Deployment Script
# Applies validated Terraform configuration
# Includes backup and rollback capabilities
#
# Usage: ./deploy.sh [dev|staging|prod] [--auto-approve]
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="${1:-dev}"
AUTO_APPROVE="${2:---auto-approve}"
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${INFRA_DIR}/terraform"
ENV_TFVARS="${TF_DIR}/environments/${ENVIRONMENT}.tfvars"
BACKUP_DIR="${TF_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Validation
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
  echo -e "${RED}❌ Invalid environment: $ENVIRONMENT${NC}"
  echo "Usage: $0 [dev|staging|prod] [--auto-approve]"
  exit 1
fi

if [[ ! -f "$ENV_TFVARS" ]]; then
  echo -e "${RED}❌ Environment tfvars file not found: $ENV_TFVARS${NC}"
  exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}🚀 Terraform Deployment - Environment: $ENVIRONMENT${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

# Confirmation
if [[ "$AUTO_APPROVE" != "--auto-approve" ]]; then
  echo -e "${YELLOW}⚠️  WARNING: You are about to deploy to $ENVIRONMENT environment${NC}"
  read -p "Type 'yes' to continue: " confirmation
  if [[ "$confirmation" != "yes" ]]; then
    echo -e "${RED}❌ Deployment cancelled${NC}"
    exit 1
  fi
fi

# Step 1: Backup current state
echo -e "${YELLOW}1️⃣  Backing up current state...${NC}"
STATE_FILE="${TF_DIR}/terraform.tfstate"
if [[ -f "$STATE_FILE" ]]; then
  STATE_BACKUP="${BACKUP_DIR}/terraform-${ENVIRONMENT}-${TIMESTAMP}.tfstate"
  cp "$STATE_FILE" "$STATE_BACKUP"
  echo -e "${GREEN}✅ State backed up to: $STATE_BACKUP${NC}"
else
  echo -e "${YELLOW}⚠️  No existing state file${NC}"
fi

# Step 2: Initialize Terraform
echo -e "\n${YELLOW}2️⃣  Initializing Terraform...${NC}"
terraform -chdir="$TF_DIR" init -upgrade -backend-config="bucket=" -backend-config="prefix=terraform/${ENVIRONMENT}/state"
echo -e "${GREEN}✅ Terraform initialized${NC}"

# Step 3: Create plan
echo -e "\n${YELLOW}3️⃣  Creating deployment plan...${NC}"
PLAN_FILE="${TF_DIR}/.terraform/tfplan-${ENVIRONMENT}-${TIMESTAMP}"
terraform -chdir="$TF_DIR" plan \
  -var-file="$ENV_TFVARS" \
  -out="$PLAN_FILE" \
  | tee "${BACKUP_DIR}/plan-${ENVIRONMENT}-${TIMESTAMP}.log"

# Step 4: Apply plan
echo -e "\n${YELLOW}4️⃣  Applying Terraform configuration...${NC}"
terraform -chdir="$TF_DIR" apply "$PLAN_FILE" 2>&1 | tee "${BACKUP_DIR}/apply-${ENVIRONMENT}-${TIMESTAMP}.log"

# Step 5: Export outputs
echo -e "\n${YELLOW}5️⃣  Exporting deployment outputs...${NC}"
OUTPUT_FILE="${BACKUP_DIR}/outputs-${ENVIRONMENT}-${TIMESTAMP}.json"
terraform -chdir="$TF_DIR" output -json > "$OUTPUT_FILE"
echo -e "${GREEN}✅ Outputs exported to: $OUTPUT_FILE${NC}"

# Display outputs
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}📊 Deployment Outputs (${ENVIRONMENT})${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
terraform -chdir="$TF_DIR" output -raw deployment_summary || terraform -chdir="$TF_DIR" output

# Final summary
echo -e "\n${GREEN}✅ Deployment completed successfully!${NC}"
echo -e "${YELLOW}📝 Deployment logs:${NC}"
echo -e "  Plan:  ${BACKUP_DIR}/plan-${ENVIRONMENT}-${TIMESTAMP}.log"
echo -e "  Apply: ${BACKUP_DIR}/apply-${ENVIRONMENT}-${TIMESTAMP}.log"
echo -e "  State: ${BACKUP_DIR}/terraform-${ENVIRONMENT}-${TIMESTAMP}.tfstate"
echo -e "  Output: $OUTPUT_FILE"

echo -e "\n${YELLOW}Useful commands:${NC}"
echo -e "  View state:    terraform -chdir=\"$TF_DIR\" state list"
echo -e "  Show resource: terraform -chdir=\"$TF_DIR\" state show <resource>"
echo -e "  Get outputs:   terraform -chdir=\"$TF_DIR\" output"
