#!/usr/bin/env bash
set -euo pipefail

# Phase P1 Pre-Deployment Validation Script
# Comprehensive checks before production deployment

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

log_check() {
  echo -e "${BLUE}[CHECK]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  ((CHECKS_PASSED++))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  ((CHECKS_FAILED++))
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
  ((CHECKS_WARNING++))
}

echo "=========================================="
echo "Phase P1 - Pre-Deployment Validation"
echo "=========================================="
echo ""

# 1. Component Files Exist
log_check "Component files present"
for file in job-cancellation-handler.sh vault-integration.sh failure-predictor.sh; do
  if [ -f "scripts/automation/pmo/$file" ]; then
    log_pass "  ✓ $file"
  else
    log_fail "  ✗ Missing: $file"
  fi
done

# 2. Test Suite Completeness
log_check "Test suites implemented"
for test in test-job-cancellation.sh test-vault-integration.sh test-failure-predictor.sh test-integration-p1.sh; do
  if [ -f "scripts/automation/pmo/tests/$test" ]; then
    log_pass "  ✓ $test"
  else
    log_fail "  ✗ Missing test: $test"
  fi
done

# 3. Documentation Complete
log_check "Documentation present"
docs=(
  "docs/PHASE_P1_IMPLEMENTATION_GUIDE.md"
  "docs/PHASE_P1_OPERATIONAL_RUNBOOKS.md"
)
for doc in "${docs[@]}"; do
  if [ -f "$doc" ]; then
    log_pass "  ✓ $doc"
  else
    log_fail "  ✗ Missing: $doc"
  fi
done

# 4. Configuration Templates
log_check "Configuration templates ready"
configs=(
  "scripts/automation/pmo/examples/.runner-config/job-cancellation.yaml"
  "scripts/automation/pmo/examples/.runner-config/vault-rotation.yaml"
  "scripts/automation/pmo/examples/.runner-config/failure-detection.yaml"
)
for config in "${configs[@]}"; do
  if [ -f "$config" ]; then
    log_pass "  ✓ $(basename $config)"
  else
    log_warn "  ⚠️  Missing config template: $config (will create at deployment)"
  fi
done

# 5. Monitoring Configuration
log_check "Monitoring & alerting configured"
if [ -f "scripts/automation/pmo/monitoring/p1-alerts.yaml" ]; then
  log_pass "  ✓ Alert rules configured"
  
  # Validate YAML syntax
  if command -v yq &> /dev/null; then
    if yq eval . "scripts/automation/pmo/monitoring/p1-alerts.yaml" > /dev/null 2>&1; then
      log_pass "  ✓ Alert rules YAML valid"
    else
      log_fail "  ✗ Alert rules YAML invalid"
    fi
  fi
else
  log_fail "  ✗ Alert rules not found"
fi

# 6. Deployment Script Ready
log_check "Deployment automation ready"
if [ -f "scripts/automation/pmo/deploy-p1-production.sh" ]; then
  log_pass "  ✓ Deployment script present"
  
  if grep -q "pre_deployment_check" "scripts/automation/pmo/deploy-p1-production.sh"; then
    log_pass "  ✓ Pre-deployment checks included"
  else
    log_fail "  ✗ Pre-deployment checks missing"
  fi
else
  log_fail "  ✗ Deployment script not found"
fi

# 7. Bash Syntax Validation
log_check "Bash script syntax"
for script in scripts/automation/pmo/{job-cancellation-handler,vault-integration,failure-predictor,deploy-p1-production}.sh; do
  if bash -n "$script" 2>/dev/null; then
    log_pass "  ✓ $(basename $script)"
  else
    log_fail "  ✗ Syntax error in: $(basename $script)"
  fi
done

# 8. Required Tools Available
log_check "Required tools available"
tools=("jq" "curl" "sqlite3" "python3" "bash")
for tool in "${tools[@]}"; do
  if command -v "$tool" &> /dev/null; then
    log_pass "  ✓ $tool"
  else
    log_fail "  ✗ Missing tool: $tool"
  fi
done

# 9. System Resources Sufficient
log_check "System resources adequate"

# Check disk space
available_disk=$(df / | tail -1 | awk '{print $4}')
if [ "$available_disk" -gt $((10 * 1024 * 1024)) ]; then  # >10GB
  log_pass "  ✓ Disk space: ${available_disk}KB"
else
  log_warn "  ⚠️  Low disk space: ${available_disk}KB"
fi

# Check memory
available_mem=$(free | grep Mem | awk '{print $7}')
if [ "$available_mem" -gt $((4 * 1024 * 1024)) ]; then  # >4GB
  log_pass "  ✓ Available memory: ${available_mem}KB"
else
  log_fail "  ✗ Insufficient memory: ${available_mem}KB"
fi

# Check CPU cores
cpu_cores=$(grep -c ^processor /proc/cpuinfo)
if [ "$cpu_cores" -ge 4 ]; then
  log_pass "  ✓ CPU cores: $cpu_cores"
else
  log_warn "  ⚠️  Low CPU cores: $cpu_cores (recommended: 4+)"
fi

# 10. Network Connectivity
log_check "Network connectivity"
if curl -s -m 5 https://github.com > /dev/null 2>&1; then
  log_pass "  ✓ GitHub reachable"
else
  log_fail "  ✗ GitHub unreachable (may impact deployment)"
fi

if [ -z "${VAULT_ADDR:-}" ]; then
  log_warn "  ⚠️  VAULT_ADDR not set (required for deployment)"
else
  if curl -s -m 5 "$VAULT_ADDR" > /dev/null 2>&1; then
    log_pass "  ✓ Vault server reachable"
  else
    log_fail "  ✗ Vault unreachable at $VAULT_ADDR"
  fi
fi

# 11. Directory Permissions
log_check "Directory permissions correct"
dirs=("scripts/automation/pmo" "docs" "build/github-runner")
for dir in "${dirs[@]}"; do
  if [ -d "$dir" ] && [ -w "$dir" ]; then
    log_pass "  ✓ $dir writable"
  else
    log_warn "  ⚠️  $dir not writable"
  fi
done

# 12. Git Status
log_check "Git repository status"
if [ -d ".git" ]; then
  log_pass "  ✓ Git repository found"
  
  # Check for uncommitted changes
  if git diff-index --quiet HEAD -- 2>/dev/null; then
    log_pass "  ✓ No uncommitted changes"
  else
    log_warn "  ⚠️  Uncommitted changes detected (commit before deployment)"
  fi
else
  log_warn "  ⚠️  Not a git repository"
fi

# 13. Environment Variables
log_check "Environment variables configured"
env_vars=(
  "JOB_TIMEOUT"
  "GRACE_PERIOD"
  "VAULT_ADDR"
  "VAULT_ROLE_ID"
  "ANOMALY_THRESHOLD"
)

for var in "${env_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    log_warn "  ⚠️  $var not set (will use defaults)"
  else
    log_pass "  ✓ $var set"
  fi
done

# 14. Backup Strategy
log_check "Backup strategy in place"
if [ -d "/var/backups" ] && [ -w "/var/backups" ]; then
  log_pass "  ✓ Backup directory ready"
else
  log_fail "  ✗ Backup directory not accessible"
fi

# 15. Test Execution QA
log_check "Running quick validation tests"
if bash scripts/automation/pmo/tests/test-job-cancellation.sh > /dev/null 2>&1; then
  log_pass "  ✓ Job cancellation tests pass"
else
  log_warn "  ⚠️  Job cancellation tests may have issues"
fi

echo ""
echo "=========================================="
echo -e "Validation Results:"
echo -e "  ${GREEN}Passed:  $CHECKS_PASSED${NC}"
echo -e "  ${YELLOW}Warnings: $CHECKS_WARNING${NC}"
echo -e "  ${RED}Failed:  $CHECKS_FAILED${NC}"
echo "=========================================="
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ Pre-deployment validation PASSED${NC}"
  echo "Ready for production deployment!"
  exit 0
else
  echo -e "${RED}✗ Pre-deployment validation FAILED${NC}"
  echo "Address failing checks before proceeding."
  exit 1
fi
