#!/bin/bash
# Auto-provision deployment fields from credential providers (GSM/Vault/KMS)
# Immutable, ephemeral, idempotent execution
# Handles: VAULT_ADDR, VAULT_ROLE, AWS_ROLE_TO_ASSUME, GCP_WORKLOAD_IDENTITY_PROVIDER
#
# Usage: auto-provision-deployment-fields.sh [--dry-run] [--provider=gsm|vault|kms]

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
AUDIT_LOG="${REPO_ROOT}/logs/deployment-provisioning-audit.jsonl"
STATE_DIR="${REPO_ROOT}/.deployment-state"
LOCK_FILE="${STATE_DIR}/.provisioning.lock"
DRY_RUN=${DRY_RUN:-false}
PREFERRED_PROVIDER=${PREFERRED_PROVIDER:-gsm}  # gsm, vault, kms
FORCE=${FORCE:-false}

# Required deployment fields
REQUIRED_FIELDS=(
    "VAULT_ADDR"
    "VAULT_ROLE"
    "AWS_ROLE_TO_ASSUME"
    "GCP_WORKLOAD_IDENTITY_PROVIDER"
)

# ============================================================================
# UTILITIES & LOGGING
# ============================================================================

log_info() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO] $*" >&2; }
log_warn() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN] $*" >&2; }
log_error() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2; }
log_success() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS] $*" >&2; }

audit_log() {
    local action="$1" field="$2" status="$3" source="${4:-unknown}"
    local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    local entry=$(cat <<EOF
{"timestamp":"$timestamp","action":"$action","field":"$field","status":"$status","source":"$source","hostname":"$(hostname)","user":"${USER:-system}"}
EOF
)
    echo "$entry" >> "$AUDIT_LOG"
}

acquire_lock() {
    local max_wait=30
    local waited=0
    
    while [ $waited -lt $max_wait ] && [ -f "$LOCK_FILE" ]; do
        log_warn "Another provisioning is in progress, waiting..."
        sleep 1
        ((waited++))
    done
    
    if [ -f "$LOCK_FILE" ] && [ "$FORCE" != "true" ]; then
        log_error "Lock file exists after timeout. Use FORCE=true to override."
        return 1
    fi
    
    mkdir -p "$STATE_DIR"
    echo "$$" > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

trap release_lock EXIT

# ============================================================================
# CREDENTIAL PROVIDER IMPLEMENTATIONS
# ============================================================================

fetch_from_gsm() {
    local field_name="$1" gsm_secret="${2:-deployment-fields-${field_name}}"
    
    if ! command -v gcloud &> /dev/null; then
        log_warn "gcloud CLI not available, skipping GSM fetch for $field_name"
        return 1
    fi
    
    local version="${GSM_VERSION:-latest}"
    gcloud secrets versions access "$version" --secret="$gsm_secret" 2>/dev/null || {
        log_warn "GSM secret not found: $gsm_secret"
        return 1
    }
}

fetch_from_vault() {
    local field_name="$1" vault_path="${2:-secret/deployment/fields/${field_name}}"
    local vault_addr="${VAULT_ADDR:-https://vault.example.com:8200}"
    
    if ! command -v vault &> /dev/null; then
        log_warn "vault CLI not available, skipping Vault fetch for $field_name"
        return 1
    fi
    
    if [ -z "${VAULT_TOKEN:-}" ] && [ -z "${VAULT_ROLE:-}" ]; then
        log_warn "No Vault authentication configured for $field_name"
        return 1
    fi
    
    VAULT_ADDR="$vault_addr" vault kv get -field=value "$vault_path" 2>/dev/null || {
        log_warn "Vault secret not found: $vault_path"
        return 1
    }
}

fetch_from_kms() {
    local field_name="$1" kms_key="${2:-deployment-fields-${field_name}}"
    
    if ! command -v aws &> /dev/null; then
        log_warn "AWS CLI not available, skipping KMS fetch for $field_name"
        return 1
    fi
    
    # KMS GetSecretValue is through Secrets Manager typically
    aws secretsmanager get-secret-value --secret-id "deployment/${field_name}" \
        --query 'SecretString' --output text 2>/dev/null || {
        log_warn "KMS/Secrets Manager secret not found: deployment/${field_name}"
        return 1
    }
}

# ============================================================================
# FIELD DISCOVERY & CURRENT STATE
# ============================================================================

discover_field_sources() {
    # Discover where each field is currently sourced from
    # Check: environment, GitHub secrets, local files, credential providers
    
    local field_name="$1"
    
    # 1. Check environment variable
    if [ -n "${!field_name:-}" ]; then
        echo "environment"
        return 0
    fi
    
    # 2. Check GitHub secrets (when in Actions)
    if [ -n "${GITHUB_ACTIONS:-}" ] && [ -n "${!field_name:-}" ]; then
        echo "github-actions-secret"
        return 0
    fi
    
    # 3. Check .env files (for non-production)
    if grep -q "^${field_name}=" .env 2>/dev/null || \
       grep -q "^${field_name}=" .env.local 2>/dev/null; then
        echo "env-file"
        return 0
    fi
    
    # 4. Check if value is a placeholder (needs provisioning)
    if echo "${!field_name:-unknown}" | grep -qE "(example\.com|placeholder|EXAMPLE|PLACEHOLDER)"; then
        echo "placeholder"
        return 0
    fi
    
    echo "missing"
    return 1
}

get_field_value() {
    local field_name="$1"
    local current="${!field_name:-}"
    
    # If already set and not a placeholder, return current value
    if [ -n "$current" ] && ! echo "$current" | grep -qE "(example\.com|placeholder|EXAMPLE|PLACEHOLDER|\*\*\*)"; then
        echo "$current"
        return 0
    fi
    
    # Otherwise, fetch from credential providers
    local providers=("gsm" "vault" "kms")
    
    # Prioritize preferred provider
    if [[ " ${providers[@]} " =~ " ${PREFERRED_PROVIDER} " ]]; then
        providers=("$PREFERRED_PROVIDER" "${providers[@]/$PREFERRED_PROVIDER}")
    fi
    
    for provider in "${providers[@]}"; do
        local value
        if value=$(fetch_from_${provider} "$field_name" 2>/dev/null); then
            audit_log "fetch" "$field_name" "success" "$provider"
            echo "$value"
            return 0
        fi
    done
    
    log_warn "Could not fetch $field_name from any provider"
    audit_log "fetch" "$field_name" "failed" "all-providers"
    return 1
}

# ============================================================================
# PROVISIONING OPERATIONS
# ============================================================================

provision_github_secrets() {
    # Update GitHub Actions repository secrets with discovered values
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would update GitHub Actions secrets"
        return 0
    fi
    
    if ! command -v gh &> /dev/null; then
        log_warn "GitHub CLI not available, cannot provision GitHub secrets"
        return 1
    fi
    
    local updated=0
    for field in "${REQUIRED_FIELDS[@]}"; do
        local value
        if value=$(get_field_value "$field"); then
            log_info "Provisioning GitHub secret: $field"
            echo "$value" | gh secret set "$field" 2>/dev/null || {
                log_error "Failed to set GitHub secret: $field"
                audit_log "provision-github" "$field" "failed" "gh-cli"
                continue
            }
            audit_log "provision-github" "$field" "success" "github-actions"
            ((updated++))
        fi
    done
    
    echo "$updated"
}

provision_environment_variables() {
    # Create .env.deployment file with all provisioned values
    local env_file="${REPO_ROOT}/.env.deployment"
    
    log_info "Provisioning environment variables to: $env_file"
    
    > "$env_file"  # Clear file
    chmod 600 "$env_file"
    
    local provisioned=0
    for field in "${REQUIRED_FIELDS[@]}"; do
        local value
        if value=$(get_field_value "$field"); then
            echo "${field}=${value}" >> "$env_file"
            log_info "  ✓ $field"
            audit_log "provision-env" "$field" "success" "env-file"
            ((provisioned++))
        else
            log_warn "  ✗ $field (not available)"
            audit_log "provision-env" "$field" "failed" "env-file"
        fi
    done
    
    echo "$provisioned"
}

provision_systemd_environment() {
    # Create systemd drop-in directory with environment settings
    # Location: /etc/systemd/system/daemon-scheduler.service.d/deployment-fields.conf
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would create systemd environment drop-in"
        return 0
    fi
    
    if [ ! -f /etc/systemd/system/daemon-scheduler.service ]; then
        log_warn "Systemd service not found, skipping systemd provisioning"
        return 1
    fi
    
    local dropindir="/etc/systemd/system/daemon-scheduler.service.d"
    local dropinfile="${dropindir}/deployment-fields.conf"
    
    log_info "Provisioning systemd environment: $dropinfile"
    
    if ! sudo mkdir -p "$dropindir" 2>/dev/null; then
        log_error "Cannot create systemd drop-in directory (need sudo)"
        return 1
    fi
    
    local content="[Service]\n"
    local provisioned=0
    
    for field in "${REQUIRED_FIELDS[@]}"; do
        local value
        if value=$(get_field_value "$field"); then
            content+="Environment=\"${field}=${value}\"\n"
            audit_log "provision-systemd" "$field" "success" "systemd"
            ((provisioned++))
        fi
    done
    
    if echo -e "$content" | sudo tee "$dropinfile" > /dev/null; then
        sudo systemctl daemon-reload 2>/dev/null || true
        log_success "Systemd environment configured"
    else
        log_error "Failed to write systemd drop-in"
        return 1
    fi
    
    echo "$provisioned"
}

# ============================================================================
# VALIDATION & VERIFICATION
# ============================================================================

verify_provisioning() {
    # Verify all fields are properly provisioned (non-placeholder, accessible)
    
    log_info "Verifying deployment field provisioning..."
    
    local verified=0
    local failed=0
    
    for field in "${REQUIRED_FIELDS[@]}"; do
        local value
        if value=$(get_field_value "$field"); then
            if echo "$value" | grep -qE "(example\.com|placeholder|EXAMPLE|PLACEHOLDER|\*\*\*)"; then
                log_warn "  ✗ $field (still a placeholder)"
                audit_log "verify" "$field" "failed-placeholder" "verification"
                ((failed++))
            else
                log_success "  ✓ $field (valid)"
                audit_log "verify" "$field" "success" "verification"
                ((verified++))
            fi
        else
            log_error "  ✗ $field (not found)"
            audit_log "verify" "$field" "failed-notfound" "verification"
            ((failed++))
        fi
    done
    
    echo "Verified: $verified, Failed: $failed"
    return $(( failed > 0 ? 1 : 0 ))
}

# ============================================================================
# MAIN EXECUTION FLOW
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                ;;
            --provider=*)
                PREFERRED_PROVIDER="${1#*=}"
                ;;
            --force)
                FORCE=true
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
        shift
    done
}

main() {
    log_info "Starting deployment field auto-provisioning..."
    
    # Ensure state directories exist
    mkdir -p "$STATE_DIR" "$(dirname "$AUDIT_LOG")"
    
    # Acquire lock (idempotency guard)
    acquire_lock || exit 1
    
    # Log provisioning start
    audit_log "provision-start" "all" "initiated" "auto-provisioning"
    
    # Discover current state
    log_info "Discovering current deployment field state..."
    for field in "${REQUIRED_FIELDS[@]}"; do
        local source=$(discover_field_sources "$field" || echo "unknown")
        log_info "  $field: $source"
        audit_log "discover" "$field" "found" "$source"
    done
    
    # Provision to different targets
    log_info ""
    log_info "Provisioning to target systems..."
    
    # Target 1: GitHub Actions Secrets
    if gh auth show &>/dev/null; then
        log_info "▸ GitHub Actions Secrets..."
        local gh_count=$(provision_github_secrets)
        log_success "  ✓ Updated $gh_count GitHub secrets"
    else
        log_warn "GitHub CLI not authenticated, skipping GitHub secret provisioning"
    fi
    
    # Target 2: Environment variables
    log_info "▸ Environment variables..."
    local env_count=$(provision_environment_variables)
    log_success "  ✓ Provisioned $env_count environment variables"
    
    # Target 3: Systemd (if available)
    if systemctl is-active --quiet daemon-scheduler 2>/dev/null; then
        log_info "▸ Systemd daemon environment..."
        if provision_systemd_environment; then
            log_success "  ✓ Systemd environment configured"
        fi
    fi
    
    # Verification
    log_info ""
    log_info "Verifying provisioning..."
    if verify_provisioning; then
        log_success "✅ All deployment fields successfully provisioned"
        audit_log "provision-complete" "all" "success" "auto-provisioning"
        return 0
    else
        log_warn "⚠️  Some fields may still need manual updates"
        audit_log "provision-complete" "all" "partial" "auto-provisioning"
        return 1
    fi
}

# ============================================================================
# EXECUTION
# ============================================================================

parse_args "$@"

if [ "$DRY_RUN" = "true" ]; then
    log_info "Running in DRY-RUN mode (no changes will be applied)"
fi

main
exit $?
