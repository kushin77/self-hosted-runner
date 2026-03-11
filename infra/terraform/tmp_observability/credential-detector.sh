#!/bin/bash
# Automated credential detector + deploy trigger
# Handles auto-deployment when GSM secret or local SA key becomes available
# Idempotent, safe for cron/systemd timer; logs all attempts

set -euo pipefail

PROJECT="${PROJECT:-nexusshield-prod}"
SECRET_NAME="${SECRET_NAME:-deploy-sa-key}"
TARGET_URL="${TARGET_URL:-https://nexus-shield-portal-backend-2tqp6t4txq-uc.a.run.app/health}"
LOG_DIR="${LOG_DIR:-logs/deploy-blocker}"
LOG_FILE="${LOG_DIR}/credential-detector-$(date +%Y%m%d).log"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT:-infra/terraform/tmp_observability/deploy_with_gsm.sh}"

mkdir -p "$LOG_DIR"

log_event() {
    local level="$1"
    local message="$2"
    local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"timestamp\":\"$ts\",\"level\":\"$level\",\"message\":\"$message\"}" >> "$LOG_FILE"
    echo "[$ts] $level: $message"
}

# Check for GSM secret
check_gsm_secret() {
    if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
        log_event "INFO" "GSM secret $SECRET_NAME found in project $PROJECT"
        return 0
    fi
    return 1
}

# Check for local SA key
check_local_key() {
    if [ -f /etc/nexusshield/gcp-sa.json ]; then
        log_event "INFO" "Local SA key found at /etc/nexusshield/gcp-sa.json"
        return 0
    fi
    return 1
}

# Attempt deploy
attempt_deploy() {
    log_event "INFO" "Credentials detected. Attempting deployment..."
    
    if [ ! -f "$DEPLOY_SCRIPT" ]; then
        log_event "ERROR" "Deploy script not found at $DEPLOY_SCRIPT"
        return 1
    fi
    
    if bash "$DEPLOY_SCRIPT" "$PROJECT" "$SECRET_NAME" 2>&1 | tee -a "$LOG_FILE"; then
        log_event "INFO" "Deployment succeeded. Verifying resources..."
        
        # Verify Cloud Function was created
        if gcloud functions describe synthetic-health-check --region=us-central1 --project="$PROJECT" >/dev/null 2>&1; then
            log_event "INFO" "✓ Cloud Function verified"
            # Log success event
            ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            echo "{\"timestamp\":\"$ts\",\"event\":\"DEPLOY_SUCCESS\",\"function\":\"synthetic-health-check\",\"project\":\"$PROJECT\",\"target_url\":\"$TARGET_URL\"}" >> "$LOG_FILE"
            return 0
        fi
    fi
    
    log_event "ERROR" "Deployment failed or function not verified"
    return 1
}

# Main entry point
main() {
    log_event "INFO" "Credential detector started (project=$PROJECT, secret=$SECRET_NAME)"
    
    if check_gsm_secret; then
        attempt_deploy
    elif check_local_key; then
        log_event "INFO" "Using local SA key at /etc/nexusshield/gcp-sa.json"
        export GOOGLE_APPLICATION_CREDENTIALS=/etc/nexusshield/gcp-sa.json
        attempt_deploy
    else
        log_event "WARN" "No credentials found (GSM secret or local key)"
        log_event "WARN" "REMEDIATION: (A) Create GSM secret $SECRET_NAME with SA key, OR (B) Place SA key at /etc/nexusshield/gcp-sa.json"
        echo "Credentials not yet available. See $LOG_FILE for details."
        return 1
    fi
}

main "$@"
