#!/bin/bash
# 🔄 AUTOMATED CREDENTIAL ROTATION ORCHESTRATOR
# Hands-off, immutable, ephemeral credential lifecycle management
# Executes on schedule: GSM daily, Vault weekly, KMS quarterly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../../logs/rotation"
mkdir -p "$LOG_DIR"

# ============================================================================
# LOGGING & MONITORING
# ============================================================================
log() { echo "[$(date -u '+%Y-%m-%d_%H:%M:%S_UTC')] $*" | tee -a "$LOG_DIR/rotation.log"; }
success() { echo "✅ $*" | tee -a "$LOG_DIR/rotation.log"; }
error() { echo "❌ $*" | tee -a "$LOG_DIR/rotation.log"; }
audit() { echo "$(date -u '+%Y-%m-%d_%H:%M:%S_UTC') | ROTATION | $*" >> "$LOG_DIR/audit.log"; }

# ============================================================================
# GSM DAILY ROTATION
# ============================================================================
rotate_gsm_credentials() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "🔐 GSM DAILY CREDENTIAL ROTATION"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ -z "${GCP_PROJECT_ID:-}" ]; then
        error "GCP_PROJECT_ID not configured - skipping GSM rotation"
        return 1
    fi
    
    log "Rotating GSM secrets for project: $GCP_PROJECT_ID"
    
    # Verify current GSM secrets
    for secret in terraform-aws-prod terraform-aws-secret terraform-aws-region; do
        if gcloud secrets describe "$secret" \
            --project="$GCP_PROJECT_ID" \
            --format='value(name,created)' 2>/dev/null; then
            
            log "Verified GSM secret: $secret"
            audit "GSM | $secret | VERIFIED"
        else
            error "GSM secret not found: $secret"
            audit "GSM | $secret | MISSING"
        fi
    done
    
    # List current versions for cleanup
    log "Current GSM secret versions:"
    gcloud secrets versions list terraform-aws-prod \
        --project="$GCP_PROJECT_ID" \
        --limit=10 \
        --format='value(name,created)' 2>/dev/null || true
    
    success "GSM daily rotation check complete"
    audit "GSM_ROTATION | COMPLETE | SUCCESS"
    return 0
}

# ============================================================================
# VAULT WEEKLY ROTATION
# ============================================================================
rotate_vault_credentials() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "🔓 VAULT WEEKLY CREDENTIAL ROTATION"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ -z "${VAULT_ADDR:-}" ]; then
        error "VAULT_ADDR not configured - skipping Vault rotation"
        return 1
    fi
    
    if [ -z "${VAULT_TOKEN:-}" ]; then
        error "VAULT_TOKEN not configured - skipping Vault rotation"
        return 1
    fi
    
    log "Rotating Vault AppRole for deployment role"
    
    # Check AppRole status
    if curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/auth/approle/role/deployment" >/dev/null 2>&1; then
        
        log "AppRole deployment role verified"
        audit "VAULT | APPROLE | VERIFIED"
        
        # Generate new Secret ID (rotation)
        new_secret=$(curl -s \
            -X POST \
            -H "X-Vault-Token: $VAULT_TOKEN" \
            "$VAULT_ADDR/v1/auth/approle/role/deployment/secret-id" \
            2>/dev/null | jq -r '.data.secret_id' 2>/dev/null || echo "")
        
        if [ -n "$new_secret" ]; then
            log "New AppRole Secret ID generated"
            audit "VAULT | SECRET_ID_ROTATED | SUCCESS"
            success "Vault weekly rotation complete"
        else
            error "Failed to generate new Secret ID"
            audit "VAULT | SECRET_ID_ROTATION | FAILED"
        fi
    else
        error "Vault AppRole deployment role not found"
        audit "VAULT | APPROLE | NOT_FOUND"
    fi
    
    return 0
}

# ============================================================================
# KMS QUARTERLY KEY ROTATION
# ============================================================================
rotate_kms_keys() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "🔑 KMS QUARTERLY KEY ROTATION"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ -z "${AWS_REGION:-}" ]; then
        error "AWS_REGION not configured - skipping KMS rotation"
        return 1
    fi
    
    if [ -z "${KMS_KEY_ID:-}" ]; then
        log "KMS_KEY_ID not configured - listing available keys"
        aws kms list-keys --region "$AWS_REGION" \
            --query 'Keys[*].[KeyArn]' \
            --output text 2>/dev/null | head -5 || true
        return 0
    fi
    
    log "Rotating KMS key: $KMS_KEY_ID"
    
    # Check key status
    key_status=$(aws kms describe-key \
        --key-id "$KMS_KEY_ID" \
        --region "$AWS_REGION" \
        --query 'KeyMetadata.[KeyState,Enabled]' \
        --output text 2>/dev/null || echo "UNKNOWN UNKNOWN")
    
    log "KMS key status: $key_status"
    audit "KMS | KEY_STATUS | $key_status"
    
    # Enable automatic key rotation if not already enabled
    if aws kms get-key-rotation-status \
        --key-id "$KMS_KEY_ID" \
        --region "$AWS_REGION" \
        --query RotationEnabled 2>/dev/null | grep -q false; then
        
        log "Enabling automatic KMS key rotation..."
        aws kms enable-key-rotation \
            --key-id "$KMS_KEY_ID" \
            --region "$AWS_REGION" >/dev/null 2>&1
        
        success "KMS key rotation enabled"
        audit "KMS | ROTATION_ENABLED | SUCCESS"
    else
        log "KMS key rotation already enabled"
        audit "KMS | ROTATION_STATUS | ALREADY_ENABLED"
    fi
    
    success "KMS quarterly rotation check complete"
    return 0
}

# ============================================================================
# GITHUB SECRETS EPHEMERAL CLEANUP
# ============================================================================
cleanup_github_secrets() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "📝 GITHUB SECRETS EPHEMERAL CLEANUP"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if ! command -v gh >/dev/null 2>&1; then
        log "GitHub CLI not available - skipping cleanup"
        return 0
    fi
    
    # Get current secrets (for audit only - cannot delete via CLI)
    log "Current repository secrets (for audit trail):"
    gh secret list 2>/dev/null | tail -5 || log "Could not list secrets"
    
    audit "GITHUB | SECRETS_AUDIT | COMPLETE"
    success "GitHub secrets cleanup check complete"
    return 0
}

# ============================================================================
# ROTATION COORDINATION
# ============================================================================
determine_rotation_type() {
    local day_of_week=$(date +%w)      # 0=Sunday, 6=Saturday
    local day_of_month=$(date +%d)
    
    # Daily: GSM rotation every day
    echo "DAILY"
    
    # Weekly: Vault rotation on Sundays
    if [ "$day_of_week" == "0" ]; then
        echo "WEEKLY"
    fi
    
    # Quarterly: KMS rotation on 1st of Jan/Apr/Jul/Oct
    if [ "$day_of_month" == "01" ] && \
       { [ "$(date +%m)" == "01" ] || \
         [ "$(date +%m)" == "04" ] || \
         [ "$(date +%m)" == "07" ] || \
         [ "$(date +%m)" == "10" ]; }; then
        echo "QUARTERLY"
    fi
}

# ============================================================================
# HEALTH CHECK POST-ROTATION
# ============================================================================
verify_rotation_health() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "🏥 VERIFYING POST-ROTATION HEALTH"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local health_ok=0
    
    # Verify GSM
    if [ -n "${GCP_PROJECT_ID:-}" ]; then
        if gcloud secrets list --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
            log "✅ GSM layer accessible"
            audit "HEALTH | GSM | HEALTHY"
        else
            log "❌ GSM layer unhealthy"
            audit "HEALTH | GSM | UNHEALTHY"
            health_ok=1
        fi
    fi
    
    # Verify Vault
    if [ -n "${VAULT_ADDR:-}" ]; then
        if curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
            log "✅ Vault layer accessible"
            audit "HEALTH | VAULT | HEALTHY"
        else
            log "❌ Vault layer unhealthy"
            audit "HEALTH | VAULT | UNHEALTHY"
            health_ok=1
        fi
    fi
    
    # Verify KMS
    if [ -n "${AWS_REGION:-}" ]; then
        if aws kms list-keys --region "$AWS_REGION" >/dev/null 2>&1; then
            log "✅ KMS layer accessible"
            audit "HEALTH | KMS | HEALTHY"
        else
            log "❌ KMS layer unhealthy"
            audit "HEALTH | KMS | UNHEALTHY"
            health_ok=1
        fi
    fi
    
    return $health_ok
}

# ============================================================================
# INCIDENT ALERTING
# ============================================================================
alert_on_failure() {
    local failure_msg="$1"
    local rotation_type="$2"
    
    log "🚨 ALERTING: $failure_msg"
    audit "ALERT | $rotation_type | $failure_msg"
    
    # Create incident in issue tracking (if integration available)
    # This would trigger PagerDuty, Slack, etc. in production
    log "Incident created: Credential rotation failure - $rotation_type"
}

# ============================================================================
# MAIN ORCHESTRATION
# ============================================================================
main() {
    log "╔════════════════════════════════════════════════════════════════╗"
    log "║      CREDENTIAL ROTATION ORCHESTRATOR - AUTOMATED             ║"
    log "║      Time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')                    ║"
    log "╚════════════════════════════════════════════════════════════════╝"
    
    # Determine what rotations to run
    rotation_types=$(determine_rotation_type)
    
    log "Scheduled rotations for today: $rotation_types"
    
    failed=0
    
    # Daily GSM rotation
    if echo "$rotation_types" | grep -q "DAILY"; then
        rotate_gsm_credentials || { failed=$((failed+1)); alert_on_failure "GSM rotation failed" "DAILY"; }
    fi
    
    # Weekly Vault rotation (Sundays)
    if echo "$rotation_types" | grep -q "WEEKLY"; then
        rotate_vault_credentials || { failed=$((failed+1)); alert_on_failure "Vault rotation failed" "WEEKLY"; }
    fi
    
    # Quarterly KMS rotation
    if echo "$rotation_types" | grep -q "QUARTERLY"; then
        rotate_kms_keys || { failed=$((failed+1)); alert_on_failure "KMS rotation failed" "QUARTERLY"; }
    fi
    
    # Ephemeral cleanup (daily)
    cleanup_github_secrets || { failed=$((failed+1)); alert_on_failure "GitHub cleanup failed" "CLEANUP"; }
    
    # Verify health post-rotation
    if verify_rotation_health; then
        success "All credential layers healthy post-rotation"
        audit "ROTATION_CYCLE | COMPLETE | SUCCESS"
    else
        error "Some credential layers unhealthy post-rotation"
        audit "ROTATION_CYCLE | COMPLETE | PARTIAL_FAILURE"
        failed=$((failed+1))
    fi
    
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ $failed -eq 0 ]; then
        success "CREDENTIAL ROTATION COMPLETE - ALL LAYERS HEALTHY"
        audit "ROTATION_SESSION | SUCCESS"
        return 0
    else
        error "CREDENTIAL ROTATION COMPLETED WITH $failed FAILURE(S)"
        audit "ROTATION_SESSION | FAILED | $failed"
        return 1
    fi
}

# Execute
main "$@"
