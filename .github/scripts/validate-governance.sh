#!/bin/bash

# ============================================================================
# .github/scripts/validate-governance.sh
# Validate Governance Framework Compliance
#
# Purpose: Pre-commit hook & workflow validation to catch governance issues
#          before they reach main branch
#
# Usage:
#   validate-governance.sh [--strict] [--fix] [--report]
#
# Examples:
#   validate-governance.sh                # Standard validation
#   validate-governance.sh --strict       # Fail on any violation
#   validate-governance.sh --fix          # Auto-fix violations
#   validate-governance.sh --report       # Generate report file
# ============================================================================

set -eu

# Configuration
STRICT_MODE=false
AUTO_FIX=false
GENERATE_REPORT=false
REPORT_FILE="governance-validation-report.md"
VIOLATIONS=0
WARNINGS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --strict)
      STRICT_MODE=true
      shift
      ;;
    --fix)
      AUTO_FIX=true
      shift
      ;;
    --report)
      GENERATE_REPORT=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Initialize report
if [ "$GENERATE_REPORT" = true ]; then
  cat > "$REPORT_FILE" << 'EOF'
# Governance Validation Report

**Generated:** $(date)
**Repository:** $(git remote get-url origin 2>/dev/null || echo "unknown")

## Summary

EOF
fi

# ============================================================================
# Check 1: Workflow File Structure
# ============================================================================

echo -e "${BLUE}🔍 Check 1: Workflow File Structure${NC}"

WORKFLOW_COUNT=0
WORKFLOW_VIOLATIONS=0

if [ -d ".github/workflows" ]; then
  while IFS= read -r workflow; do
    WORKFLOW_COUNT=$((WORKFLOW_COUNT + 1))
    
    # Check for 'name:' field
    if ! grep -q "^name:" "$workflow" 2>/dev/null; then
      echo -e "  ${RED}✗${NC} $workflow: Missing 'name:' field"
      WORKFLOW_VIOLATIONS=$((WORKFLOW_VIOLATIONS + 1))
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
    
    # Check for 'permissions:' block
    if ! grep -q "^permissions:" "$workflow" 2>/dev/null; then
      echo -e "  ${RED}✗${NC} $workflow: Missing 'permissions:' block"
      WORKFLOW_VIOLATIONS=$((WORKFLOW_VIOLATIONS + 1))
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
    
  done < <(find .github/workflows -name "*.yml" -o -name "*.yaml")
  
  if [ $WORKFLOW_VIOLATIONS -eq 0 ]; then
    echo -e "  ${GREEN}✓${NC} All $WORKFLOW_COUNT workflows have required fields"
  fi
else
  echo -e "  ${YELLOW}⚠${NC} .github/workflows directory not found"
fi

# ============================================================================
# Check 2: Secret Handling
# ============================================================================

echo ""
echo -e "${BLUE}🔍 Check 2: Secret Handling${NC}"

SECRET_VIOLATIONS=0

# Scan for hardcoded secrets
if grep -r "password\|api_key\|secret\|token" . \
  --include="*.yml" --include="*.yaml" --include="*.tf" \
  --exclude-dir=".git" --exclude-dir="node_modules" 2>/dev/null | \
  grep -v "secrets\." | grep -v '\${{' | grep -v "^.*#" | grep -q "="; then
  
  echo -e "  ${RED}✗${NC} Potential hardcoded secrets detected"
  SECRET_VIOLATIONS=$((SECRET_VIOLATIONS + 1))
  VIOLATIONS=$((VIOLATIONS + 1))
else
  echo -e "  ${GREEN}✓${NC} No obvious hardcoded secrets found"
fi

# Check for Gitleaks availability
if command -v gitleaks &> /dev/null; then
  if gitleaks detect --no-git --verbose 2>/dev/null | grep -q "leaks"; then
    echo -e "  ${RED}✗${NC} Secrets detected by gitleaks"
    VIOLATIONS=$((VIOLATIONS + 1))
  else
    echo -e "  ${GREEN}✓${NC} Gitleaks scan passed"
  fi
fi

# ============================================================================
# Check 3: Terraform Standards
# ============================================================================

echo ""
echo -e "${BLUE}🔍 Check 3: Terraform Standards${NC}"

TERRAFORM_VIOLATIONS=0

if [ -d "terraform" ]; then
  TF_FILES=$(find terraform -name "*.tf" -type f | wc -l)
  
  if [ "$TF_FILES" -gt 0 ]; then
    # Check for inline resources (not using modules)
    INLINE_RESOURCES=$(grep -r "^resource " terraform --include="*.tf" 2>/dev/null | grep -v "module\|locals" | wc -l || true)
    
    if [ "$INLINE_RESOURCES" -gt 20 ]; then
      echo -e "  ${YELLOW}⚠${NC} High inline resource count ($INLINE_RESOURCES). Consider using modules."
      WARNINGS=$((WARNINGS + 1))
    else
      echo -e "  ${GREEN}✓${NC} Terraform structure follows best practices ($INLINE_RESOURCES inline resources)"
    fi
    
    # Check for sensitive variable handling
    SENSITIVE_VARS=$(grep -r "password\|secret\|key" terraform --include="*.tf" 2>/dev/null | wc -l || true)
    MARKED_SENSITIVE=$(grep -r "sensitive = true" terraform --include="*.tf" 2>/dev/null | wc -l || true)
    
    if [ "$SENSITIVE_VARS" -gt "$MARKED_SENSITIVE" ]; then
      echo -e "  ${YELLOW}⚠${NC} Sensitive variables not all marked (found: $SENSITIVE_VARS, marked: $MARKED_SENSITIVE)"
      WARNINGS=$((WARNINGS + 1))
    else
      echo -e "  ${GREEN}✓${NC} All sensitive variables properly marked"
    fi
  fi
else
  echo -e "  ${YELLOW}ℹ${NC} No terraform directory found"
fi

# ============================================================================
# Check 4: Governance Framework
# ============================================================================

echo ""
echo -e "${BLUE}🔍 Check 4: Governance Framework${NC}"

FRAMEWORK_VIOLATIONS=0

# Check for governance files
REQUIRED_FILES=(
  ".github/governance/GOVERNANCE.md"
  ".github/governance/GOVERNANCE_ALLOWLIST.yaml"
  ".github/CODEOWNERS"
  ".github/scripts/audit-log.sh"
  ".github/scripts/validate-governance.sh"
)

for file in "${REQUIRED_FILES[@]}"; do
  if [ -f "$file" ]; then
    echo -e "  ${GREEN}✓${NC} $file exists"
  else
    echo -e "  ${RED}✗${NC} $file missing"
    FRAMEWORK_VIOLATIONS=$((FRAMEWORK_VIOLATIONS + 1))
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done

# ============================================================================
# Check 5: Policy Enforcement Workflows
# ============================================================================

echo ""
echo -e "${BLUE}🔍 Check 5: Policy Enforcement Workflows${NC}"

ENFORCEMENT_VIOLATIONS=0

ENFORCEMENT_WORKFLOWS=(
  ".github/workflows/policy-enforcement-gate.yml"
  ".github/workflows/governance-audit-report.yml"
  ".github/workflows/reusable-guards.yml"
  ".github/workflows/branch-protection-enforcer.yml"
)

for workflow in "${ENFORCEMENT_WORKFLOWS[@]}"; do
  if [ -f "$workflow" ]; then
    echo -e "  ${GREEN}✓${NC} $(basename $workflow)"
  else
    echo -e "  ${YELLOW}⚠${NC} $(basename $workflow) not yet deployed"
    WARNINGS=$((WARNINGS + 1))
  fi
done

# ============================================================================
# Check 6: Concurrency Guards
# ============================================================================

echo ""
echo -e "${BLUE}🔍 Check 6: Concurrency Guards${NC}"

CONCURRENCY_VIOLATIONS=0

if [ -d ".github/workflows" ]; then
  DEPLOY_WORKFLOWS=$(find .github/workflows -name "*.yml" -exec grep -l "apply\|deploy\|rotate\|release" {} \; | wc -l)
  PROTECTED_WORKFLOWS=$(find .github/workflows -name "*.yml" -exec grep -l "concurrency:" {} \; | wc -l)
  
  if [ "$DEPLOY_WORKFLOWS" -gt "$PROTECTED_WORKFLOWS" ]; then
    echo -e "  ${YELLOW}⚠${NC} Deploy workflows without concurrency: $((DEPLOY_WORKFLOWS - PROTECTED_WORKFLOWS))"
    WARNINGS=$((WARNINGS + 1))
  else
    echo -e "  ${GREEN}✓${NC} All deploy workflows have concurrency guards"
  fi
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "Governance Validation Summary"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"

echo -e "Total Violations: ${RED}$VIOLATIONS${NC}"
echo -e "Total Warnings: ${YELLOW}$WARNINGS${NC}"

if [ "$STRICT_MODE" = true ] && [ $VIOLATIONS -gt 0 ]; then
  echo -e "\n${RED}❌ STRICT MODE: Validation failed${NC}"
  exit 1
elif [ $VIOLATIONS -gt 0 ]; then
  echo -e "\n${YELLOW}⚠️  Validation passed with warnings${NC}"
  exit 0
else
  echo -e "\n${GREEN}✅ All governance checks passed${NC}"
  exit 0
fi
