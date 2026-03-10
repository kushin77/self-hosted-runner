#!/bin/bash
# credential-rotation-automation.sh
# Automated multi-layer credential rotation (GSM → Vault → KMS)
# No GitHub Actions. Direct deployment. Immutable audit trail.
# This script runs as a systemd timer on production hosts.

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT_DIR="${REPO_ROOT}/logs/credential-rotation"
AUDIT_FILE="${AUDIT_DIR}/audit.jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME=$(hostname)
DEPLOYED_ENV="${DEPLOYED_ENV:-production}"

# Credential layers (priority order)
declare -a CRED_LAYERS=("gsm" "vault" "kms" "aws")
ROTATION_INTERVAL_HOURS=24
CACHE_VALIDITY_HOURS=1

# Metrics
ROTATION_START_TIME=$(date +%s)

# ============================================================================
# Initialization
# ============================================================================
mkdir -p "${AUDIT_DIR}"
touch "${AUDIT_FILE}"

init_audit_entry() {
    local entry="{
  \"timestamp\": \"${TIMESTAMP}\",
  \"hostname\": \"${HOSTNAME}\",
  \"environment\": \"${DEPLOYED_ENV}\",
  \"event\": \"credential_rotation_start\",
  \"runner_id\": \"$(hostname -f)\",
  \"status\": \"initiated\",
  \"immutable\": true
}"
    echo "${entry}" >> "${AUDIT_FILE}"
}

# ============================================================================
# Credential Fetching (4-layer fallback)
# ============================================================================
fetch_credential() {
    local secret_name="$1"
    local credential=""
    local layer_used=""

    # Layer 1: GCP Secret Manager
    if credential=$(gcloud secrets versions access latest --secret="${secret_name}" 2>/dev/null); then
        layer_used="gsm"
        echo "GSM:${credential}"
        return 0
    fi

    # Layer 2: HashiCorp Vault
    if command -v vault &>/dev/null && vault login -path=auth/jwt -method=jwt &>/dev/null 2>&1; then
        if credential=$(vault kv get -field=value "secret/${secret_name}" 2>/dev/null); then
            layer_used="vault"
            echo "VAULT:${credential}"
            return 0
        fi
    fi

    # Layer 3: AWS KMS
    if command -v aws &>/dev/null; then
        if credential=$(aws secretsmanager get-secret-value --secret-id "${secret_name}" --query SecretString --output text 2>/dev/null); then
            layer_used="kms"
            echo "KMS:${credential}"
            return 0
        fi
    fi

    # Layer 4: Local encrypted cache (offline fallback)
    local cache_file="${AUDIT_DIR}/.cache/${secret_name}.enc"
    if [[ -f "${cache_file}" ]]; then
        if credential=$(openssl enc -d -aes-256-cbc -in "${cache_file}" -k "${CACHE_KEY}" 2>/dev/null); then
            layer_used="cache"
            echo "CACHE:${credential}"
            return 0
        fi
    fi

    # All layers exhausted
    exit_with_error "credential_fetch_failed" "Could not fetch ${secret_name} from any layer"
}

# ============================================================================
# Rotation Logic
# ============================================================================
rotate_credential() {
    local secret_name="$1"
    local new_value=$(openssl rand -hex 32)
    
    # Primary: GCP Secret Manager
    if gcloud secrets versions add "${secret_name}" --data-file=<(echo -n "${new_value}") 2>/dev/null; then
        audit_log "credential_rotated" "secret=${secret_name} layer=gsm version=$(gcloud secrets versions list ${secret_name} --limit=1 --format='value(name)')"
        
        # Cache it for offline fallback
        mkdir -p "${AUDIT_DIR}/.cache"
        echo -n "${new_value}" | openssl enc -aes-256-cbc -out "${AUDIT_DIR}/.cache/${secret_name}.enc" -k "${CACHE_KEY}" 2>/dev/null || true
        
        return 0
    fi

    # Fallback to Vault
    if command -v vault &>/dev/null; then
        vault kv put "secret/${secret_name}" value="${new_value}" 2>/dev/null && return 0
    fi

    # Fallback to AWS KMS
    if command -v aws &>/dev/null; then
        aws secretsmanager put-secret-value --secret-id "${secret_name}" --secret-string "${new_value}" 2>/dev/null && return 0
    fi

    exit_with_error "rotation_failed" "Could not rotate ${secret_name}"
}

# ============================================================================
# Audit Logging (Immutable)
# ============================================================================
audit_log() {
    local event="$1"
    local details="${2:-}"
    local entry=$(cat <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "hostname": "${HOSTNAME}",
  "environment": "${DEPLOYED_ENV}",
  "event": "${event}",
  "details": "${details}",
  "immutable": true,
  "hash": "$(echo -n "${event}:${details}" | sha256sum | awk '{print $1}')"
}
EOF
)
    echo "${entry}" >> "${AUDIT_FILE}"
}

exit_with_error() {
    local event="$1"
    local message="$2"
    audit_log "${event}" "${message}"
    echo "ERROR: ${message}" >&2
    exit 1
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
    init_audit_entry
    
    # List of critical secrets to rotate
    local secrets=(
        "runner_ssh_key"
        "runner_ssh_user"
        "database_secret"
        "api_bearer_token"
        "vault_unlock_key"
    )

    local rotated=0
    local failed=0

    for secret in "${secrets[@]}"; do
        if rotate_credential "${secret}"; then
            ((rotated++))
            audit_log "rotation_success" "secret=${secret}"
        else
            ((failed++))
            audit_log "rotation_failed" "secret=${secret}"
        fi
    done

    # Final status
    local duration=$(($(date +%s) - ROTATION_START_TIME))
    audit_log "rotation_complete" "rotated=${rotated} failed=${failed} duration_seconds=${duration}"
    
    # Push audit to git (immutable record)
    cd "${REPO_ROOT}"
    if git diff --quiet "${AUDIT_FILE}" 2>/dev/null; then
        git add "${AUDIT_FILE}"
        git commit -m "security: credential rotation audit ($(date -u +%Y-%m-%d_%H:%M:%SZ)) - ${rotated} rotated, ${failed} failed" || true
        git push origin main || true
    fi

    [[ ${failed} -eq 0 ]] && audit_log "rotation_status" "ok" || exit 1
}

main "$@"
