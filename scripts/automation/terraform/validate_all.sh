#!/usr/bin/env bash
# Terraform Module Validation Script
# Purpose: Scan all Terraform modules, validate syntax, check providers, and generate report
# Usage: ./scripts/automation/terraform/validate_all.sh [--verbose] [--fix-mode]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
TF_ROOT="${PROJECT_ROOT}/terraform"
REPORT_FILE="${PROJECT_ROOT}/terraform-validation-report.json"
VERBOSE=${VERBOSE:=0}
FIX_MODE=${FIX_MODE:=0}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
TOTAL=0
VALID=0
INVALID=0
INIT_FAIL=0
PROVIDERS_MISSING=0

# Arrays for detailed reporting
declare -a VALID_MODULES
declare -a INVALID_MODULES
declare -a INIT_FAIL_MODULES
declare -a PROVIDER_ISSUES

echo "🔍 Terraform Module Validation"
echo "========================================"
echo "Root: ${TF_ROOT}"
echo "Report: ${REPORT_FILE}"
echo ""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose)
      VERBOSE=1
      shift
      ;;
    --fix-mode)
      FIX_MODE=1
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Find all terraform modules (directories containing .tf files)
find_terraform_modules() {
  local root_dir="$1"
  find "${root_dir}" -name "*.tf" -type f | while read -r tf_file; do
    dirname "${tf_file}"
  done | sort -u
}

# Validate a single module
validate_module() {
  local module_path="$1"
  local module_name="${module_path#${TF_ROOT}/}"
  
  ((TOTAL++))
  
  echo -n "📦 ${module_name} ... "
  
  # Check if directory is empty or has no .tf files
  if ! ls "${module_path}"/*.tf >/dev/null 2>&1; then
    echo -e "${YELLOW}SKIP (no .tf files)${NC}"
    return 0
  fi
  
  # Try terraform init -backend=false first (doesn't require backend config)
  if ! terraform -chdir="${module_path}" init -backend=false >/dev/null 2>&1; then
    echo -e "${RED}INIT_FAIL${NC}"
    INIT_FAIL_MODULES+=("${module_name}")
    ((INIT_FAIL++))
    
    if [[ ${VERBOSE} -eq 1 ]]; then
      terraform -chdir="${module_path}" init -backend=false 2>&1 | sed 's/^/  ERROR: /'
    fi
    return 1
  fi
  
  # Run terraform validate
  if ! terraform -chdir="${module_path}" validate >/dev/null 2>&1; then
    echo -e "${RED}INVALID${NC}"
    INVALID_MODULES+=("${module_name}")
    ((INVALID++))
    
    if [[ ${VERBOSE} -eq 1 ]]; then
      terraform -chdir="${module_path}" validate 2>&1 | sed 's/^/  ERROR: /'
    fi
    return 1
  fi
  
  # Check provider requirements
  if grep -q "required_providers" "${module_path}/main.tf" "${module_path}/versions.tf" 2>/dev/null; then
    echo -e "${GREEN}OK (with providers)${NC}"
    VALID_MODULES+=("${module_name}")
    ((VALID++))
  else
    echo -e "${GREEN}OK${NC}"
    VALID_MODULES+=("${module_name}")
    ((VALID++))
  fi
}

# Generate JSON report
generate_report() {
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  cat > "${REPORT_FILE}" <<EOF
{
  "timestamp": "${timestamp}",
  "summary": {
    "total": ${TOTAL},
    "valid": ${VALID},
    "invalid": ${INVALID},
    "init_failures": ${INIT_FAIL}
  },
  "valid_modules": [
EOF

  for module in "${VALID_MODULES[@]}"; do
    echo "    \"${module}\"," >> "${REPORT_FILE}"
  done
  
  # Remove trailing comma from last item
  sed -i '$ s/,$//' "${REPORT_FILE}"
  
  cat >> "${REPORT_FILE}" <<EOF
  ],
  "invalid_modules": [
EOF

  for module in "${INVALID_MODULES[@]}"; do
    echo "    \"${module}\"," >> "${REPORT_FILE}"
  done
  
  # Remove trailing comma if exists
  sed -i '$ s/,$//' "${REPORT_FILE}"
  
  cat >> "${REPORT_FILE}" <<EOF
  ],
  "init_failures": [
EOF

  for module in "${INIT_FAIL_MODULES[@]}"; do
    echo "    \"${module}\"," >> "${REPORT_FILE}"
  done
  
  # Remove trailing comma if exists
  sed -i '$ s/,$//' "${REPORT_FILE}"
  
  cat >> "${REPORT_FILE}" <<EOF
  ]
}
EOF
}

# Main validation loop
echo "Scanning modules..."
modules=$(find_terraform_modules "${TF_ROOT}")
for module in ${modules}; do
  validate_module "${module}"
done

echo ""
echo "========================================"
echo "📊 Validation Summary"
echo "========================================"
printf "Total modules: %d\n" "${TOTAL}"
printf "Valid: %d\n" "${VALID}"
printf "Invalid: %d\n" "${INVALID}"
printf "Init failures: %d\n" "${INIT_FAIL}"
echo ""

# Generate report
generate_report
echo "✅ Report written to: ${REPORT_FILE}"

# Determine exit code
if [[ ${INVALID} -gt 0 ]] || [[ ${INIT_FAIL} -gt 0 ]]; then
  echo ""
  echo -e "${RED}❌ Validation FAILED${NC}"
  echo ""
  echo "Next steps:"
  echo "1. Review invalid modules above"
  echo "2. Run: terraform validate -no-color in the failing module directory"
  echo "3. Fix syntax errors, missing variables, or provider constraints"
  echo "4. Re-run this script to verify fixes"
  exit 2
else
  echo ""
  echo -e "${GREEN}✅ All modules VALID${NC}"
  exit 0
fi
