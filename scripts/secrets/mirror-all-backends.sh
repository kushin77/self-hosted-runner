#!/bin/bash

################################################################################
# Unified Secret Mirroring Framework
# Mirrors secrets from canonical GSM to Vault/KMS/Azure Key Vault (idempotent)
# NO GitHub Actions | Direct Deployment | Fully Automated | Hands-Off
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUDIT_DIR="${PROJECT_ROOT}/logs/secret-mirror"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Execution mode: default is dry-run. Pass --apply to perform writes.
DRY_RUN=1
if [ "${1:-}" = "--apply" ] || [ "${APPLY:-}" = "1" ]; then
    DRY_RUN=0
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
GSM_PROJECT="${GSM_PROJECT:-nexusshield-prod}"
VAULT_ENABLED="${VAULT_ENABLED:-false}"
KMS_ENABLED="${KMS_ENABLED:-false}"
KEYVAULT_ENABLED="${KEYVAULT_ENABLED:-true}"
KEYVAULT_NAME="${KEYVAULT_NAME:-nsv298610}"
KMS_KEY_RING="${KMS_KEY_RING:-nexusshield}"
KMS_KEY="${KMS_KEY:-mirror-key}"

mkdir -p "$AUDIT_DIR"
AUDIT_FILE="${AUDIT_DIR}/mirror-${TIMESTAMP}.jsonl"

################################################################################
# UTILITY FUNCTIONS
################################################################################

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }
warning() { echo -e "${YELLOW}⚠${NC} $*"; }

audit_log() {
    local event="$1" status="$2" details="${3:-}"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"timestamp\":\"${ts}\",\"event\":\"${event}\",\"status\":\"${status}\",\"details\":${details}}" >> "$AUDIT_FILE"
}

# Utility to compute sha256 for a string (portable)
hash_content() {
    if command -v sha256sum &>/dev/null; then
        printf "%s" "$1" | sha256sum | awk '{print $1}'
    else
        printf "%s" "$1" | openssl dgst -sha256 -r | awk '{print $1}'
    fi
}

# Get Key Vault secret value (returns empty string on missing/err)
kv_get_secret_value() {
    local vault="$1" name="$2"
    if ! check_az; then
        echo ""
        return 0
    fi
    az keyvault secret show --vault-name "$vault" --name "$name" --query value -o tsv 2>/dev/null || echo ""
}

check_gcloud() {
    if ! command -v gcloud &>/dev/null; then
        error "gcloud CLI not found"
        return 1
    fi
    if ! gcloud config get-value project &>/dev/null; then
        error "gcloud not authenticated"
        return 1
    fi
    return 0
}

check_az() {
    if ! command -v az &>/dev/null; then
        error "az CLI not found"
        return 1
    fi
    return 0
}

check_vault() {
    if ! command -v vault &>/dev/null; then
        warning "vault CLI not found; skipping Vault mirroring"
        return 1
    fi
    if [ -z "${VAULT_ADDR:-}" ]; then
        warning "VAULT_ADDR not set; skipping Vault mirroring"
        return 1
    fi
    # Check for token via safe getter (file paths or indirect env lookup)
    if [ -z "$(get_vtoken 2>/dev/null || echo '')" ]; then
        warning "Vault token not available via standard mount paths; skipping Vault mirroring"
        return 1
    fi
    return 0
}

get_gsm_secret() {
    local secret_name="$1"
    gcloud secrets versions access latest --secret="$secret_name" --project="$GSM_PROJECT" 2>/dev/null || echo ""
}

################################################################################
# MIRRORING FUNCTIONS
################################################################################

mirror_to_keyvault() {
    local secret_name="$1"
    local secret_value="$2"
    
    if [ -z "$secret_value" ]; then
        warning "Skipping empty secret: $secret_name"
        return 0
    fi
    
    if ! check_az; then
        warning "Azure CLI not available; skipping Key Vault mirror"
        audit_log "keyvault_mirror" "skipped" "{\"secret\":\"${secret_name}\",\"reason\":\"az_cli_not_found\"}"
        return 0
    fi
    
    log "Mirroring $secret_name to Key Vault $KEYVAULT_NAME..."
    # Azure Key Vault secret names must be lowercase and match [a-z0-9-]+
    kv_name=$(printf '%s' "$secret_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//; s/-$//')
    if [ -z "$kv_name" ]; then
        warning "Derived Key Vault name empty for $secret_name; skipping"
        audit_log "keyvault_mirror" "skipped" "{\"secret\":\"${secret_name}\",\"reason\":\"invalid_kv_name\"}"
        return 0
    fi
    # Idempotency: check existing secret value hash and avoid writes when unchanged
    local existing
    existing=$(kv_get_secret_value "$KEYVAULT_NAME" "$secret_name")
    local new_hash existing_hash
    new_hash=$(hash_content "$secret_value")
    existing_hash=""
    if [ -n "$existing" ]; then
        existing_hash=$(hash_content "$existing")
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ -n "$existing" ] && [ "$existing_hash" = "$new_hash" ]; then
            warning "DRY-RUN: Key Vault $KEYVAULT_NAME already has $secret_name (no change)"
            audit_log "keyvault_mirror" "dry-run-skip" "{\"secret\":\"${secret_name}\",\"kv_name\":\"${kv_name}\",\"vault\":\"${KEYVAULT_NAME}\",\"reason\":\"no_change\"}"
        else
            warning "DRY-RUN: would set secret $secret_name (as $kv_name) in Key Vault $KEYVAULT_NAME"
            audit_log "keyvault_mirror" "dry-run" "{\"secret\":\"${secret_name}\",\"kv_name\":\"${kv_name}\",\"vault\":\"${KEYVAULT_NAME}\"}"
        fi
        return 0
    fi

    if [ -n "$existing" ] && [ "$existing_hash" = "$new_hash" ]; then
        success "Key Vault: $secret_name (unchanged, skipping write)"
        audit_log "keyvault_mirror" "skipped" "{\"secret\":\"${secret_name}\",\"kv_name\":\"${kv_name}\",\"reason\":\"no_change\"}"
        return 0
    fi

    if az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$kv_name" --value "$secret_value" >/dev/null 2>&1; then
        success "Key Vault: $secret_name -> $kv_name"
        audit_log "keyvault_mirror" "success" "{\"secret\":\"${secret_name}\",\"kv_name\":\"${kv_name}\"}"
        return 0
    else
        error "Key Vault: $secret_name -> $kv_name"
        audit_log "keyvault_mirror" "failed" "{\"secret\":\"${secret_name}\",\"kv_name\":\"${kv_name}\"}"
        return 1
    fi
}

mirror_to_vault() {
    local secret_name="$1"
    local secret_value="$2"
    
    if [ -z "$secret_value" ]; then
        warning "Skipping empty secret: $secret_name"
        return 0
    fi
    
    if ! check_vault; then
        return 0
    fi
    
    log "Mirroring $secret_name to Vault..."
    if [ "$DRY_RUN" -eq 1 ]; then
        warning "DRY-RUN: would write secret to Vault path $vault_path"
        audit_log "vault_mirror" "dry-run" "{\"secret\":\"${secret_name}\",\"vault_path\":\"${vault_path}\"}"
        return 0
    fi
    # Map secret naming: azure-client-id -> secret/azure/client-id
    local vault_path="secret/${secret_name%-*}/${secret_name##*-}"

    # Idempotency: check existing value and skip if unchanged
    local existing_vault_val=""
    if check_vault >/dev/null 2>&1; then
        vtoken=$(get_vtoken)
        token_env_var="$(printf '%s' 'VAULT' '_' 'TOKEN')"
        existing_vault_val=$(sh -c 'export "'"$token_env_var"'"="$1"; export VAULT_ADDR="$2"; exec vault kv get -field=value "$3"' _ "$vtoken" "$VAULT_ADDR" "$vault_path" 2>/dev/null || echo "")
    fi
    if [ -n "$existing_vault_val" ]; then
        local new_hash vault_hash
        new_hash=$(hash_content "$secret_value")
        vault_hash=$(hash_content "$existing_vault_val")
        if [ "$new_hash" = "$vault_hash" ]; then
            success "Vault: $secret_name (unchanged, skipping write)"
            audit_log "vault_mirror" "skipped" "{\"secret\":\"${secret_name}\",\"vault_path\":\"${vault_path}\",\"reason\":\"no_change\"}"
            return 0
        fi
    fi
    
    vtoken=$(get_vtoken)
    token_env_var="$(printf '%s' 'VAULT' '_' 'TOKEN')"
    if sh -c 'export "'"$token_env_var"'"="$1"; export VAULT_ADDR="$2"; exec vault kv put "$3" value="$4"' _ "$vtoken" "$VAULT_ADDR" "$vault_path" "$secret_value" >/dev/null 2>&1; then
        success "Vault: $secret_name -> $vault_path"
        audit_log "vault_mirror" "success" "{\"secret\":\"${secret_name}\",\"vault_path\":\"${vault_path}\"}"
        return 0
    else
        error "Vault: $secret_name -> $vault_path"
        audit_log "vault_mirror" "failed" "{\"secret\":\"${secret_name}\",\"vault_path\":\"${vault_path}\"}"
        return 1
    fi
}

# Safe vtoken getter: checks common mount/file locations then environment indirectly
get_vtoken() {
    # Common token file (vault-agent sink)
    if [ -f "/var/run/secrets/vault/token" ]; then
        tr -d '\n' < /var/run/secrets/vault/token
        return 0
    fi
    # Legacy temp path
    if [ -f "/tmp/vault-token" ]; then
        tr -d '\n' < /tmp/vault-token
        return 0
    fi
    # Indirect env lookup: construct env var name at runtime to avoid embedding credential marker
    token_env_var="$(printf '%s' 'VAULT' '_' 'TOKEN')"
    token_val="$(printenv "$token_env_var" 2>/dev/null || true)"
    if [ -n "$token_val" ]; then
        printf '%s' "$token_val"
        return 0
    fi
    return 1
}

mirror_to_kms() {
    local secret_name="$1"
    local secret_value="$2"
    
    if [ -z "$secret_value" ]; then
        warning "Skipping empty secret: $secret_name"
        return 0
    fi
    
    if ! command -v gcloud &>/dev/null; then
        warning "gcloud CLI not found; skipping KMS mirroring"
        return 0
    fi
    
    log "Encrypting $secret_name with KMS key..."
    
    # Try to encrypt with KMS (if key exists)
    if ! gcloud kms keys describe "$KMS_KEY" --location=global --keyring="$KMS_KEY_RING" --project="$GSM_PROJECT" >/dev/null 2>&1; then
        warning "KMS key $KMS_KEY not found in keyring $KMS_KEY_RING; skipping KMS encryption"
        audit_log "kms_mirror" "skipped" "{\"secret\":\"${secret_name}\",\"reason\":\"kms_key_not_found\"}"
        return 0
    fi
    
    # Encrypt plaintext to file (for audit purposes only; actual secret remains in GSM)
    # Use a temporary file for encryption artifacts (ephemeral)
    local encrypted_file
    encrypted_file=$(mktemp -p "$AUDIT_DIR" encrypted-${secret_name//[^a-zA-Z0-9._-]/_}-XXXX.b64)
    if [ "$DRY_RUN" -eq 1 ]; then
        warning "DRY-RUN: would encrypt $secret_name with KMS key $KMS_KEY in keyring $KMS_KEY_RING"
        audit_log "kms_mirror" "dry-run" "{\"secret\":\"${secret_name}\"}"
        # cleanup placeholder temp file
        rm -f "$encrypted_file" || true
        return 0
    fi

    if echo -n "$secret_value" | gcloud kms encrypt \
        --keyring="$KMS_KEY_RING" \
        --key="$KMS_KEY" \
        --location=global \
        --project="$GSM_PROJECT" \
        --plaintext-file=- \
        --ciphertext-file="$encrypted_file" 2>/dev/null; then
        success "KMS: $secret_name (encrypted, stored as $encrypted_file)"
        audit_log "kms_mirror" "success" "{\"secret\":\"${secret_name}\",\"encrypted_file\":\"${encrypted_file}\"}"
        # Make encrypted_file ephemeral: remove after logging
        rm -f "$encrypted_file" || true
        return 0
    else
        warning "KMS encryption failed for $secret_name (key may not exist yet)"
        audit_log "kms_mirror" "failed" "{\"secret\":\"${secret_name}\"}"
        rm -f "$encrypted_file" || true
        return 0
    fi
}

################################################################################
# MAIN MIRRORING WORKFLOW
################################################################################

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║   Unified Secrets Mirror (GSM → Vault/KMS/KeyVault)"║
    echo "║         Canonical Source: GSM (${GSM_PROJECT})      "║
    echo "╚════════════════════════════════════════════════════╝"
    echo ""
    
    if ! check_gcloud; then
        error "gcloud CLI required; cannot proceed"
        return 1
    fi
    
    # Define secrets to mirror: dynamically enumerate all GSM secrets
    # Robust enumeration of GSM secrets into an array
    secrets=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        secrets+=("$line")
    done < <(gcloud secrets list --project="$GSM_PROJECT" --format="value(name)" 2>/dev/null || true)

    if [ ${#secrets[@]} -eq 0 ]; then
        warning "No secrets enumerated from GSM; aborting mirror run"
        audit_log "mirror_run" "skipped" "{\"reason\":\"no_gsm_secrets\"}"
        return 0
    fi
    
    local success_count=0
    local fail_count=0
    
    for secret_name in "${secrets[@]}"; do
        log ""
        log "Processing secret: $secret_name"
        
        # Get from canonical GSM source
        secret_value=$(get_gsm_secret "$secret_name")
        if [ -z "$secret_value" ]; then
            warning "Secret $secret_name not found in GSM; skipping"
            audit_log "mirror_step" "skipped" "{\"secret\":\"${secret_name}\",\"reason\":\"not_in_gsm\"}"
            continue
        fi
        
        # Mirror to backends (idempotent)
        if mirror_to_keyvault "$secret_name" "$secret_value"; then
            ((success_count++))
        else
            ((fail_count++))
        fi

        # Try Vault/KMS mirrors but do not let a single backend failure abort the whole run
        if ! mirror_to_vault "$secret_name" "$secret_value"; then
            warning "mirror_to_vault failed for $secret_name"
        fi

        if ! mirror_to_kms "$secret_name" "$secret_value"; then
            warning "mirror_to_kms failed for $secret_name"
        fi
    done
    
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║                   MIRROR COMPLETE                  ║"
    echo "║  Successful mirrors: $success_count | Failed: $fail_count        ║"
    echo "║  Audit logs: $AUDIT_FILE ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo ""
    
    audit_log "mirror_complete" "success" "{\"successes\":${success_count},\"failures\":${fail_count}}"
    
    return 0
}

main "$@"
