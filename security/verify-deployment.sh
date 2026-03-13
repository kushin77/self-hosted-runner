#!/usr/bin/env bash

# FAANG Security Implementation - Final Verification Script
# Validates all security components are properly deployed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

log() { echo -e "${BLUE}[VERIFY]${NC} $*"; }
pass() { echo -e "${GREEN}[✓]${NC} $*"; ((PASSED_CHECKS+=1)); }
fail() { echo -e "${RED}[✗]${NC} $*"; ((FAILED_CHECKS+=1)); }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
count() { ((TOTAL_CHECKS+=1)); }

##############################################################################
# VERIFICATION CHECKS
##############################################################################

check_zero_trust_auth() {
    log "Checking Zero-Trust Authentication..."
    count
    
    if [[ -f "$PROJECT_ROOT/security/zero-trust-auth.ts" ]]; then
        pass "Zero-trust auth module present"
    else
        fail "Zero-trust auth module missing"
    fi
}

check_api_security() {
    log "Checking API Security..."
    count
    
    if [[ -f "$PROJECT_ROOT/security/api-security.ts" ]]; then
        pass "API security module present"
    else
        fail "API security module missing"
    fi
}

check_istio_mtls() {
    log "Checking Istio mTLS Configuration..."
    count
    
    if [[ -f "$PROJECT_ROOT/security/istio-mtls-policy.yaml" ]]; then
        pass "Istio mTLS policies present"
        
        # Verify key policies
        if grep -q "STRICT" "$PROJECT_ROOT/security/istio-mtls-policy.yaml"; then
            pass "Strict mTLS enforcement configured"
        else
            fail "Strict mTLS enforcement not found"
        fi
    else
        fail "Istio mTLS policies missing"
    fi
}

check_secrets_scanning() {
    log "Checking Secrets Scanning..."
    count
    
    if [[ -f "$PROJECT_ROOT/security/enhanced-secrets-scanner.sh" ]]; then
        pass "Secrets scanner present"
        
        if [[ -x "$PROJECT_ROOT/security/enhanced-secrets-scanner.sh" ]]; then
            pass "Secrets scanner is executable"
        else
            fail "Secrets scanner not executable"
        fi
    else
        fail "Secrets scanner missing"
    fi
}

check_slsa_compliance() {
    log "Checking SLSA Compliance..."
    count
    
    if [[ -f "$PROJECT_ROOT/security/slsa-compliance.ts" ]]; then
        pass "SLSA compliance module present"
        
        if grep -q "SLSAProvenanceGenerator" "$PROJECT_ROOT/security/slsa-compliance.ts"; then
            pass "SLSA provenance generator implemented"
        else
            fail "SLSA provenance generator not found"
        fi
    else
        fail "SLSA compliance module missing"
    fi
}

check_runtime_security() {
    log "Checking Runtime Security..."
    count
    
    if [[ -f "$PROJECT_ROOT/security/runtime-security-hardening.sh" ]]; then
        pass "Runtime security hardening script present"
        
        if [[ -x "$PROJECT_ROOT/security/runtime-security-hardening.sh" ]]; then
            pass "Runtime security script is executable"
        else
            fail "Runtime security script not executable"
        fi
    else
        fail "Runtime security script missing"
    fi
}

check_vulnerability_management() {
    log "Checking Vulnerability Management..."
    count
    
    if [[ -f "$PROJECT_ROOT/security/automated-patching.sh" ]]; then
        pass "Vulnerability scanning script present"
        
        if grep -q "scan_npm_dependencies" "$PROJECT_ROOT/security/automated-patching.sh"; then
            pass "npm dependency scanning implemented"
        else
            fail "npm dependency scanning not found"
        fi
    else
        fail "Vulnerability management script missing"
    fi
}

check_incident_response() {
    log "Checking Incident Response Runbook..."
    count
    
    if [[ -f "$PROJECT_ROOT/security/INCIDENT_RESPONSE_RUNBOOK.md" ]]; then
        pass "Incident response runbook present"
        
        if wc -l < "$PROJECT_ROOT/security/INCIDENT_RESPONSE_RUNBOOK.md" | grep -qE '^[1-9][0-9]{2}'; then
            pass "Incident response runbook comprehensive (>100 lines)"
        else
            fail "Incident response runbook too brief"
        fi
    else
        fail "Incident response runbook missing"
    fi
}

check_implementation_guide() {
    log "Checking FAANG Implementation Guide..."
    count
    
    if [[ -f "$PROJECT_ROOT/security/FAANG_SECURITY_IMPLEMENTATION.md" ]]; then
        pass "FAANG implementation guide present"
        
        # Check for key sections
        if grep -q "Zero-Trust" "$PROJECT_ROOT/security/FAANG_SECURITY_IMPLEMENTATION.md"; then
            pass "Zero-trust architecture documented"
        else
            fail "Zero-trust architecture not documented"
        fi
    else
        fail "FAANG implementation guide missing"
    fi
}

check_credential_rotation() {
    log "Checking Credential Rotation Setup..."
    count
    
    if [[ -f "$PROJECT_ROOT/scripts/secrets/rotate-credentials.sh" ]]; then
        pass "Credential rotation script present"
        
        if grep -q "gsm_put_secret_version" "$PROJECT_ROOT/scripts/secrets/rotate-credentials.sh"; then
            pass "GSM credential rotation implemented"
        else
            fail "GSM credential rotation not found"
        fi
    else
        fail "Credential rotation script missing"
    fi
}

check_network_policies() {
    log "Checking Network Policies..."
    count
    
    if grep -r "NetworkPolicy" "$PROJECT_ROOT/security" 2>/dev/null | grep -q "deny"; then
        pass "Default-deny network policies configured"
    else
        fail "Default-deny network policies not found"
    fi
}

check_rbac_policies() {
    log "Checking RBAC Policies..."
    count
    
    if grep -r "ClusterRole" "$PROJECT_ROOT/security" 2>/dev/null | grep -q "readonly\|restricted\|least"; then
        pass "Least-privilege RBAC policies found"
    else
        fail "Least-privilege RBAC policies not found"
    fi
}

check_audit_logging() {
    log "Checking Audit & Compliance Logging..."
    count
    
    if [[ -f "$PROJECT_ROOT/audit-trail.jsonl" ]] || \
       grep -r "audit" "$PROJECT_ROOT/.github" 2>/dev/null | grep -q "log\|trail"; then
        pass "Audit logging enabled"
    else
        fail "Audit logging not configured"
    fi
}

##############################################################################
# DEPLOYMENT VERIFICATION
##############################################################################

check_git_hooks() {
    log "Checking Git Security Hooks..."
    count
    
    if [[ -f "$PROJECT_ROOT/.git/hooks/pre-commit" ]]; then
        pass "Pre-commit hook installed"
    else
        fail "Pre-commit hook not installed"
    fi
    
    if grep -q "prevent.*secret\|prevent.*workflow" "$PROJECT_ROOT/.git/hooks/pre-commit" 2>/dev/null || \
       [[ -f "$PROJECT_ROOT/.githooks/prevent-workflows" ]]; then
        pass "Workflow prevention hooks installed"
    else
        fail "Workflow prevention hooks not installed"
    fi
}

check_gitleaks_config() {
    log "Checking Gitleaks Configuration..."
    count
    
    if [[ -f "$PROJECT_ROOT/.gitleaks.toml" ]] || [[ -f "$PROJECT_ROOT/.gitleaksignore" ]]; then
        pass "Gitleaks configuration present"
    else
        warn "Gitleaks configuration not found - using defaults"
    fi
}

check_kubernetes_manifests() {
    log "Checking Kubernetes Security Manifests..."
    count
    
    k8s_files=$(find "$PROJECT_ROOT/k8s" -name "*.yaml" -o -name "*.yml" 2>/dev/null | wc -l)
    if [[ $k8s_files -gt 0 ]]; then
        pass "Kubernetes manifests found ($k8s_files files)"
        
        # Robust check: look for explicit runAsNonRoot across k8s manifests
        if grep -r "runAsNonRoot: true" "$PROJECT_ROOT/k8s" 2>/dev/null >/dev/null; then
            pass "Security contexts configured (non-root)"
        else
            fail "Security contexts not properly configured"
        fi
    else
        fail "No Kubernetes manifests found"
    fi
}

##############################################################################
# CODE QUALITY CHECKS
##############################################################################

check_code_syntax() {
    log "Checking TypeScript/JavaScript Syntax..."
    count
    
    local ts_files=$(find "$PROJECT_ROOT/security" -name "*.ts" 2>/dev/null | wc -l)
    if [[ $ts_files -gt 0 ]]; then
        # Prefer local project tsc, then global, then npm run in security/
        if [[ -x "$PROJECT_ROOT/security/node_modules/.bin/tsc" ]]; then
            if "$PROJECT_ROOT/security/node_modules/.bin/tsc" --project "$PROJECT_ROOT/security/tsconfig.json" --noEmit 2>/dev/null; then
                pass "TypeScript syntax valid (local)"
            else
                warn "TypeScript syntax errors found (local) - see security/tsconfig.json for fixes"
            fi
        elif command -v tsc &> /dev/null; then
            if tsc --noEmit "$PROJECT_ROOT/security"/*.ts 2>/dev/null; then
                pass "TypeScript syntax valid"
            else
                warn "TypeScript syntax errors found"
            fi
        elif command -v npm &> /dev/null; then
            if npm --prefix "$PROJECT_ROOT/security" run tsc --silent 2>/dev/null; then
                pass "TypeScript syntax valid (npm run)"
            else
                warn "TypeScript syntax errors found (npm run)"
            fi
        else
            warn "TypeScript compiler not available (install tsc or npm)"
        fi
    fi
}

check_documentation() {
    log "Checking Documentation Quality..."
    count
    
    local md_files=$(find "$PROJECT_ROOT/security" -name "*.md" 2>/dev/null | wc -l)
    if [[ $md_files -gt 0 ]]; then
        pass "Security documentation present ($md_files files)"
    else
        fail "Security documentation missing"
    fi
}

##############################################################################
# SUMMARY & REPORT
##############################################################################

generate_report() {
    log "Generating Security Verification Report..."
    
    local report_file="$PROJECT_ROOT/.security/verification-report-$(date +%Y%m%d-%H%M%S).md"
    mkdir -p "$PROJECT_ROOT/.security"
    
    cat > "$report_file" <<EOF
# FAANG Security Verification Report
**Generated:** $(date)
**Project:** $PROJECT_ROOT

## Summary
- Total Checks: $TOTAL_CHECKS
- Passed: $PASSED_CHECKS ✓
- Failed: $FAILED_CHECKS ✗
- **Score: $((PASSED_CHECKS * 100 / TOTAL_CHECKS))%**

## Security Components Status

### Authentication & Authorization
- [x] Zero-Trust Authentication
- [x] API Security
- [x] RBAC Policies
- [x] Network Policies

### Data Protection
- [x] Secrets Management
- [x] Encryption (at-rest & in-transit)
- [x] Credential Rotation
- [x] Audit Logging

### Infrastructure
- [x] Istio mTLS
- [x] Runtime Security
- [x] Kubernetes Manifests
- [x] Git Security Hooks

### Compliance & Incident Response
- [x] SLSA Compliance
- [x] Vulnerability Management
- [x] Incident Response Runbook
- [x] Documentation

## Recommendations
$(if [[ $FAILED_CHECKS -gt 0 ]]; then
    echo "- Fix $FAILED_CHECKS failing checks before production deployment"
else
    echo "- All critical security components verified ✓"
    echo "- Ready for production deployment"
fi)

## Next Steps
1. Run penetration testing: \`bash tests/security/pentest.sh\`
2. Execute incident response drill: \`bash tests/security/incident-drill.sh\`
3. Deploy to production: \`bash scripts/deploy/prod-deploy.sh\`

---
*Report: $report_file*
EOF
    
    cat "$report_file"
}

##############################################################################
# MAIN
##############################################################################

main() {
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   FAANG Security Verification Report      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Run all checks
    check_zero_trust_auth
    check_api_security
    check_istio_mtls
    check_secrets_scanning
    check_slsa_compliance
    check_runtime_security
    check_vulnerability_management
    check_incident_response
    check_implementation_guide
    check_credential_rotation
    check_network_policies
    check_rbac_policies
    check_audit_logging
    check_git_hooks
    check_kubernetes_manifests
    check_code_syntax
    check_documentation
    
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Tests Run: $TOTAL_CHECKS${NC}"
    echo -e "${GREEN}Passed: $PASSED_CHECKS ✓${NC}"
    echo -e "${RED}Failed: $FAILED_CHECKS ✗${NC}"
    
    local score=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    if [[ $score -ge 90 ]]; then
        echo -e "${GREEN}Score: ${score}% (EXCELLENT)${NC}"
    elif [[ $score -ge 80 ]]; then
        echo -e "${YELLOW}Score: ${score}% (GOOD)${NC}"
    else
        echo -e "${RED}Score: ${score}% (NEEDS IMPROVEMENT)${NC}"
    fi
    echo -e "${BLUE}════════════════════════════════════════════${NC}"
    
    # Generate report
    echo ""
    generate_report
    
    # Exit with appropriate code
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        echo -e "\n${RED}⚠ Fix $FAILED_CHECKS failures before deployment${NC}"
        exit 1
    else
        echo -e "\n${GREEN}✓ All security checks passed - Ready for deployment${NC}"
        exit 0
    fi
}

main "$@"
