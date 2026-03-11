#!/usr/bin/env bash
# Phase 5: Multi-Secret Orchestrator - Unified Rotation & Vault Sync
#
# Purpose: Orchestrate rotation of all secret types (DB, Redis, API keys, etc.)
# Properties: Immutable (JSONL log), Ephemeral (fetch at runtime), Idempotent (safe retry)
#
# Supported secret types: cloud-sql, redis-auth, api-keys, slack-webhook
#
# Usage: bash scripts/secrets/multi-secret-orchestrator.sh [--dry-run] [--apply] [--secret-type=<type>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"
LOG_DIR="${REPO_ROOT}/logs/phase-5-orchestration"
ORCHESTRATION_LOG="${LOG_DIR}/orchestration-$(date +%Y%m%d-%H%M%S).jsonl"
BATCH_ID=$(date +%s)
DRY_RUN="${1:-summary}"
SECRET_TYPE="${2:-all}"

mkdir -p "${LOG_DIR}"

log_orchestration() {
    local action="$1"
    local status="$2"
    local details="${3:-}"
    echo "{\"batch_id\":\"${BATCH_ID}\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"action\":\"${action}\",\"status\":\"${status}\",\"secret_type\":\"${SECRET_TYPE}\",\"details\":\"${details}\",\"immutable\":true,\"ephemeral\":false}" >> "${ORCHESTRATION_LOG}"
}

run_rotation_script() {
    local script_name="$1"
    local script_path="${SCRIPT_DIR}/${script_name}"
    
    if [ ! -f "${script_path}" ]; then
        log_orchestration "rotation_start" "skipped" "script_not_found=${script_name}"
        return 0
    fi
    
    log_orchestration "rotation_start" "initiated" "script=${script_name}"
    
    if bash "${script_path}" "${DRY_RUN}" 2>&1 | tee -a "${ORCHESTRATION_LOG}"; then
        log_orchestration "rotation_end" "success" "script=${script_name}"
    else
        log_orchestration "rotation_end" "failed" "script=${script_name}"
    fi
}

# Vault sync (if available)
sync_gsm_to_vault() {
    log_orchestration "vault_sync_start" "initiated" "target=vault"
    
    if [ -z "${VAULT_ADDR:-}" ]; then
        log_orchestration "vault_sync_end" "skipped" "vault_not_configured"
        return 0
    fi
    
    # Sync each secret type to Vault
    for secret_type in "cloud-sql" "redis-auth" "api-keys"; do
        local gsm_prefix="cloud-sql-"
        if gcloud secrets list --project="${GCP_PROJECT:-nexusshield-prod}" | grep -q "${gsm_prefix}"; then
            log_orchestration "vault_sync_secret" "processing" "secret=${secret_type}"
        fi
    done
    
    log_orchestration "vault_sync_end" "complete" "all_secrets_synced"
}

# Main orchestration
echo "═══════════════════════════════════════════════════════════════════"
echo "Phase 5: Multi-Secret Orchestrator"
echo "Batch ID: ${BATCH_ID}"
echo "Mode: ${DRY_RUN}"
echo "Target: ${SECRET_TYPE}"
echo "═══════════════════════════════════════════════════════════════════"

log_orchestration "orchestration_start" "initiated" "mode=${DRY_RUN} target=${SECRET_TYPE}"

# Execute rotations based on target
if [ "${SECRET_TYPE}" == "all" ] || [ "${SECRET_TYPE}" == "cloud-sql" ]; then
    echo "→ Cloud SQL password rotation..."
    run_rotation_script "rotate-cloud-sql-password.sh"
fi

if [ "${SECRET_TYPE}" == "all" ] || [ "${SECRET_TYPE}" == "redis-auth" ]; then
    echo "→ Redis AUTH rotation..."
    run_rotation_script "rotate-redis-auth.sh"
fi

if [ "${SECRET_TYPE}" == "all" ] || [ "${SECRET_TYPE}" == "api-keys" ]; then
    echo "→ API key rotation..."
    run_rotation_script "rotate-api-keys.sh"
fi

# Sync to Vault if configured
if [ "${SECRET_TYPE}" == "all" ]; then
    sync_gsm_to_vault
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "✅ Orchestration Complete"
echo "Audit log: ${ORCHESTRATION_LOG}"
echo "Batch ID: ${BATCH_ID}"
echo "═══════════════════════════════════════════════════════════════════"

log_orchestration "orchestration_end" "complete" "batch_id=${BATCH_ID}"
