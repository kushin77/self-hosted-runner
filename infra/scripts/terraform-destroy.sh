#!/bin/bash
#
# Terraform Destroy Script
# Safely destroys Terraform-managed infrastructure
# Includes confirmation and backup
#
# Usage: ./destroy.sh [dev|staging|prod] [--auto-approve]
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

echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${RED}⚠️  DESTRUCTIVE OPERATION - Infrastructure Destruction${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════════════${NC}\n"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Confirmation
echo -e "${RED}🚨 WARNING: You are about to DESTROY all $ENVIRONMENT infrastructure!${NC}"
echo -e "${YELLOW}This will delete:${NC}"
echo -e "  - Cloud Run services"
echo -e "  - Cloud SQL databases"
echo -e "  - Redis instances"
echo -e "  - VPC networks"
echo -e "  - Storage buckets"
echo -e "  - All managed resources"
echo -e ""

if [[ "$AUTO_APPROVE" != "--auto-approve" ]]; then
  read -p "Type the environment name ($ENVIRONMENT) to confirm: " confirmation
  if [[ "$confirmation" != "$ENVIRONMENT" ]]; then
    echo -e "${GREEN}✅ Destruction cancelled${NC}"
    exit 0
  fi
fi

# Step 1: Backup state before destruction
echo -e "\n${YELLOW}1️⃣  Backing up state before destruction...${NC}"
STATE_FILE="${TF_DIR}/terraform.tfstate"
if [[ -f "$STATE_FILE" ]]; then
  STATE_BACKUP="${BACKUP_DIR}/terraform-${ENVIRONMENT}-BEFORE-DESTROY-${TIMESTAMP}.tfstate"
  cp "$STATE_FILE" "$STATE_BACKUP"
  echo -e "${GREEN}✅ State backed up to: $STATE_BACKUP${NC}"
fi

# Step 2: Initialize Terraform
echo -e "\n${YELLOW}2️⃣  Initializing Terraform...${NC}"
terraform -chdir="$TF_DIR" init -backend-config="bucket=" -backend-config="prefix=terraform/${ENVIRONMENT}/state" > /dev/null
echo -e "${GREEN}✅ Terraform initialized${NC}"

# Step 3: Show what will be destroyed
echo -e "\n${YELLOW}3️⃣  Resources that will be destroyed:${NC}"
terraform -chdir="$TF_DIR" plan -destroy \
  -var-file="$ENV_TFVARS" | tee "${BACKUP_DIR}/destroy-plan-${ENVIRONMENT}-${TIMESTAMP}.log"

# Step 4: Destroy
if [[ "$AUTO_APPROVE" == "--auto-approve" ]]; then
  terraform -chdir="$TF_DIR" destroy \
    -var-file="$ENV_TFVARS" \
    -auto-approve 2>&1 | tee "${BACKUP_DIR}/destroy-${ENVIRONMENT}-${TIMESTAMP}.log"
else
  terraform -chdir="$TF_DIR" destroy \
    -var-file="$ENV_TFVARS" 2>&1 | tee "${BACKUP_DIR}/destroy-${ENVIRONMENT}-${TIMESTAMP}.log"
fi

# Final message
echo -e "\n${RED}✅ Destruction completed for environment: $ENVIRONMENT${NC}"
echo -e "${YELLOW}📝 Backup state file: $STATE_BACKUP${NC}"
echo -e "${YELLOW}📝 Destruction logs: ${BACKUP_DIR}/destroy-${ENVIRONMENT}-${TIMESTAMP}.log${NC}"
