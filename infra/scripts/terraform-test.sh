#!/bin/bash
#
# Terraform Testing Script
# Runs comprehensive tests on Terraform configuration
# Validates modules, outputs, and integration
#
# Usage: ./test.sh [dev|staging|prod]
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
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${INFRA_DIR}/terraform"
ENV_TFVARS="${TF_DIR}/environments/${ENVIRONMENT}.tfvars"
TEST_RESULTS="${TF_DIR}/test-results-${ENVIRONMENT}.txt"

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

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}🧪 Terraform Testing - Environment: $ENVIRONMENT${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
test_passed() {
  echo -e "${GREEN}✅ $1${NC}"
  ((TESTS_PASSED++))
}

test_failed() {
  echo -e "${RED}❌ $1${NC}"
  ((TESTS_FAILED++))
}

# Test 1: Variable validation
echo -e "${YELLOW}1️⃣  Testing variable definitions...${NC}"

required_vars=("project_id" "region" "backend_image" "frontend_image" "redis_auth_password" "database_root_password")
for var in "${required_vars[@]}"; do
  if grep -q "variable \"$var\"" "$TF_DIR/variables.tf"; then
    test_passed "Variable '$var' defined"
  else
    test_failed "Variable '$var' missing"
  fi
done

# Test 2: Module structure
echo -e "\n${YELLOW}2️⃣  Testing module structure...${NC}"

modules=("iam" "vpc_networking" "cloud_sql" "redis" "storage" "cloud_run")
for module in "${modules[@]}"; do
  module_path="$TF_DIR/modules/$module"
  if [[ -d "$module_path" ]] && [[ -f "$module_path/main.tf" ]] && [[ -f "$module_path/variables.tf" ]] && [[ -f "$module_path/outputs.tf" ]]; then
    test_passed "Module '$module' has correct structure"
  else
    test_failed "Module '$module' missing required files"
  fi
done

# Test 3: Root configuration
echo -e "\n${YELLOW}3️⃣  Testing root configuration...${NC}"

if [[ -f "$TF_DIR/main.tf" ]] && [[ -f "$TF_DIR/variables.tf" ]] && [[ -f "$TF_DIR/outputs.tf" ]]; then
  test_passed "Root configuration files present"
else
  test_failed "Root configuration files missing"
fi

# Test 4: Environment file structure
echo -e "\n${YELLOW}4️⃣  Testing environment configuration...${NC}"

required_env_vars=("project_id" "environment" "backend_image" "frontend_image")
for var in "${required_env_vars[@]}"; do
  if grep -q "^$var" "$ENV_TFVARS"; then
    test_passed "Environment variable '$var' in $ENVIRONMENT.tfvars"
  else
    test_failed "Environment variable '$var' missing in $ENVIRONMENT.tfvars"
  fi
done

# Test 5: Terraform syntax
echo -e "\n${YELLOW}5️⃣  Testing Terraform syntax...${NC}"

if terraform -chdir="$TF_DIR" validate > /dev/null 2>&1; then
  test_passed "Terraform syntax validation"
else
  test_failed "Terraform syntax validation"
fi

# Test 6: Module syntax
echo -e "\n${YELLOW}6️⃣  Testing module syntax...${NC}"

for module in "${modules[@]}"; do
  module_path="$TF_DIR/modules/$module"
  if terraform -chdir="$module_path" validate > /dev/null 2>&1; then
    test_passed "Module '$module' syntax validation"
  else
    test_failed "Module '$module' syntax validation"
  fi
done

# Test 7: Terraform formatting
echo -e "\n${YELLOW}7️⃣  Testing code formatting...${NC}"

if terraform -chdir="$TF_DIR" fmt -check -recursive > /dev/null 2>&1; then
  test_passed "Terraform code formatting"
else
  test_failed "Terraform code formatting (run: terraform fmt -recursive)"
fi

# Test 8: Provider requirements
echo -e "\n${YELLOW}8️⃣  Testing provider requirements...${NC}"

if grep -q "hashicorp/google" "$TF_DIR/variables.tf"; then
  test_passed "Google provider configured in root"
else
  test_failed "Google provider missing in root"
fi

# Test 9: Backend configuration
echo -e "\n${YELLOW}9️⃣  Testing backend configuration...${NC}"

if grep -q "backend \"gcs\"" "$TF_DIR/main.tf"; then
  test_passed "GCS backend configured"
else
  test_failed "GCS backend not configured"
fi

# Test 10: Output validation
echo -e "\n${YELLOW}🔟 Testing output definitions...${NC}"

required_outputs=("deployment_summary" "cloud_run_outputs" "storage_outputs" "cloud_sql_outputs" "redis_outputs")
for output in "${required_outputs[@]}"; do
  if grep -q "output \"$output\"" "$TF_DIR/main.tf"; then
    test_passed "Output '$output' defined"
  else
    test_failed "Output '$output' missing"
  fi
done

# Summary
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}📊 Test Results Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Passed: $TESTS_PASSED${NC}"
echo -e "${RED}❌ Failed: $TESTS_FAILED${NC}"

# Save results
{
  echo "Test Results - Environment: $ENVIRONMENT"
  echo "Timestamp: $(date)"
  echo "Passed: $TESTS_PASSED"
  echo "Failed: $TESTS_FAILED"
} > "$TEST_RESULTS"

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "\n${GREEN}✅ All tests passed!${NC}"
  exit 0
else
  echo -e "\n${RED}❌ Some tests failed. See details above.${NC}"
  exit 1
fi
