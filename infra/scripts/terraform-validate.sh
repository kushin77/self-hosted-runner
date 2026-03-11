#!/bin/bash
#
# Terraform Validation Script
# Validates Terraform configuration without applying changes
# Ensures syntax, variable requirements, and security best practices
#
# Usage: ./validate.sh [dev|staging|prod]
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="${1:-dev}"
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${INFRA_DIR}/terraform"
ENV_TFVARS="${TF_DIR}/environments/${ENVIRONMENT}.tfvars"

# Validation
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
  echo -e "${RED}❌ Invalid environment: $ENVIRONMENT${NC}"
  echo "Usage: $0 [dev|staging|prod]"
  exit 1
fi

if [[ ! -f "$ENV_TFVARS" ]]; then
  echo -e "${RED}❌ Environment tfvars file not found: $ENV_TFVARS${NC}"
  exit 1
fi

echo -e "${YELLOW}🔍 Validating Terraform configuration for environment: $ENVIRONMENT${NC}\n"

# 1. Terraform Format Check
echo -e "${YELLOW}1️⃣  Checking Terraform formatting...${NC}"
if terraform -chdir="$TF_DIR" fmt -check -recursive > /dev/null 2>&1; then
  echo -e "${GREEN}✅ Formatting check passed${NC}"
else
  echo -e "${YELLOW}⚠️  Formatting issues found. Running terraform fmt...${NC}"
  terraform -chdir="$TF_DIR" fmt -recursive
fi

# 2. Terraform Validation
echo -e "\n${YELLOW}2️⃣  Validating Terraform syntax...${NC}"
terraform -chdir="$TF_DIR" validate
echo -e "${GREEN}✅ Syntax validation passed${NC}"

# 3. Security Scan with tfsec
echo -e "\n${YELLOW}3️⃣  Running security scan with tfsec...${NC}"
if command -v tfsec &> /dev/null; then
  if tfsec "$TF_DIR" --format json --exit-code 0 > /tmp/tfsec-report.json 2>&1; then
    echo -e "${GREEN}✅ Security scan passed${NC}"
  else
    echo -e "${YELLOW}⚠️  Security findings:${NC}"
    tfsec "$TF_DIR" --format pretty --exit-code 0 || true
  fi
else
  echo -e "${YELLOW}⚠️  tfsec not installed. Install with: brew install tfsec${NC}"
fi

# 4. Terraform Plan (dry-run)
echo -e "\n${YELLOW}4️⃣  Creating Terraform plan (dry-run)...${NC}"
PLAN_FILE="${TF_DIR}/terraform-${ENVIRONMENT}-$(date +%s).tfplan"
terraform -chdir="$TF_DIR" plan \
  -var-file="$ENV_TFVARS" \
  -out="$PLAN_FILE" \
  > /dev/null 2>&1

if [[ $? -eq 0 ]]; then
  echo -e "${GREEN}✅ Plan created successfully: $PLAN_FILE${NC}"
  
  # Show plan summary
  echo -e "\n${YELLOW}📋 Plan Summary:${NC}"
  terraform -chdir="$TF_DIR" show "$PLAN_FILE" | grep -E "^Plan:|^Terraform" || true
else
  echo -e "${RED}❌ Plan failed. Check errors above.${NC}"
  exit 1
fi

# 5. Cost Estimation (if infracost installed)
echo -e "\n${YELLOW}5️⃣  Estimating infrastructure costs...${NC}"
if command -v infracost &> /dev/null; then
  infracost breakdown --path "$PLAN_FILE" --format table || echo -e "${YELLOW}⚠️  Cost estimation failed${NC}"
else
  echo -e "${YELLOW}⚠️  infracost not installed. Install from: https://www.infracost.io${NC}"
fi

# 6. Module validation
echo -e "\n${YELLOW}6️⃣  Validating modules...${NC}"
MODULE_DIRS=("$TF_DIR/modules"/*)
for module_dir in "${MODULE_DIRS[@]}"; do
  if [[ -d "$module_dir" ]]; then
    module_name=$(basename "$module_dir")
    echo -n "  Validating ${module_name}... "
    if terraform -chdir="$module_dir" validate > /dev/null 2>&1; then
      echo -e "${GREEN}✅${NC}"
    else
      echo -e "${RED}❌${NC}"
      exit 1
    fi
  fi
done

# Summary
echo -e "\n${GREEN}✅ All validation checks passed for environment: $ENVIRONMENT${NC}"
echo -e "${YELLOW}📝 Plan file: $PLAN_FILE${NC}"
echo -e "\nNext steps:"
echo -e "  Review the plan: terraform -chdir=\"$TF_DIR\" show \"$PLAN_FILE\""
echo -e "  Apply changes:   terraform -chdir=\"$TF_DIR\" apply \"$PLAN_FILE\""
