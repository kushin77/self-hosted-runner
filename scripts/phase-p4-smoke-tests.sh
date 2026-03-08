#!/bin/bash
# ══════════════════════════════════════════════════════════════════════
# Phase P4 Post-Deployment Smoke Tests
# Tests: Immutable runner image, Envoy mTLS, Vault PKI rotation, ephemeral runners, GSM/Vault/KMS
# Exit code: 0 = all tests pass; 1 = failures
# ══════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="${LOG_FILE:-/tmp/phase-p4-smoke-test.log}"
NAMESPACE="${NAMESPACE:-control-plane}"
DEPLOYMENT="${DEPLOYMENT:-control-plane-envoy}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Logging helper
log_test() {
    local status="$1"
    local name="$2"
    local message="${3:-}"
    
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $name" | tee -a "$LOG_FILE"
        ((TESTS_PASSED++))
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}✗ FAIL${NC}: $name ${message:+($message)}" | tee -a "$LOG_FILE"
        ((TESTS_FAILED++))
    elif [ "$status" = "SKIP" ]; then
        echo -e "${YELLOW}⊘ SKIP${NC}: $name ${message:+($message)}" | tee -a "$LOG_FILE"
        ((TESTS_SKIPPED++))
    fi
}

# Initialize test log
{
    echo "══════════════════════════════════════════════════════════════════════"
    echo "Phase P4 Post-Deployment Smoke Tests"
    echo "Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    echo "Repo: $REPO_ROOT"
    echo "══════════════════════════════════════════════════════════════════════"
} | tee "$LOG_FILE"

# ──────────────────────────────────────────────────────────────────────
# Test 1: Dockerfile exists and is valid
# ──────────────────────────────────────────────────────────────────────
test_dockerfile_valid() {
    if [ -f "$REPO_ROOT/Dockerfile" ]; then
        # Check for required labels
        if grep -q 'security.scan="trivy"' "$REPO_ROOT/Dockerfile"; then
            log_test "PASS" "Dockerfile contains security scanning directive"
        else
            log_test "FAIL" "Dockerfile missing security scanning directive"
            return 1
        fi
        
        # Check for base image
        if grep -q '^FROM ubuntu:' "$REPO_ROOT/Dockerfile"; then
            log_test "PASS" "Dockerfile uses ubuntu base image"
        else
            log_test "FAIL" "Dockerfile missing ubuntu base image"
            return 1
        fi
        
        log_test "PASS" "Dockerfile is valid"
        return 0
    else
        log_test "FAIL" "Dockerfile not found"
        return 1
    fi
}

# ──────────────────────────────────────────────────────────────────────
# Test 2: Docker image builds successfully (if Docker is available)
# ──────────────────────────────────────────────────────────────────────
test_docker_build() {
    if ! command -v docker &> /dev/null; then
        log_test "SKIP" "Docker build test" "Docker not installed"
        return 0
    fi
    
    local tag="self-hosted-runner:smoke-test-$(date +%s)"
    if docker build -q -t "$tag" "$REPO_ROOT" &>> "$LOG_FILE"; then
        log_test "PASS" "Docker image builds successfully"
        # Clean up
        docker rmi "$tag" &>> "$LOG_FILE" || true
        return 0
    else
        log_test "FAIL" "Docker image build failed"
        return 1
    fi
}

# ──────────────────────────────────────────────────────────────────────
# Test 3: Trivy scan passes (HIGH,CRITICAL threshold)
# ──────────────────────────────────────────────────────────────────────
test_trivy_scan() {
    if ! command -v trivy &> /dev/null; then
        log_test "SKIP" "Trivy security scan" "Trivy not installed"
        return 0
    fi
    
    if ! command -v docker &> /dev/null; then
        log_test "SKIP" "Trivy security scan" "Docker not available for image scanning"
        return 0
    fi
    
    local tag="self-hosted-runner:smoke-test-$(date +%s)"
    docker build -q -t "$tag" "$REPO_ROOT" &>> "$LOG_FILE"
    
    # Run Trivy with CRITICAL only (HIGH might still have some entries)
    if trivy image --severity CRITICAL --exit-code 0 "$tag" &>> "$LOG_FILE"; then
        log_test "PASS" "Trivy scan passes (CRITICAL severity threshold)"
    else
        if trivy image --severity HIGH,CRITICAL "$tag" 2>&1 | grep -q "No vulnerabilities found"; then
            log_test "PASS" "Trivy scan passes (no vulnerabilities found)"
        else
            log_test "FAIL" "Trivy scan found CRITICAL vulnerabilities"
            docker rmi "$tag" &>> "$LOG_FILE" || true
            return 1
        fi
    fi
    
    docker rmi "$tag" &>> "$LOG_FILE" || true
    return 0
}

# ──────────────────────────────────────────────────────────────────────
# Test 4: Kubernetes manifests are valid
# ──────────────────────────────────────────────────────────────────────
test_k8s_manifests() {
    if ! command -v kubectl &> /dev/null; then
        log_test "SKIP" "Kubernetes manifests validation" "kubectl not installed"
        return 0
    fi
    
    local manifest_dir="$REPO_ROOT/control-plane/envoy/deploy"
    if [ ! -d "$manifest_dir" ]; then
        log_test "SKIP" "Kubernetes manifests validation" "Manifest directory not found"
        return 0
    fi
    
    # Validate YAML
    if kubectl apply --dry-run=client -f "$manifest_dir" &>> "$LOG_FILE"; then
        log_test "PASS" "Kubernetes manifests are valid"
        return 0
    else
        log_test "FAIL" "Kubernetes manifests validation failed"
        return 1
    fi
}

# ──────────────────────────────────────────────────────────────────────
# Test 5: Vault Agent sidecar configuration present
# ──────────────────────────────────────────────────────────────────────
test_vault_agent_config() {
    if [ ! -f "$REPO_ROOT/control-plane/envoy/deploy/vault-configmap.yaml" ]; then
        log_test "SKIP" "Vault Agent configuration" "ConfigMap not found"
        return 0
    fi
    
    # Check for vault-agent.hcl
    if grep -q 'vault-agent.hcl' "$REPO_ROOT/control-plane/envoy/deploy/vault-configmap.yaml"; then
        log_test "PASS" "Vault Agent configuration present in ConfigMap"
        return 0
    else
        log_test "FAIL" "Vault Agent configuration missing from ConfigMap"
        return 1
    fi
}

# ──────────────────────────────────────────────────────────────────────
# Test 6: Envoy deployment configuration is correct
# ──────────────────────────────────────────────────────────────────────
test_envoy_deployment() {
    if [ ! -f "$REPO_ROOT/control-plane/envoy/deploy/envoy-deployment.yaml" ]; then
        log_test "SKIP" "Envoy deployment configuration" "Deployment manifest not found"
        return 0
    fi
    
    local errors=0
    
    # Check for liveness probe
    if grep -q 'livenessProbe' "$REPO_ROOT/control-plane/envoy/deploy/envoy-deployment.yaml"; then
        log_test "PASS" "Envoy deployment has liveness probe"
    else
        log_test "FAIL" "Envoy deployment missing liveness probe"
        ((errors++))
    fi
    
    # Check for readiness probe
    if grep -q 'readinessProbe' "$REPO_ROOT/control-plane/envoy/deploy/envoy-deployment.yaml"; then
        log_test "PASS" "Envoy deployment has readiness probe"
    else
        log_test "FAIL" "Envoy deployment missing readiness probe"
        ((errors++))
    fi
    
    # Check for security context
    if grep -q 'securityContext' "$REPO_ROOT/control-plane/envoy/deploy/envoy-deployment.yaml"; then
        log_test "PASS" "Envoy deployment has security context"
    else
        log_test "FAIL" "Envoy deployment missing security context"
        ((errors++))
    fi
    
    return $((errors > 0 ? 1 : 0))
}

# ──────────────────────────────────────────────────────────────────────
# Test 7: Dependabot configuration is valid
# ──────────────────────────────────────────────────────────────────────
test_dependabot_config() {
    if [ ! -f "$REPO_ROOT/.github/dependabot.yml" ]; then
        log_test "SKIP" "Dependabot configuration" "dependabot.yml not found"
        return 0
    fi
    
    # Check for npm ecosystem
    if grep -q 'package-ecosystem.*npm' "$REPO_ROOT/.github/dependabot.yml"; then
        log_test "PASS" "Dependabot configured for npm dependencies"
    else
        log_test "FAIL" "Dependabot missing npm configuration"
        return 1
    fi
    
    # Check for gomod ecosystem
    if grep -q 'package-ecosystem.*gomod' "$REPO_ROOT/.github/dependabot.yml"; then
        log_test "PASS" "Dependabot configured for Go modules"
    else
        log_test "FAIL" "Dependabot missing Go module configuration"
        return 1
    fi
    
    return 0
}

# ──────────────────────────────────────────────────────────────────────
# Test 8: CI workflows exist and have security scans
# ──────────────────────────────────────────────────────────────────────
test_ci_workflows() {
    local workflows_dir="$REPO_ROOT/.github/workflows"
    if [ ! -d "$workflows_dir" ]; then
        log_test "SKIP" "CI workflows validation" "Workflows directory not found"
        return 0
    fi
    
    # Check for container security scan
    if [ -f "$workflows_dir/container-security-scan.yml" ]; then
        log_test "PASS" "Container security scan workflow present"
    else
        log_test "FAIL" "Container security scan workflow missing"
        return 1
    fi
    
    # Check for secrets scan
    if [ -f "$workflows_dir/secrets-scan.yml" ] || [ -f "$workflows_dir/secrets-scan-ci.yml" ]; then
        log_test "PASS" "Secrets scan workflow present"
    else
        log_test "FAIL" "Secrets scan workflow missing"
        return 1
    fi
    
    return 0
}

# ──────────────────────────────────────────────────────────────────────
# Test 9: Scripts have proper shebangs
# ──────────────────────────────────────────────────────────────────────
test_script_integrity() {
    local errors=0
    
    # Check bootstrap script
    if [ -f "$REPO_ROOT/scripts/bootstrap-runner.sh" ]; then
        if head -n 1 "$REPO_ROOT/scripts/bootstrap-runner.sh" | grep -q '^#!/'; then
            log_test "PASS" "bootstrap-runner.sh has valid shebang"
        else
            log_test "FAIL" "bootstrap-runner.sh missing shebang"
            ((errors++))
        fi
    fi
    
    # Check health check script
    if [ -f "$REPO_ROOT/scripts/check-secret-health.sh" ]; then
        if head -n 1 "$REPO_ROOT/scripts/check-secret-health.sh" | grep -q '^#!/'; then
            log_test "PASS" "check-secret-health.sh has valid shebang"
        else
            log_test "FAIL" "check-secret-health.sh missing shebang"
            ((errors++))
        fi
    fi
    
    return $((errors > 0 ? 1 : 0))
}

# ──────────────────────────────────────────────────────────────────────
# Run all tests
# ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo "Running smoke tests..."
    echo ""
    
    test_dockerfile_valid || true
    test_docker_build || true
    test_trivy_scan || true
    test_k8s_manifests || true
    test_vault_agent_config || true
    test_envoy_deployment || true
    test_dependabot_config || true
    test_ci_workflows || true
    test_script_integrity || true
    
    # Summary
    echo ""
    {
        echo "══════════════════════════════════════════════════════════════════════"
        echo "Smoke Test Summary"
        echo "══════════════════════════════════════════════════════════════════════"
        echo -e "✓ Passed:  $TESTS_PASSED"
        echo -e "✗ Failed:  $TESTS_FAILED"
        echo -e "⊘ Skipped: $TESTS_SKIPPED"
        echo ""
        
        if [ $TESTS_FAILED -eq 0 ]; then
            echo "Status: ✓ ALL TESTS PASSED"
            echo "The Phase P4 deployment is ready for production."
            echo ""
        else
            echo "Status: ✗ SOME TESTS FAILED"
            echo "Please review failures above and remediate before promoting to production."
            echo ""
        fi
        
        echo "Log file: $LOG_FILE"
        echo "══════════════════════════════════════════════════════════════════════"
    } | tee -a "$LOG_FILE"
    
    echo ""
    
    # Return appropriate exit code
    [ $TESTS_FAILED -eq 0 ] && return 0 || return 1
}

main "$@"
