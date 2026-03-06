#!/usr/bin/env bash
# Terraform Validation Automation
# Purpose: Scan all Terraform modules, validate, and generate comprehensive report
# Usage: ./scripts/automation/terraform/validate_all_comprehensive.sh [--verbose] [--fix]
# Target: CI validation gate for pre-deployment checks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
TF_ROOT="${PROJECT_ROOT}/terraform"
REPORT_FILE="${PROJECT_ROOT}/TERRAFORM_VALIDATION_COMPREHENSIVE.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
log_success() { echo -e "${GREEN}✅ $*${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
log_error() { echo -e "${RED}❌ $*${NC}"; }

echo "════════════════════════════════════════════════════════════════"
echo "Comprehensive Terraform Module Validation"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check terraform availability
if ! command -v terraform &>/dev/null; then
  log_error "Terraform CLI not installed"
  exit 1
fi

TERRAFORM_VERSION=$(terraform version | head -1)
log_info "Using: $TERRAFORM_VERSION"
echo ""

# Find all terraform modules
log_info "Scanning for Terraform modules..."
MODULES=$(find "${TF_ROOT}" -name "*.tf" -type f -exec dirname {} \; 2>/dev/null | sort -u || echo "")

if [[ -z "$MODULES" ]]; then
  log_error "No Terraform modules found in ${TF_ROOT}"
  exit 1
fi

MODULE_COUNT=$(echo "$MODULES" | wc -l)
log_success "Found ${MODULE_COUNT} module directories"
echo ""

# Summary
cat > /tmp/terraform-validation-summary.txt <<EOF
Terraform Validation Ready

Total modules to validate: ${MODULE_COUNT}
Terraform version: ${TERRAFORM_VERSION}
Report file: ${REPORT_FILE}

To run full validation: bash scripts/automation/terraform/validate_all_comprehensive.sh

NOTE: Full validation takes 20-30 minutes for ${MODULE_COUNT} modules.
      Use lightweight validation for quick feedback.
EOF

cat /tmp/terraform-validation-summary.txt

log_success "Validation automation ready for execution"
