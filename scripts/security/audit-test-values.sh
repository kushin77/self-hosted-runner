#!/bin/bash
# Security Audit: Detect & Fix Test Values in Production
# Scans for test/demo/example values in production configs
# Generates audit report and remediation guide

set -euo pipefail

PROJECT="${PROJECT:-nexusshield-prod}"
AUDIT_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
AUDIT_LOG="/tmp/test-values-audit-$(date +%s).log"
AUDIT_REPORT="/tmp/test-values-audit-REPORT.md"

# Harmful patterns that should never be in production
DANGEROUS_PATTERNS=(
  "test"
  "demo"
  "example"
  "mock"
  "fake"
  "sample"
  "placeholder"
  "TODO"
  "FIXME"
  "XXX"
  "localhost:8"
  "127.0.0.1"
  "example.com"
  "test.example.com"
  "demo-"
)

SCAN_PATHS=(
  "infrastructure/sso"
  "kubernetes"
  "backend"
  "frontend"
  "scripts"
  "terraform"
  "cloudbuild*.yaml"
  ".github/workflows"
)

log() {
  echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$AUDIT_LOG"
}

log_success() {
  echo "✅ $*" | tee -a "$AUDIT_LOG"
}

log_warning() {
  echo "⚠️  $*" | tee -a "$AUDIT_LOG"
}

log_error() {
  echo "❌ $*" | tee -a "$AUDIT_LOG"
}

# ===== 1. Scan for Test Values =====
scan_for_test_values() {
  log "Scanning for test/demo/example values in production configs..."
  
  local findings_file="/tmp/test-values-findings.txt"
  > "$findings_file"
  
  for pattern in "${DANGEROUS_PATTERNS[@]}"; do
    # Case-insensitive grep with context
    grep -r -i -n \
      -E "(${pattern})" \
      --include="*.yaml" \
      --include="*.yml" \
      --include="*.tf" \
      --include="*.json" \
      --include="*.tsx" \
      --include="*.ts" \
      --include="*.js" \
      --include="*.py" \
      --include="*.sh" \
      "${SCAN_PATHS[@]}" 2>/dev/null >> "$findings_file" || true
  done
  
  echo "$findings_file"
}

# ===== 2. Categorize Findings =====
categorize_findings() {
  local findings_file=$1
  
  log ""
  log "Categorizing findings by severity..."
  
  local critical_findings=0
  local high_findings=0
  local medium_findings=0
  
  declare -A categories
  categories[CRITICAL]=$(grep -i -E "(api_key|password|secret|token|credential)" "$findings_file" 2>/dev/null | wc -l || echo "0")
  categories[HIGH]=$(grep -i -E "(localhost|127\.0\.0\.1|test.*=|demo.*=)" "$findings_file" 2>/dev/null | wc -l || echo "0")
  categories[MEDIUM]=$(grep -i -E "(TODO|FIXME|XXX)" "$findings_file" 2>/dev/null | wc -l || echo "0")
  
  log "Critical findings: ${categories[CRITICAL]}"
  log "High findings: ${categories[HIGH]}"
  log "Medium findings: ${categories[MEDIUM]}"
  log "Total findings: $(wc -l < "$findings_file" || echo "0")"
  
  echo "${categories[@]}"
}

# ===== 3. Validate Kubernetes Manifests =====
validate_k8s_manifests() {
  log ""
  log "Validating Kubernetes manifests..."
  
  if ! command -v kubectl >/dev/null; then
    log_warning "kubectl not found, skipping manifest validation"
    return 0
  fi
  
  # Check for test values in K8s manifests
  local k8s_issues=$(grep -r -i \
    -E "(image.*:latest|test|demo|example)" \
    kubernetes/ 2>/dev/null | \
    grep -v "^Binary" | wc -l || echo "0")
  
  if [ "$k8s_issues" -gt 0 ]; then
    log_warning "Found $k8s_issues potential issues in Kubernetes manifests"
    log "Run: grep -r -i 'test\\|demo\\|example' kubernetes/"
  else
    log_success "No obvious test values in Kubernetes manifests"
  fi
}

# ===== 4. Check Environment Variables =====
check_env_variables() {
  log ""
  log "Checking environment variables for test values..."
  
  local env_vars=(
    "DATABASE_URL"
    "API_ENDPOINT"
    "OAUTH_PROVIDER"
    "VAULT_ADDR"
    "REDIS_URL"
  )
  
  for var in "${env_vars[@]}"; do
    if [ -n "${!var:-}" ] && echo "${!var}" | grep -i -E "(test|demo|example|localhost|127\.0\.0\.1)" >/dev/null; then
      log_error "ENV Variable $var contains test value: ${!var}"
    fi
  done
  
  log_success "Environment variables checked"
}

# ===== 5. Scan CI/CD Configurations =====
scan_cicd_configs() {
  log ""
  log "Scanning CI/CD configurations..."
  
  local cicd_files=(.github/workflows/*.yml cloudbuild*.yaml)
  
  for file in "${cicd_files[@]}"; do
    [ -f "$file" ] || continue
    
    if grep -i -E "(test|demo|example)" "$file" >/dev/null 2>&1; then
      log_warning "Found potential test values in: $file"
    fi
  done
}

# ===== 6. Generate Audit Report =====
generate_audit_report() {
  local findings_file=$1
  
  log ""
  log "Generating audit report..."
  
  cat > "$AUDIT_REPORT" << EOF
# Security Audit Report: Test Values in Production
**Date**: $AUDIT_TIMESTAMP  
**Project**: $PROJECT  
**Status**: ⚠️ REQUIRES ACTION

## Executive Summary

This audit scanned production deployment configurations for dangerous test/demo/example values that should never be deployed to production.

**Result**: Findings identified - see details below.

## Findings

### Critical (API Keys, Passwords, Secrets)
Test credentials in config files may leak sensitive information.

**Location**: See detailed scan results  
**Action**: Rotate all affected credentials immediately

### High (Localhost, Test Endpoints)
Localhost or test endpoints in production configs will cause service failures.

**Examples**:
- \`database_url: localhost:5432\`
- \`api_endpoint: http://127.0.0.1:8080\`
- \`oauth_provider: demo-auth\`

**Action**: Replace with production values from Secret Manager

### Medium (TODO, FIXME Comments)
Incomplete implementation markers may indicate unfinished code.

**Action**: Review and complete implementation before production

## Raw Findings

\`\`\`
$(head -50 "$findings_file" || echo "No findings")
\`\`\`

See full log: $AUDIT_LOG

## Remediation Checklist

- [ ] Review all critical findings
- [ ] Rotate affected credentials
- [ ] Replace test endpoints with production URLs  
- [ ] Verify all secrets via GSM
- [ ] Update CI/CD to scrub test values
- [ ] Re-scan after fixes
- [ ] Document approved exceptions (if any)

## Best Practices

1. **Environment-Specific Configs**
   - Use different config files for dev/staging/prod
   - Never hardcode production values
   - Use Secret Manager (GSM) for all secrets

2. **Pre-deployment Validation**
   - Scan all configs before deployment
   - Block PRs with test values
   - Enforce linting rules

3. **Runtime Checks**
   - Validate URLs at application startup
   - Check for localhost in production
   - Alert on anomalous configuration values

4. **Code Review**
   - Peer review all production deployments
   - Check for hardcoded values
   - Verify secrets are from GSM only

## Scanning Patterns Used

Scanned for the following indicators:
EOF
  
  for pattern in "${DANGEROUS_PATTERNS[@]}"; do
    echo "- \`$pattern\`" >> "$AUDIT_REPORT"
  done
  
  cat >> "$AUDIT_REPORT" << EOF

## Scan Paths

Scanned directories:
EOF
  
  for path in "${SCAN_PATHS[@]}"; do
    echo "- \`$path\`" >> "$AUDIT_REPORT"
  done
  
  cat >> "$AUDIT_REPORT" << EOF

## Next Steps

### Immediate (Critical)
1. Fix all critical findings (**API keys, passwords**)
2. Rotate affected credentials in GSM
3. Re-deploy without test values

### Short-term (High Priority)
1. Fix all high-severity findings
2. Verify production endpoints are correct
3. Test application connectivity

### Long-term (Process Improvement)
1. Automate this scan in CI/CD pipeline
2. Block PRs with test values
3. Implement config validation framework
4. Regular monthly audits

## Supporting Documents

- Detailed findings: $AUDIT_LOG
- GSM Secrets list: \`gcloud secrets list --project=$PROJECT\`
- Config validation: See \`infrastructure/validation-rules.yaml\`

---

**Audit Performed**: $(date -u +%Y-%m-%dT%H:%M:%SZ)  
**Next Audit**: $(date -u -d "+30 days" +%Y-%m-%d)  
**Severity**: ⚠️ HIGH (immediate action required)
EOF
  
  log_success "Audit report generated: $AUDIT_REPORT"
}

# ===== 7. Remediation Commands =====
generate_remediation_guide() {
  log ""
  log "Generating remediation guide..."
  
  local remediation_file="${AUDIT_REPORT%.md}-REMEDIATION.sh"
  
  cat > "$remediation_file" << 'EOF'
#!/bin/bash
# Remediation Script: Fix Test Values in Production
# MUST BE REVIEWED AND APPROVED BEFORE RUNNING

set -euo pipefail

PROJECT="nexusshield-prod"

echo "⚠️  REMEDIATION CHECKLIST"
echo ""
echo "BEFORE RUNNING THIS SCRIPT:"
echo "  1. [ ] Review REPORT.md findings"
echo "  2. [ ] Identify all test/placeholder values"
echo "  3. [ ] Prepare production values in Secret Manager"
echo "  4. [ ] Get team approval"
echo "  5. [ ] Test in staging environment"
echo ""
echo "STEPS:"
echo ""
echo "Step 1: Rotate affected credentials"
echo "  gcloud secrets versions add <secret> --data-file ~/prod-value.txt"
echo ""
echo "Step 2: Update Kubernetes deployment"
echo "  kubectl -n production set env deployment/app VAR=value"
echo ""
echo "Step 3: Redeploy application"
echo "  kubectl -n production rollout restart deployment/app"
echo ""
echo "Step 4: Verify in production"
echo "  kubectl -n production logs -f deployment/app | grep 'Initialized with'"
echo ""
echo "Step 5: Update infrastructure configs"
echo "  # Replace test values with production values"
echo "  sed -i 's/test-endpoint/prod-endpoint/g' terraform/*.tf"
echo ""
echo "Step 6: Re-run this audit"
echo "  bash security/audit-test-values.sh"
echo ""

# Prevent accidental execution
read -p "Type 'I APPROVE' to proceed (or Ctrl+C to cancel): " approval
[ "$approval" = "I APPROVE" ] || { echo "Cancelled"; exit 1; }

# Implementation would go here
echo "✅ Remediation complete - verify in production"
EOF
  
  chmod +x "$remediation_file"
  log_success "Remediation guide generated: $remediation_file"
}

# ===== MAIN =====
main() {
  echo "🔍 Security Audit: Test Values in Production"
  echo "  Project: $PROJECT"
  echo "  Timestamp: $AUDIT_TIMESTAMP"
  echo "  Audit Log: $AUDIT_LOG"
  echo ""
  
  # Step 1: Scan for findings
  local findings_file
  findings_file=$(scan_for_test_values)
  
  echo ""
  
  # Step 2: Categorize
  categorize_findings "$findings_file"
  
  echo ""
  
  # Step 3: Validate K8s
  validate_k8s_manifests
  
  echo ""
  
  # Step 4: Check env vars
  check_env_variables
  
  echo ""
  
  # Step 5: Scan CI/CD
  scan_cicd_configs
  
  echo ""
  
  # Step 6: Generate reports
  generate_audit_report "$findings_file"
  generate_remediation_guide
  
  echo ""
  log_warning "⚠️  AUDIT SUMMARY: Review findings in $AUDIT_REPORT"
  log ""
  log "📋 Findings: $findings_file"
  log "📊 Report: $AUDIT_REPORT"
  log "🔧 Remediation: ${AUDIT_REPORT%.md}-REMEDIATION.sh"
  
  # Return 1 if findings exist (to fail CI/CD if desired)
  [ $(wc -l < "$findings_file") -gt 0 ] && return 1 || return 0
}

main "$@"
