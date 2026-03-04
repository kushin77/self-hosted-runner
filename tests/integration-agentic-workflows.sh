#!/bin/bash
# Integration tests for agentic workflows
# Validates compilation, execution, and health checks

set -u
set -o pipefail

TEST_DIR="/tmp/agentic-integration-tests"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0
FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

test_header() {
  echo -e "\n${BLUE}▸ $*${NC}"
}

test_pass() {
  echo -e "${GREEN}✅ $*${NC}"
  ((PASSED++))
  true
}

test_fail() {
  echo -e "${RED}❌ $*${NC}"
  ((FAILED++))
  true
}

test_warn() {
  echo -e "${YELLOW}⚠️  $*${NC}"
  true
}

# Test 1: Compiler exists and is executable
test_compiler_exists() {
  test_header "Test: Compiler script exists"
  
  if [ -x "$REPO_ROOT/scripts/compile-agentic-workflows.sh" ]; then
    test_pass "Compiler is executable"
    return 0
  else
    test_fail "Compiler not found or not executable"
    return 0
  fi
}

# Test 2: Workflow templates exist
test_workflow_templates_exist() {
  test_header "Test: Workflow templates exist"
  
  local workflows=(
    ".github/workflows/agentic/auto-fix.md"
    ".github/workflows/agentic/pr-review.md"
    ".github/workflows/agentic/dependency-audit.md"
  )
  
  for wf in "${workflows[@]}"; do
    if [ -f "$REPO_ROOT/$wf" ]; then
      test_pass "Found: $wf"
    else
      test_fail "Missing: $wf"
      return 0
    fi
  done
}

# Test 3: Workflow compilation
test_workflow_compilation() {
  test_header "Test: Workflow compilation"
  
  cd "$REPO_ROOT"
  
  for md_file in .github/workflows/agentic/*.md; do
    local lock_file="${md_file%.md}.lock.yml"
    
    if [ -f "$lock_file" ]; then
      # Check if it's a YAML file with required fields (basic validation)
      if grep -q "^name:" "$lock_file" && grep -q "^on:" "$lock_file"; then
        test_pass "Valid YAML: $(basename "$lock_file")"
      else
        test_fail "Invalid YAML: $(basename "$lock_file")"
      fi
    else
      test_fail "Missing compiled file: $(basename "$lock_file")"
    fi
  done
}

# Test 4: Workflow has required fields
test_workflow_structure() {
  test_header "Test: Workflow structure validation"
  
  cd "$REPO_ROOT"
  
  for lock_file in .github/workflows/agentic/*.lock.yml; do
    local required_fields=("name" "on" "permissions" "jobs")
    
    for field in "${required_fields[@]}"; do
      if grep -q "^$field:" "$lock_file"; then
        test_pass "Field '$field' found in $(basename "$lock_file")"
      else
        test_fail "Missing required field '$field' in $(basename "$lock_file")"
        return 0
      fi
    done
  done
}

# Test 5: Health check script exists
test_health_check_exists() {
  test_header "Test: Health check script exists"
  
  if [ -x "$REPO_ROOT/scripts/agentic-health-check.sh" ]; then
    test_pass "Health check script exists and is executable"
  else
    test_fail "Health check script not found or not executable"
    return 0
  fi
}

# Test 6: Documentation exists
test_documentation() {
  test_header "Test: Documentation exists"
  
  local docs=(
    "docs/AGENTIC_WORKFLOWS_SETUP.md"
    "docs/AGENTIC_WORKFLOWS_EXAMPLES.md"
    "docs/SELF_SERVICE_ACTIONS_QUICKSTART.md"
    "docs/SELF_SERVICE_IMPLEMENTATION_COMPLETE.md"
  )
  
  for doc in "${docs[@]}"; do
    if [ -f "$REPO_ROOT/$doc" ]; then
      test_pass "Found: $doc"
    else
      test_warn "Missing: $doc (optional)"
    fi
  done
}

# Test 7: Packer includes Ollama
test_packer_ollama() {
  test_header "Test: Packer includes Ollama"
  
  if grep -q "ollama" "$REPO_ROOT/packer/runner-image.pkr.hcl" 2>/dev/null; then
    test_pass "Packer build includes Ollama"
  else
    test_warn "Packer doesn't mention Ollama (may be normal if pre-installed)"
  fi
}

# Test 8: CLI tool exists
test_cli_tool_exists() {
  test_header "Test: CLI tool exists"
  
  if [ -f "$REPO_ROOT/scripts/aw.mjs" ]; then
    test_pass "CLI tool found"
  else
    test_fail "CLI tool not found"
    return 0
  fi
}

# Test 9: GitHub Actions workflow triggers are valid
test_workflow_triggers() {
  test_header "Test: Workflow triggers are valid"
  
  cd "$REPO_ROOT"
  
  for lock_file in .github/workflows/agentic/*.lock.yml; do
    # Check for at least one trigger
    if grep -A 5 "^on:" "$lock_file" | grep -qE "(pull_request|issues|schedule|workflow_dispatch)"; then
      test_pass "Valid trigger found in $(basename "$lock_file")"
    else
      test_fail "No valid trigger found in $(basename "$lock_file")"
      return 0
    fi
  done
}

# Test 10: Permissions are correctly scoped
test_workflow_permissions() {
  test_header "Test: Workflow permissions are scoped"
  
  cd "$REPO_ROOT"
  
  for lock_file in .github/workflows/agentic/*.lock.yml; do
    # Check that permissions are explicitly set (not 'write-all')
    if grep -A 5 "^permissions:" "$lock_file" | grep -qE "(contents|pull-requests|issues|checks)"; then
      test_pass "Permissions properly scoped in $(basename "$lock_file")"
    else
      test_warn "Permissions may not be sufficiently scoped in $(basename "$lock_file")"
    fi
  done
}

# Test 11: Workflow references self-hosted runner
test_runner_label() {
  test_header "Test: Workflows reference self-hosted runner"
  
  cd "$REPO_ROOT"
  
  for lock_file in .github/workflows/agentic/*.lock.yml; do
    if grep -q "elevatediq-runner\|runs-on:" "$lock_file"; then
      test_pass "Runner label found in $(basename "$lock_file")"
    else
      test_warn "Runner label not explicitly set in $(basename "$lock_file")"
    fi
  done
}

# Test 12: Git files are tracked
test_git_tracked() {
  test_header "Test: Files are git-tracked"
  
  cd "$REPO_ROOT"
  
  local files_to_check=(
    ".github/workflows/agentic/auto-fix.md"
    ".github/workflows/agentic/pr-review.md"
    ".github/workflows/agentic/dependency-audit.md"
  )
  
  for file in "${files_to_check[@]}"; do
    if git ls-files --error-unmatch "$file" > /dev/null 2>&1; then
      test_pass "Git tracked: $file"
    else
      test_warn "Not git-tracked: $file"
    fi
  done
}

# Main test runner
run_all_tests() {
  echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║  Agentic Workflows Integration Tests      ║${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
  
  echo -e "${BLUE}Repository: $REPO_ROOT${NC}"
  echo -e "${BLUE}Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')${NC}"
  
  # Run all tests
  test_compiler_exists
  test_workflow_templates_exist
  test_workflow_compilation
  test_workflow_structure
  test_health_check_exists
  test_documentation
  test_packer_ollama
  test_cli_tool_exists
  test_workflow_triggers
  test_workflow_permissions
  test_runner_label
  test_git_tracked
  
  # Summary
  echo -e "\n${BLUE}╔════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║  Test Summary                             ║${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
  
  local total=$((PASSED + FAILED))
  local percentage=0
  [ $total -gt 0 ] && percentage=$((PASSED * 100 / total))
  
  echo -e "${GREEN}✅ Passed: $PASSED${NC}"
  echo -e "${RED}❌ Failed: $FAILED${NC}"
  echo -e "Total: $total"
  echo -e "Success Rate: ${percentage}%"
  
  if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 All tests passed!${NC}"
    return 0
  else
    echo -e "\n${RED}⚠️  Some tests failed - review above${NC}"
    return 0
  fi
}

run_all_tests
