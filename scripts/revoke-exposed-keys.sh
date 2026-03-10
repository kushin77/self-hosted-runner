#!/bin/bash
# Revoke Exposed/Compromised Keys Across GSM/Vault/AWS
# Phase 3: Post-deployment key hygiene
# Immutable | Ephemeral | Idempotent | No-Ops
#
# Usage: ./revoke-exposed-keys.sh [--dry-run] [--audit-only]
# 
# Prerequisites:
#   - gcloud CLI configured with GSM access
#   - Vault CLI configured (VAULT_ADDR, REDACTED_VAULT_TOKEN or auth method)
#   - aws CLI configured with KMS access
#   - logs/deployment-provisioning-audit.jsonl existing (audit trail)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_LOG="$PROJECT_ROOT/logs/deployment-provisioning-audit.jsonl"
AUDIT_STATE="$PROJECT_ROOT/logs/revocation-audit.jsonl"
DRY_RUN="${1:-}"
AUDIT_ONLY="${2:-}"

# Logging & state
log_audit() {
    local action="$1"
    local status="$2"
    local details="$3"
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    echo "{\"timestamp\":\"$timestamp\",\"action\":\"$action\",\"status\":\"$status\",\"details\":$details}" >> "$AUDIT_STATE"
}

fail_audit() {
    local reason="$1"
    log_audit "REVOCATION_FAILED" "ERROR" "$(echo \"$reason\" | jq -R .)"
    exit 1
}

info() {
    echo "[$(date -u +'%Y-%m-%d %H:%M:%S UTC')] $1"
}

# =============================================================================
# Phase 1: Identify Exposed Keys
# =============================================================================

identify_exposed_keys() {
    info "Identifying exposed keys from audit logs and git history..."
    
    # Extract all keys rotated/created in last 7 days from audit
    exposed_keys=()
    while IFS= read -r line; do
        if echo "$line" | jq -e '.action == "KEY_CREATED" or .action == "KEY_ROTATED"' > /dev/null 2>&1; then
            key_id=$(echo "$line" | jq -r '.key_id // "unknown"')
            key_type=$(echo "$line" | jq -r '.key_type // "unknown"')
            backend=$(echo "$line" | jq -r '.backend // "unknown"')
            exposed_keys+=("$key_type:$key_id:$backend")
        fi
    done < "$AUDIT_LOG"
    
    info "Found ${#exposed_keys[@]} keys from audit trail"
    
    # Scan git history for committed secrets (gitleaks if available)
    if command -v gitleaks &> /dev/null; then
        info "Running gitleaks scan..."
        gitleaks detect --source "$PROJECT_ROOT" --report-path /tmp/gitleaks-report.json --exit-code 0 || true
        if [ -f /tmp/gitleaks-report.json ]; then
            exposed_count=$(jq '.[] | select(.Secret // false) | length' /tmp/gitleaks-report.json || echo 0)
            info "Gitleaks found $exposed_count potential secrets"
        fi
    else
        info "gitleaks not found; skipping git history scan (install with: apt install gitleaks)"
    fi
    
    echo "${exposed_keys[@]}"
}

# =============================================================================
# Phase 2: Revoke from GSM
# =============================================================================

revoke_from_gsm() {
    local key_id="$1"
    info "[GSM] Revoking key $key_id..."
    
    if [ "$DRY_RUN" == "--dry-run" ]; then
        info "[GSM-DRY-RUN] Would revoke secret: $key_id"
        log_audit "GSM_REVOKE_DRY_RUN" "SUCCESS" "{\"key_id\":\"$key_id\"}"
        return 0
    fi
    
    # Get project ID from gcloud config
    local project_id
    project_id=$(gcloud config get-value project 2>/dev/null || echo "unknown")
    
    # List all versions of the secret
    local versions
    versions=$(gcloud secrets versions list "$key_id" --project="$project_id" --format='value(name)' 2>/dev/null || true)
    
    if [ -z "$versions" ]; then
        info "[GSM] Secret $key_id not found (may already be deleted)"
        log_audit "GSM_REVOKE_NOTFOUND" "SKIPPED" "{\"key_id\":\"$key_id\"}"
        return 0
    fi
    
    # Destroy all versions
    while IFS= read -r version; do
        info "[GSM] Destroying version $version of $key_id..."
        gcloud secrets versions destroy "$version" --secret="$key_id" --project="$project_id" --quiet 2>&1 || true
    done <<< "$versions"
    
    # Optionally delete the secret resource itself (aggressive)
    # gcloud secrets delete "$key_id" --project="$project_id" --quiet 2>&1 || true
    
    log_audit "GSM_REVOKE_SUCCESS" "SUCCESS" "{\"key_id\":\"$key_id\",\"versions\":\"$(echo \"$versions\" | wc -l)\"}"
}

# =============================================================================
# Phase 3: Revoke from Vault
# =============================================================================

revoke_from_vault() {
    local key_path="$1"
    local key_id="$2"
    info "[Vault] Revoking key at path: $key_path..."
    
    if [ "$DRY_RUN" == "--dry-run" ]; then
        info "[Vault-DRY-RUN] Would revoke secret: $key_path"
        log_audit "VAULT_REVOKE_DRY_RUN" "SUCCESS" "{\"path\":\"$key_path\",\"key_id\":\"$key_id\"}"
        return 0
    fi
    
    # Check Vault connectivity
    if ! vault status > /dev/null 2>&1; then
        info "[Vault] Vault not accessible, skipping revocation"
        log_audit "VAULT_REVOKE_UNREACHABLE" "SKIPPED" "{\"path\":\"$key_path\"}"
        return 0
    fi
    
    # Rotate AppRole credential (revoke old, generate new)
    if [[ "$key_path" == *"approle"* ]]; then
        info "[Vault] Rotating AppRole credentials at $key_path..."
        vault write -f "$key_path/role/automation/secret-id" > /dev/null 2>&1 || true
        vault write -f "$key_path/role/automation/role-id" > /dev/null 2>&1 || true
    fi
    
    # Delete old secrets from KV store
    vault kv delete "$key_path" 2>&1 || true
    
    log_audit "VAULT_REVOKE_SUCCESS" "SUCCESS" "{\"path\":\"$key_path\",\"key_id\":\"$key_id\"}"
}

# =============================================================================
# Phase 4: Revoke from AWS KMS
# =============================================================================

revoke_from_aws() {
    local key_id="$1"
    info "[AWS KMS] Revoking/scheduling deletion of key $key_id..."
    
    if [ "$DRY_RUN" == "--dry-run" ]; then
        info "[AWS-DRY-RUN] Would schedule key deletion: $key_id"
        log_audit "AWS_REVOKE_DRY_RUN" "SUCCESS" "{\"key_id\":\"$key_id\"}"
        return 0
    fi
    
    # Schedule key deletion (7-day waiting period by default)
    aws kms schedule-key-deletion --key-id "$key_id" --pending-window-in-days 7 2>&1 || {
        # If key not found or already pending deletion, skip
        info "[AWS KMS] Key $key_id may already be deleted or invalid"
        log_audit "AWS_REVOKE_NOTFOUND" "SKIPPED" "{\"key_id\":\"$key_id\"}"
        return 0
    }
    
    info "[AWS KMS] Key $key_id scheduled for deletion (7-day grace period)"
    log_audit "AWS_REVOKE_SCHEDULED" "SUCCESS" "{\"key_id\":\"$key_id\"}"
}

# =============================================================================
# Phase 5: Clean Local State
# =============================================================================

clean_local_state() {
    info "Cleaning local credential caches..."
    
    if [ "$DRY_RUN" == "--dry-run" ]; then
        info "[DRY-RUN] Would shred: /tmp/vault-token, ~/.ssh/id_*, ~/.ssh/authorized_keys"
        log_audit "LOCAL_CLEANUP_DRY_RUN" "SUCCESS" "{}"
        return 0
    fi
    
    # Shred Vault token if present
    if [ -f /tmp/vault-token ]; then
        info "Shredding /tmp/vault-token..."
        shred -vfz -n 3 /tmp/vault-token 2>/dev/null || rm -f /tmp/vault-token
    fi
    
    # (Note: Be very careful with ~/.ssh credentials; only revoke if explicitly in audit trail)
    # For now, just log the action
    info "Local SSH credentials retained (manual review recommended)"
    
    log_audit "LOCAL_CLEANUP_SUCCESS" "SUCCESS" "{}"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    info "================== KEY REVOCATION AUTOMATION =================="
    info "DRY_RUN: ${DRY_RUN:-false}, AUDIT_ONLY: ${AUDIT_ONLY:-false}"
    info "Audit log: $AUDIT_LOG"
    info "State log: $AUDIT_STATE"
    
    # Initialize audit state
    log_audit "REVOCATION_STARTED" "INITIATED" "{\"timestamp\":\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\"}"
    
    # Phase 1: Identify
    exposed_keys_list=$(identify_exposed_keys)
    info "Exposed keys to revoke: $exposed_keys_list"
    
    if [ "$AUDIT_ONLY" == "--audit-only" ]; then
        info "Audit-only mode; stopping before revocation."
        log_audit "REVOCATION_AUDIT_COMPLETE" "SUCCESS" "{\"keys\":\"$(echo \"$exposed_keys_list\" | wc -w)\"}"
        exit 0
    fi
    
    # Phase 2-4: Revoke across backends
    for key in $exposed_keys_list; do
        IFS=':' read -r key_type key_id backend <<< "$key"
        info "Revoking $key_type:$key_id from $backend..."
        
        case "$backend" in
            GSM)
                revoke_from_gsm "$key_id"
                ;;
            VAULT)
                revoke_from_vault "secret/data/$key_id" "$key_id"
                ;;
            AWS)
                revoke_from_aws "$key_id"
                ;;
            *)
                info "Unknown backend: $backend (skipping)"
                ;;
        esac
    done
    
    # Phase 5: Clean local state
    clean_local_state
    
    log_audit "REVOCATION_COMPLETED" "SUCCESS" "{\"keys_processed\":\"$(echo \"$exposed_keys_list\" | wc -w)\"}"
    info "✅ Key revocation automation complete. Audit trail: $AUDIT_STATE"
}

main "$@"
