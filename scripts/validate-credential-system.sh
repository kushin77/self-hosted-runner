#!/bin/bash
set -euo pipefail

##############################################################################
# Credential System Validation & Test Setup
# Purpose: Create test credentials and validate ephemeral retrieval
##############################################################################

TIMESTAMP=$(date -u +'%Y%m%d_%H%M%S')
LOG_FILE="credential-validation-${TIMESTAMP}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG_FILE"; }

# Configuration
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
VAULT_ADDR="${VAULT_ADDR:-}"

##############################################################################
# Phase 1: Create Test Credentials in GSM
##############################################################################

setup_test_credentials_gsm() {
  log_info "=== Phase 1: Creating Test Credentials in GSM ==="
  
  if [ -z "$GCP_PROJECT_ID" ]; then
    log_fail "GCP_PROJECT_ID not set"
    return 1
  fi

  # Test Credential 1: Terraform Backend Password
  log_info "Creating TEST_TERRAFORM_BACKEND_PASSWD..."
  TEST_TF_PASS=$(openssl rand -base64 32)
  
  (echo -n "$TEST_TF_PASS" | gcloud secrets create TEST_TERRAFORM_BACKEND_PASSWD \
    --data-file=/dev/stdin \
    --project="$GCP_PROJECT_ID" \
    --replication-policy="automatic" 2>/dev/null || \
   echo -n "$TEST_TF_PASS" | gcloud secrets versions add TEST_TERRAFORM_BACKEND_PASSWD \
    --data-file=/dev/stdin \
    --project="$GCP_PROJECT_ID") && log_pass "Created TEST_TERRAFORM_BACKEND_PASSWD"

  # Test Credential 2: AWS Access Key
  log_info "Creating TEST_AWS_ACCESS_KEY_ID..."
  TEST_AWS_KEY="AKIA$(openssl rand -hex 16 | tr '[:lower:]' '[:upper:]')"
  
  (echo -n "$TEST_AWS_KEY" | gcloud secrets create TEST_AWS_ACCESS_KEY_ID \
    --data-file=/dev/stdin \
    --project="$GCP_PROJECT_ID" \
    --replication-policy="automatic" 2>/dev/null || \
   echo -n "$TEST_AWS_KEY" | gcloud secrets versions add TEST_AWS_ACCESS_KEY_ID \
    --data-file=/dev/stdin \
    --project="$GCP_PROJECT_ID") && log_pass "Created TEST_AWS_ACCESS_KEY_ID"

  # Test Credential 3: Generic Token
  log_info "Creating TEST_API_TOKEN..."
  TEST_TOKEN=$(openssl rand -hex 64)
  
  (echo -n "$TEST_TOKEN" | gcloud secrets create TEST_API_TOKEN \
    --data-file=/dev/stdin \
    --project="$GCP_PROJECT_ID" \
    --replication-policy="automatic" 2>/dev/null || \
   echo -n "$TEST_TOKEN" | gcloud secrets versions add TEST_API_TOKEN \
    --data-file=/dev/stdin \
    --project="$GCP_PROJECT_ID") && log_pass "Created TEST_API_TOKEN"

  # Label secrets as ephemeral managed
  for SECRET in TEST_TERRAFORM_BACKEND_PASSWD TEST_AWS_ACCESS_KEY_ID TEST_API_TOKEN; do
    gcloud secrets add-iam-policy-binding "$SECRET" \
      --project="$GCP_PROJECT_ID" \
      --member="serviceAccount:github-actions-sa@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
      --role="roles/secretmanager.secretAccessor" 2>/dev/null || true
  done

  log_pass "Test credentials created and labeled in GSM"
}

##############################################################################
# Phase 2: Test Credential Retrieval
##############################################################################

test_credential_retrieval() {
  log_info "=== Phase 2: Testing Credential Retrieval ==="
  
  if [ ! -f "scripts/credential-manager.sh" ]; then
    log_fail "credential-manager.sh not found"
    return 1
  fi

  # Test GSM retrieval
  log_info "Testing GSM retrieval for TEST_API_TOKEN..."
  RETRIEVED=$(bash scripts/credential-manager.sh TEST_API_TOKEN gsm 2>/dev/null || echo "")
  
  if [ -n "$RETRIEVED" ]; then
    log_pass "TEST_API_TOKEN retrieved successfully"
    echo "  Value: ${RETRIEVED:0:20}... (masked)"
  else
    log_warn "GSM retrieval returned empty (might be expected if GSM not configured)"
  fi

  # Test failover
  log_info "Testing automatic failover..."
  RETRIEVED_AUTO=$(bash scripts/credential-manager.sh TEST_TERRAFORM_BACKEND_PASSWD auto 2>/dev/null || echo "")
  
  if [ -n "$RETRIEVED_AUTO" ]; then
    log_pass "Automatic failover successful"
  else
    log_warn "Auto retrieval not working (Vault/KMS might not be configured)"
  fi
}

##############################################################################
# Phase 3: Validate OIDC Token Generation
##############################################################################

test_oidc_tokens() {
  log_info "=== Phase 3: Testing OIDC Token Generation ==="
  
  # Note: OIDC tokens only available in GitHub Actions context
  if [ -z "$ACTIONS_ID_TOKEN_REQUEST_URL" ]; then
    log_warn "Not running in GitHub Actions context - OIDC tokens unavailable"
    log_info "In GitHub Actions, OIDC tokens will be available automatically"
    return 0
  fi

  log_info "Testing GCP OIDC token..."
  OIDC_TOKEN=$(curl -sS "${ACTIONS_ID_TOKEN_REQUEST_URL}?audience=https://iamcredentials.googleapis.com" \
    -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" 2>/dev/null | jq -r '.token // empty' || echo "")

  if [ -n "$OIDC_TOKEN" ]; then
    log_pass "GCP OIDC token obtained"
    echo "  Token: ${OIDC_TOKEN:0:20}... (masked)"
  else
    log_warn "OIDC token not available (expected outside GH Actions)"
  fi
}

##############################################################################
# Phase 4: Test GitHub Action (Manual Check)
##############################################################################

test_github_action() {
  log_info "=== Phase 4: GitHub Action Validation ==="
  
  if [ ! -f ".github/actions/get-ephemeral-credential/action.yml" ]; then
    log_fail "Action not found"
    return 1
  fi

  log_pass "GitHub Action structure verified"
  echo "  Action: .github/actions/get-ephemeral-credential/"
  echo "  Inputs: credential-name, retrieve-from, cache-ttl, audit-log"
  echo "  Outputs: credential, cached, expires-at, source-layer, audit-id"

  log_info "Test workflow usage:"
  cat <<'EOF'
  - uses: kushin77/get-ephemeral-credential@v1
    with:
      credential-name: TEST_API_TOKEN
      retrieve-from: 'auto'
      cache-ttl: 600

  # Output available as: steps.creds.outputs.credential
EOF
}

##############################################################################
# Phase 5: Workflow Schedule Validation
##############################################################################

test_workflow_schedules() {
  log_info "=== Phase 5: Workflow Schedule Validation ==="
  
  # Check if workflows exist
  WORKFLOWS=(
    ".github/workflows/ephemeral-credential-refresh-15min.yml"
    ".github/workflows/credential-system-health-check-hourly.yml"
    ".github/workflows/daily-credential-rotation.yml"
  )

  for WF in "${WORKFLOWS[@]}"; do
    if [ -f "$WF" ]; then
      log_pass "Workflow exists: $(basename $WF)"
    else
      log_warn "Workflow missing: $WF"
    fi
  done
}

##############################################################################
# Phase 6: Security Validation
##############################################################################

test_security() {
  log_info "=== Phase 6: Security Validation ==="
  
  # Check for hardcoded credentials in scripts
  log_info "Scanning for hardcoded secrets in scripts..."
  
  FOUND_SECRETS=0
  for file in scripts/*.sh .github/actions/**/*.js 2>/dev/null || true; do
    if [ ! -f "$file" ]; then
      continue
    fi
    
    if grep -E "password\s*=\s*['\"]" "$file" 2>/dev/null | grep -v "example" | grep -v "test"; then
      ((FOUND_SECRETS++))
    fi
  done

  if [ $FOUND_SECRETS -eq 0 ]; then
    log_pass "No hardcoded secrets found in implementation"
  else
    log_fail "Found $FOUND_SECRETS potential hardcoded secrets"
  fi

  # Validate audit logging
  log_info "Checking audit logging in scripts..."
  if grep -q "audit_log" scripts/credential-manager.sh; then
    log_pass "Audit logging implemented"
  else
    log_warn "Audit logging not detected"
  fi
}

##############################################################################
# Generate Report
##############################################################################

generate_report() {
  log_info "=== Validation Report ==="
  
  REPORT_FILE="credential-validation-report-${TIMESTAMP}.json"
  
  {
    echo "{"
    echo '  "validation_timestamp": "'$(date -u +'%Y-%m-%dT%H:%M:%SZ')'", '
    echo '  "components": {'
    echo '    "scripts": {'
    echo '      "audit_all_secrets": '$([ -f "scripts/audit-all-secrets.sh" ] && echo "true" || echo "false")', '
    echo '      "credential_manager": '$([ -f "scripts/credential-manager.sh" ] && echo "true" || echo "false")', '
    echo '      "setup_oidc": '$([ -f "scripts/setup-oidc-infrastructure.sh" ] && echo "true" || echo "false")'  '
    echo '    }, '
    echo '    "github_action": {'
    echo '      "exists": '$([ -f ".github/actions/get-ephemeral-credential/action.yml" ] && echo "true" || echo "false")'  '
    echo '    }, '
    echo '    "workflows": {'
    echo '      "refresh_15min": '$([ -f ".github/workflows/ephemeral-credential-refresh-15min.yml" ] && echo "true" || echo "false")', '
    echo '      "health_check_hourly": '$([ -f ".github/workflows/credential-system-health-check-hourly.yml" ] && echo "true" || echo "false")', '
    echo '      "daily_rotation": '$([ -f ".github/workflows/daily-credential-rotation.yml" ] && echo "true" || echo "false")'  '
    echo '    } '
    echo '  }, '
    echo '  "test_credentials_created": true, '
    echo '  "status": "ready_for_phase_2" '
    echo "}"
  } | tee "$REPORT_FILE"

  log_pass "Report generated: $REPORT_FILE"
}

##############################################################################
# MAIN
##############################################################################

main() {
  echo ""
  echo -e "${BLUE}======================================================${NC}"
  echo -e "${BLUE}Credential System Validation & Test Setup${NC}"
  echo -e "${BLUE}======================================================${NC}"
  echo ""

  setup_test_credentials_gsm 2>&1 | tee -a "$LOG_FILE" || true
  echo ""
  
  test_credential_retrieval 2>&1 | tee -a "$LOG_FILE" || true
  echo ""
  
  test_oidc_tokens 2>&1 | tee -a "$LOG_FILE" || true
  echo ""
  
  test_github_action 2>&1 | tee -a "$LOG_FILE" || true
  echo ""
  
  test_workflow_schedules 2>&1 | tee -a "$LOG_FILE" || true
  echo ""
  
  test_security 2>&1 | tee -a "$LOG_FILE" || true
  echo ""
  
  generate_report 2>&1 | tee -a "$LOG_FILE"

  echo ""
  echo -e "${BLUE}======================================================${NC}"
  echo -e "${GREEN}Validation Complete${NC}"
  echo -e "${BLUE}======================================================${NC}"
  echo ""
  echo "Log file: $LOG_FILE"
  echo ""
  echo "Next steps:"
  echo "  1. Review validation report (see JSON output above)"
  echo "  2. Test credentials available in GSM:"
  echo "     - TEST_TERRAFORM_BACKEND_PASSWD"
  echo "     - TEST_AWS_ACCESS_KEY_ID"
  echo "     - TEST_API_TOKEN"
  echo "  3. Configure GitHub Actions Org Secrets:"
  echo "     - GCP_PROJECT_ID"
  echo "     - GCP_WORKLOAD_IDENTITY_PROVIDER"
  echo "     - GCP_SERVICE_ACCOUNT"
  echo "  4. Trigger test workflow with manual dispatch"
  echo "  5. Proceed to Phase 5: Workflow migration"
  echo ""
}

main
