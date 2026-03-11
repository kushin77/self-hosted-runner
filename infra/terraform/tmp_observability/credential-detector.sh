#!/bin/bash
# Automated credential detector + deploy trigger
# Handles auto-deployment when GSM/Vault credentials become available
# Idempotent, safe for cron/systemd timer; logs all attempts

set -euo pipefail

PROJECT="${PROJECT:-nexusshield-prod}"
SECRET_NAME="${SECRET_NAME:-deploy-sa-key}"
TARGET_URL="${TARGET_URL:-https://nexus-shield-portal-backend-2tqp6t4txq-uc.a.run.app/health}"
LOG_DIR="${LOG_DIR:-logs/deploy-blocker}"
LOG_FILE="${LOG_DIR}/credential-detector-$(date +%Y%m%d).log"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT:-infra/terraform/tmp_observability/deploy_with_gsm.sh}"
VAULT_SECRET_PATH="${VAULT_SECRET_PATH:-secret/data/nexus/deploy-sa-key}"
VAULT_FIELD="${VAULT_FIELD:-sa_key}"
ALLOW_LOCAL_KEY="${ALLOW_LOCAL_KEY:-0}"
USE_WI="${USE_WI:-0}"
# Workload Identity config (set when USE_WI=1)
PROJECT_NUMBER="${PROJECT_NUMBER:-}"    # numeric project number
WI_POOL="${WI_POOL:-runner-pool-20260311}"
WI_PROVIDER="${WI_PROVIDER:-runner-provider-20260311}"
SA_EMAIL="${SA_EMAIL:-nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com}"
WI_SCOPES="${WI_SCOPES:-https://www.googleapis.com/auth/cloud-platform}"

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

# Check for local SA key (disabled by default; set ALLOW_LOCAL_KEY=1 to enable)
check_local_key() {
    if [ "${ALLOW_LOCAL_KEY}" != "1" ]; then
        return 1
    fi
    if [ -f /etc/nexusshield/gcp-sa.json ]; then
        log_event "INFO" "Local SA key found at /etc/nexusshield/gcp-sa.json"
        return 0
    fi
    return 1
}

# Check Vault (HashiCorp Vault KV v2 recommended)
check_vault_secret() {
    if [ -n "${VAULT_ADDR:-}" ] && [ -n "${VAULT_TKN:-}" ]; then
        log_event "INFO" "VAULT_ADDR detected; attempting to read Vault path $VAULT_SECRET_PATH"
        if command -v vault >/dev/null 2>&1; then
            if vault kv get -field="$VAULT_FIELD" "$VAULT_SECRET_PATH" >/dev/null 2>&1; then
                log_event "INFO" "Vault secret $VAULT_SECRET_PATH:$VAULT_FIELD available"
                return 0
            fi
            if vault read -field="$VAULT_FIELD" "$VAULT_SECRET_PATH" >/dev/null 2>&1; then
                log_event "INFO" "Vault secret (read) available at $VAULT_SECRET_PATH:$VAULT_FIELD"
                return 0
            fi
        else
            log_event "WARN" "vault CLI not installed; skipping Vault check"
        fi
    fi
    return 1
}

# If USE_WI=1 attempt to exchange an OIDC subject token (provided via SUBJECT_TOKEN env)
# for a short-lived service account access token and export it for gcloud via
# CLOUDSDK_AUTH_ACCESS_TOKEN.
exchange_wi_and_export() {
    if [ "${USE_WI}" != "1" ]; then
        return 1
    fi
    if [ -z "${SUBJECT_TOKEN:-}" ]; then
        log_event "WARN" "USE_WI=1 but SUBJECT_TOKEN not set; skipping WI exchange"
        return 1
    fi
    log_event "INFO" "Attempting Workload Identity token exchange via scripts/auth/exchange-wi-token.sh"
    if ! token_json=$(PROJECT_NUMBER="$PROJECT_NUMBER" WI_POOL="$WI_POOL" WI_PROVIDER="$WI_PROVIDER" SA_EMAIL="$SA_EMAIL" SCOPES="$WI_SCOPES" SUBJECT_TOKEN="$SUBJECT_TOKEN" scripts/auth/exchange-wi-token.sh 2>>"$LOG_FILE"); then
        log_event "ERROR" "WI token exchange failed"
        return 1
    fi
    access_token=$(echo "$token_json" | jq -r .access_token // empty)
    if [ -z "$access_token" ]; then
        log_event "ERROR" "WI helper returned no access_token: $token_json"
        return 1
    fi
    export CLOUDSDK_AUTH_ACCESS_TOKEN="$access_token"
    unset GOOGLE_APPLICATION_CREDENTIALS || true
    log_event "INFO" "Exported CLOUDSDK_AUTH_ACCESS_TOKEN for ephemeral gcloud auth"
    return 0
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
        # Prefer Workload Identity token flow if enabled
        if exchange_wi_and_export; then
            attempt_deploy
        else
            attempt_deploy
        fi
    elif check_local_key; then
        log_event "INFO" "Using local SA key at /etc/nexusshield/gcp-sa.json"
        export GOOGLE_APPLICATION_CREDENTIALS=/etc/nexusshield/gcp-sa.json
        attempt_deploy
    elif check_vault_secret; then
        log_event "INFO" "Using service account from Vault ($VAULT_SECRET_PATH:$VAULT_FIELD)"
        tmpfile=$(mktemp)
        if vault kv get -field="$VAULT_FIELD" "$VAULT_SECRET_PATH" > "$tmpfile" 2>/dev/null || vault read -field="$VAULT_FIELD" "$VAULT_SECRET_PATH" > "$tmpfile" 2>/dev/null; then
            chmod 600 "$tmpfile"
            export GOOGLE_APPLICATION_CREDENTIALS="$tmpfile"
            if attempt_deploy; then
                rm -f "$tmpfile"
                return 0
            fi
            rm -f "$tmpfile"
        else
            log_event "ERROR" "Failed to extract SA key from Vault path $VAULT_SECRET_PATH"
        fi
        log_event "ERROR" "Deployment via Vault failed"
    else
        log_event "WARN" "No credentials found (GSM secret or Vault) [local key disabled by default]"
        log_event "WARN" "REMEDIATION: (A) Create GSM secret $SECRET_NAME with SA key, OR (B) Set VAULT_ADDR & VAULT_TKN and store SA key at $VAULT_SECRET_PATH with field $VAULT_FIELD. Optional: set ALLOW_LOCAL_KEY=1 to use /etc/nexusshield/gcp-sa.json"
        echo "Credentials not yet available. See $LOG_FILE for details."
        return 1
    fi
}

main "$@"
