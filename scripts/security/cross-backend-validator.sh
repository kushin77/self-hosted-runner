#!/bin/bash

################################################################################
# Cross-Backend Credential Validator
# Ensures GSM → Vault → KMS mirrors contain identical content
# Detects tampering, sync failures, and corruption
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATION_LOG="${PROJECT_ROOT}/logs/governance/cross-backend-validation.jsonl"

mkdir -p "$(dirname "$VALIDATION_LOG")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }
warning() { echo -e "${YELLOW}⚠${NC} $*"; }

audit_log() {
    local secret="$1" backend1="$2" backend2="$3" status="$4" hash1="${5:-}" hash2="${6:-}"
    printf '{"timestamp":"%s","secret":"%s","backend1":"%s","backend2":"%s","status":"%s","hash1":"%s","hash2":"%s"}\n' \
        "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$secret" "$backend1" "$backend2" "$status" "$hash1" "$hash2" >> "$VALIDATION_LOG"
}

################################################################################
# BACKEND ACCESSORS
################################################################################

get_gsm_secret() {
    local secret_name="$1"
    local project="${2:-nexusshield-prod}"
    gcloud secrets versions access latest --secret="$secret_name" --project="$project" 2>/dev/null || echo ""
}

get_vault_secret() {
    local secret_path="$1"
    local vault_addr="${VAULT_ADDR:-}"
    
    if [ -z "$vault_addr" ]; then
        warning "VAULT_ADDR not set"
        return 1
    fi
    
    vault kv get -field=value "$secret_path" 2>/dev/null || return 1
}

get_keyvault_secret() {
    local secret_name="$1"
    local vault_name="$2"
    
    if ! command -v az >/dev/null; then
        warning "az CLI not found"
        return 1
    fi
    
    az keyvault secret show --vault-name "$vault_name" --name "$secret_name" --query value -o tsv 2>/dev/null || return 1
}

################################################################################
# VALIDATION FUNCTIONS
################################################################################

# Hash secret for comparison (prevents content exposure in logs)
hash_secret() {
    local content="$1"
    echo -n "$content" | sha256sum | awk '{print $1}'
}

# Validate GSM ↔ Vault consistency
validate_gsm_vault() {
    local secret_name="$1"
    local vault_path="${2:-.}"
    local project="${3:-nexusshield-prod}"
    
    log "Validating GSM → Vault for: $secret_name"
    
    local gsm_value=$(get_gsm_secret "$secret_name" "$project")
    if [ -z "$gsm_value" ]; then
        error "GSM secret not found: $secret_name"
        audit_log "$secret_name" "GSM" "Vault" "FAIL_GSM_NOT_FOUND" "" ""
        return 1
    fi
    
    local vault_value=$(get_vault_secret "$vault_path")
    if [ -z "$vault_value" ]; then
        error "Vault secret not found: $vault_path"
        audit_log "$secret_name" "GSM" "Vault" "FAIL_VAULT_NOT_FOUND" "" ""
        return 1
    fi
    
    local hash_gsm=$(hash_secret "$gsm_value")
    local hash_vault=$(hash_secret "$vault_value")
    
    if [ "$hash_gsm" != "$hash_vault" ]; then
        error "MISMATCH: GSM and Vault have different content for $secret_name"
        audit_log "$secret_name" "GSM" "Vault" "FAIL_CONTENT_MISMATCH" "$hash_gsm" "$hash_vault"
        return 1
    fi
    
    success "GSM ↔ Vault: Consistent (hash: ${hash_gsm:0:8}...)"
    audit_log "$secret_name" "GSM" "Vault" "PASS" "$hash_gsm" "$hash_vault"
    return 0
}

# Validate GSM ↔ Key Vault consistency
validate_gsm_keyvault() {
    local secret_name="$1"
    local keyvault_name="${2:-nsv298610}"
    local project="${3:-nexusshield-prod}"
    
    log "Validating GSM → Key Vault for: $secret_name"
    
    local gsm_value=$(get_gsm_secret "$secret_name" "$project")
    if [ -z "$gsm_value" ]; then
        error "GSM secret not found: $secret_name"
        audit_log "$secret_name" "GSM" "KeyVault" "FAIL_GSM_NOT_FOUND" "" ""
        return 1
    fi
    
    local keyvault_value=$(get_keyvault_secret "$secret_name" "$keyvault_name")
    if [ -z "$keyvault_value" ]; then
        error "Key Vault secret not found: $secret_name"
        audit_log "$secret_name" "GSM" "KeyVault" "FAIL_KEYVAULT_NOT_FOUND" "" ""
        return 1
    fi
    
    local hash_gsm=$(hash_secret "$gsm_value")
    local hash_keyvault=$(hash_secret "$keyvault_value")
    
    if [ "$hash_gsm" != "$hash_keyvault" ]; then
        error "MISMATCH: GSM and Key Vault have different content for $secret_name"
        audit_log "$secret_name" "GSM" "KeyVault" "FAIL_CONTENT_MISMATCH" "$hash_gsm" "$hash_keyvault"
        return 1
    fi
    
    success "GSM ↔ Key Vault: Consistent (hash: ${hash_gsm:0:8}...)"
    audit_log "$secret_name" "GSM" "KeyVault" "PASS" "$hash_gsm" "$hash_keyvault"
    return 0
}

# Validate all backends for a secret
validate_all_backends() {
    local secret_name="$1"
    
    log "Cross-backend validation for: $secret_name"
    
    local failed=0
    
    # Validate GSM (canonical) against mirrors
    validate_gsm_vault "$secret_name" "secret/$secret_name" || failed=$((failed + 1))
    validate_gsm_keyvault "$secret_name" "nsv298610" || failed=$((failed + 1))
    
    if [ $failed -gt 0 ]; then
        error "Validation failed for $secret_name with $failed error(s)"
        return 1
    fi
    
    success "All backends consistent for $secret_name"
    return 0
}

################################################################################
# BULK VALIDATION
################################################################################

validate_all_secrets() {
    local project="${1:-nexusshield-prod}"
    
    log "=== CROSS-BACKEND CREDENTIAL VALIDATION ==="
    log "Project: $project"
    echo
    
    # List all secrets in GSM
    local secrets=$(gcloud secrets list --project="$project" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -z "$secrets" ]; then
        error "No GSM secrets found in project $project"
        return 1
    fi
    
    local total=0
    local passed=0
    local failed=0
    
    while IFS= read -r secret_name; do
        total=$((total + 1))
        
        if validate_all_backends "$secret_name"; then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
        fi
    done <<< "$secrets"
    
    echo
    echo "╔═══════════════════════════════════════╗"
    echo "║   VALIDATION RESULTS                  ║"
    echo "╠═══════════════════════════════════════╣"
    echo "║ Total:  $total                                 ║"
    echo "║ Passed: $passed                                 ║"
    echo "║ Failed: $failed                                 ║"
    echo "╚═══════════════════════════════════════╝"
    
    if [ $failed -gt 0 ]; then
        error "Cross-backend validation FAILED for $failed secret(s)"
        return 1
    fi
    
    success "All $total secrets validated across all backends ✓"
    return 0
}

################################################################################
# MAIN
################################################################################

main() {
    if [ $# -eq 0 ]; then
        # Default: validate all secrets
        validate_all_secrets "nexusshield-prod"
    elif [ "$1" = "--secret" ] && [ $# -ge 2 ]; then
        # Validate specific secret
        validate_all_backends "$2"
    else
        echo "Usage: $0 [--secret <name>]"
        echo "Default: validates all GSM secrets against Vault and Key Vault"
        exit 1
    fi
}

main "$@"
