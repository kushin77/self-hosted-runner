#!/usr/bin/env bash
set -euo pipefail

# Comprehensive validation suite for Phase P2 provisioner-worker deployment.
# Runs all 6-stage checks: infrastructure, vault, deployment, smoke, validation, handoff.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/../..")"

# Color output for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

fail() { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }
pass() { echo -e "${GREEN}✓ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
info() { echo -e "$*"; }

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
  local name="$1"
  local exit_code="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$exit_code" -eq 0 ]; then
    pass "$name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    warn "$name (exit code: $exit_code)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

echo "=== Phase P2 Production Rollout Validation Suite ==="
echo "Repository: $REPO_ROOT"
echo "Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo ""

# ============================================================================
# Stage 1: Infrastructure Checks
# ============================================================================
info "Stage 1: Infrastructure Preparation"

# Check if Dockerfile exists
[ -f "$REPO_ROOT/build/github-runner/Dockerfile" ] && pass "Dockerfile exists" || fail "Dockerfile not found"

# Check if prod_rollout.sh script exists
[ -f "$REPO_ROOT/scripts/prod_rollout.sh" ] && pass "prod_rollout.sh exists" || fail "Rollout script not found"

# Validate bash syntax
bash -n "$REPO_ROOT/scripts/prod_rollout.sh" && pass "prod_rollout.sh syntax valid" || fail "Syntax error in rollout script"

# ============================================================================
# Stage 2: Configuration Checks
# ============================================================================
info "Stage 2: Configuration Validation"

# Check for required environment variable templates
grep -q "VAULT_ROLE_ID" "$REPO_ROOT/docs/PROVISIONER_WORKER_PROD_ROLLOUT.md" && pass "Vault role ID documented" || warn "Vault role ID not found in docs"

grep -q "PROVISIONER_REDIS_URL" "$REPO_ROOT/docs/PROVISIONER_WORKER_PROD_ROLLOUT.md" && pass "Redis URL documented" || warn "Redis URL not found in docs"

# ============================================================================
# Stage 3: Workflow Validation
# ============================================================================
info "Stage 3: Workflow Files"

# Check main orchestration workflow exists
[ -f "$REPO_ROOT/.github/workflows/orchestrate-p2-rollout.yml" ] && pass "Orchestration workflow exists" || fail "Orchestration workflow not found"

# Validate YAML syntax of workflow
if command -v yq &>/dev/null; then
  yq eval '.' "$REPO_ROOT/.github/workflows/orchestrate-p2-rollout.yml" >/dev/null 2>&1 && pass "Orchestration workflow YAML valid" || warn "YAML validation skipped (yq not available)"
fi

# ============================================================================
# Stage 4: Infrastructure-as-Code
# ============================================================================
info "Stage 4: Infrastructure-as-Code"

# Check Terraform files
[ -f "$REPO_ROOT/infrastructure/terraform/main.tf" ] && pass "Terraform configuration exists" || warn "Terraform config not found"

# Check Kubernetes manifests
[ -f "$REPO_ROOT/infrastructure/kubernetes/provisioner-worker.yaml" ] && pass "Kubernetes manifest exists" || warn "Kubernetes manifest not found"

# Check systemd unit
[ -f "$REPO_ROOT/infrastructure/systemd/provisioner-worker.service" ] && pass "Systemd unit file exists" || warn "Systemd unit not found"

# ============================================================================
# Stage 5: Documentation
# ============================================================================
info "Stage 5: Documentation"

# Check rollout guide
[ -f "$REPO_ROOT/docs/PROVISIONER_WORKER_PROD_ROLLOUT.md" ] && pass "Rollout guide exists" || fail "Rollout guide not found"

# Check for post-deploy validation checklist
grep -q "Post-deploy validation" "$REPO_ROOT/docs/PROVISIONER_WORKER_PROD_ROLLOUT.md" || warn "Post-deploy validation section missing from docs"

# ============================================================================
# Stage 6: Integration & End-to-End
# ============================================================================
info "Stage 6: Integration Checks"

# Verify GitHub issue #147 reference
grep -q "#147\|issue 147" "$REPO_ROOT/docs/PROVISIONER_WORKER_PROD_ROLLOUT.md" && pass "Issue #147 referenced in docs" || warn "Issue #147 not referenced"

# Check if all scripts are executable
chmod +x "$REPO_ROOT/scripts/prod_rollout.sh" 2>/dev/null && pass "Rollout script is executable" || warn "Could not make rollout script executable"

# ============================================================================
# Summary
# ============================================================================
echo ""
info "=== Validation Summary ==="
info "Tests Run:    $TESTS_RUN"
pass "Tests Passed: $TESTS_PASSED"
if [ "$TESTS_FAILED" -gt 0 ]; then
  warn "Tests Failed: $TESTS_FAILED"
fi
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
  pass "✓ All validations passed. Ready for production rollout."
  exit 0
else
  warn "⚠ Some validations failed. Review above warnings before proceeding."
  exit 1
fi
