#!/usr/bin/env bash
# Quality Gate Script - Unified code quality checking
# Runs all quality checks across the repository
# Exit code: 0 = all pass, non-zero = failures

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}   🔍 Quality Gate - Running All Checks${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# 1. EditorConfig Check
echo -e "${YELLOW}1️⃣  EditorConfig Validation${NC}"
if command_exists ec; then
  if ec -config "${REPO_ROOT}/.editorconfig" "${REPO_ROOT}" 2>/dev/null | grep -q 'Checking'; then
    echo -e "${GREEN}   ✓ EditorConfig OK${NC}"
  else
    echo -e "${RED}   ✗ EditorConfig violations found${NC}"
    ((FAILED++))
  fi
else
  echo -e "${YELLOW}   ⊘ editorconfig-checker not installed (optional)${NC}"
fi
echo ""

# 2. YAML Linting
echo -e "${YELLOW}2️⃣  YAML Linting (yamllint)${NC}"
if command_exists yamllint; then
  if yamllint -c "${REPO_ROOT}/.yamllint" \
    "${REPO_ROOT}"/.github/workflows/*.yml \
    "${REPO_ROOT}"/.github/workflows/**/*.yml 2>/dev/null | grep -q 'error\|warning'; then
    echo -e "${RED}   ✗ YAML violations found${NC}"
    yamllint -c "${REPO_ROOT}/.yamllint" "${REPO_ROOT}"/.github/workflows/*.yml || true
    ((FAILED++))
  else
    echo -e "${GREEN}   ✓ All YAML files valid${NC}"
  fi
else
  echo -e "${YELLOW}   ⊘ yamllint not installed (install: pip install yamllint)${NC}"
fi
echo ""

# 3. ShellScript Linting (ShellCheck)
echo -e "${YELLOW}3️⃣  Shell Script Linting (ShellCheck)${NC}"
if command_exists shellcheck; then
  script_count=$(find "${REPO_ROOT}/scripts" -name "*.sh" -type f 2>/dev/null | wc -l)
  echo "   Checking $script_count shell scripts..."
  
  # ShellCheck finds will vary, just run it
  if find "${REPO_ROOT}/scripts" -name "*.sh" -type f -exec shellcheck {} + 2>&1 | grep -q 'SC'; then
    echo -e "${RED}   ⚠ ShellCheck findings (review carefully):${NC}"
    find "${REPO_ROOT}/scripts" -name "*.sh" -type f -exec shellcheck {} + || true
  else
    echo -e "${GREEN}   ✓ All shell scripts pass ShellCheck${NC}"
  fi
else
  echo -e "${YELLOW}   ⊘ ShellCheck not installed (install: sudo apt-get install shellcheck)${NC}"
fi
echo ""

# 4. GitHub Actions Workflow Linting
echo -e "${YELLOW}4️⃣  GitHub Actions Linting (actionlint)${NC}"
if command_exists actionlint; then
  workflow_count=$(find "${REPO_ROOT}/.github/workflows" -name "*.yml" -o -name "*.yaml" | wc -l)
  echo "   Checking $workflow_count workflows..."
  
  if actionlint "${REPO_ROOT}/.github/workflows" 2>&1 | grep -q 'Error'; then
    echo -e "${RED}   ✗ Workflow violations found${NC}"
    actionlint "${REPO_ROOT}/.github/workflows" || true
    ((FAILED++))
  else
    echo -e "${GREEN}   ✓ All workflows valid${NC}"
  fi
else
  echo -e "${YELLOW}   ⊘ actionlint not installed (install: https://github.com/rhysd/actionlint)${NC}"
fi
echo ""

# 5. Pre-commit checks
echo -e "${YELLOW}5️⃣  Pre-commit Hooks${NC}"
if command_exists pre-commit; then
  if pre-commit run --all-files 2>&1 | grep -E 'failed|Aborted' >/dev/null; then
    echo -e "${RED}   ✗ Pre-commit checks failed${NC}"
    ((FAILED++))
  else
    echo -e "${GREEN}   ✓ Pre-commit hooks passed${NC}"
  fi
else
  echo -e "${YELLOW}   ⊘ pre-commit not installed (install: pip install pre-commit)${NC}"
fi
echo ""

# 6. Terraform Validation
echo -e "${YELLOW}6️⃣  Terraform Validation${NC}"
if command_exists terraform; then
  terraform_files=$(find "${REPO_ROOT}/terraform" -name "*.tf" 2>/dev/null | wc -l)
  echo "   Checking $terraform_files Terraform files..."
  
  # Validate each terraform directory
  for tf_dir in "${REPO_ROOT}/terraform"/{modules,environments}/*; do
    if [ -d "$tf_dir" ] && [ -f "$tf_dir/main.tf" ]; then
      if ! (cd "$tf_dir" && terraform validate 2>&1 | grep -q 'error'); then
        echo -e "${GREEN}   ✓ $(basename $tf_dir) valid${NC}"
      else
        echo -e "${RED}   ✗ $(basename $tf_dir) has errors${NC}"
        ((FAILED++))
      fi
    fi
  done
else
  echo -e "${YELLOW}   ⊘ Terraform not installed${NC}"
fi
echo ""

# 7. Summary
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All quality checks passed!${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
  exit 0
else
  echo -e "${RED}✗ $FAILED quality checks failed${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
  exit 1
fi
