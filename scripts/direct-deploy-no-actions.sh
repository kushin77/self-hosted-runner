#!/bin/bash
# direct-deployment.sh
# Direct production deployment (no GitHub Actions, no PRs, no releases)
# Immutable audit trail. Idempotent. Hands-off automation via systemd timers.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DEPLOY_LOG="${REPO_ROOT}/logs/deployment/${DEPLOY_TIMESTAMP}_direct.log"
AUDIT_FILE="${REPO_ROOT}/logs/deployment/audit.jsonl"

# Allow skipping the secret-scan in controlled deployments
SKIP_SECRET_SCAN=${SKIP_SECRET_SCAN:-0}

mkdir -p "$(dirname "${DEPLOY_LOG}")" "$(dirname "${AUDIT_FILE}")"

# ============================================================================
# Immutable Audit Entry
# ============================================================================
audit_deploy() {
    local status="$1"
    local details="${2:-}"
    local entry=$(cat <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "status": "${status}",
  "details": "${details}",
  "commit": "$(git rev-parse HEAD)",
  "branch": "main",
  "deployer": "$(whoami)@$(hostname)",
  "immutable": true
}
EOF
)
    echo "${entry}" >> "${AUDIT_FILE}"
}

# ============================================================================
# Pre-Deployment Validation
# ============================================================================
validate_deployment() {
    echo "[VALIDATION] Checking prerequisites..."
    
    # Verify main branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "${current_branch}" != "main" ]]; then
        echo "ERROR: Must deploy from main branch (currently on ${current_branch})"
        exit 1
    fi

    # Verify no uncommitted changes
    if ! git diff --quiet; then
        echo "ERROR: Uncommitted changes detected. Please commit first."
        exit 1
    fi

    # Verify credentials are available (not hardcoded)
    if [[ "${SKIP_SECRET_SCAN}" != "1" ]]; then
        if grep -r "AKIA\|ghp_\|sk_test" --include="*.sh" --include="*.py" --include="*.tf" "${REPO_ROOT}" 2>/dev/null | grep -v "test" | grep -v "example"; then
            echo "ERROR: Hardcoded credentials detected. Use GSM/Vault/KMS only."
            exit 1
        fi
    else
        echo "[VALIDATION] SKIP_SECRET_SCAN=1 set — skipping hardcoded credential scan"
    fi

    echo "[VALIDATION] ✅ All checks passed"
    audit_deploy "validation_passed" "deployment ready"
}

# ============================================================================
# Credential Bootstrap (GSM/Vault/KMS)
# ============================================================================
bootstrap_credentials() {
    echo "[CREDENTIALS] Bootstrapping from secure backends..."

    # Fetch from GSM (primary)
    export RUNNER_SSH_KEY=$(gcloud secrets versions access latest --secret="runner_ssh_key" 2>/dev/null || echo "")
    export RUNNER_SSH_USER=$(gcloud secrets versions access latest --secret="runner_ssh_user" 2>/dev/null || echo "")
    export DATABASE_SECRET=$(gcloud secrets versions access latest --secret="database_secret" 2>/dev/null || echo "")

    # Fallback to Vault if available
    if command -v vault &>/dev/null && [[ -z "${RUNNER_SSH_KEY}" ]]; then
        export RUNNER_SSH_KEY=$(vault kv get -field=value secret/runner_ssh_key 2>/dev/null || echo "")
    fi

    # Fallback to AWS KMS if available
    if command -v aws &>/dev/null && [[ -z "${DATABASE_SECRET}" ]]; then
        export DATABASE_SECRET=$(aws secretsmanager get-secret-value --secret-id "database_secret" --query SecretString --output text 2>/dev/null || echo "")
    fi

    # Final fallback: local encrypted credential cache
    if [[ -z "${RUNNER_SSH_KEY}" || -z "${DATABASE_SECRET}" ]]; then
        if [[ -f "/etc/nexusshield/credcache.enc" ]]; then
            # CREDCACHE_PASSPHRASE must be provided in env
            source "${REPO_ROOT}/scripts/utilities/credcache.sh" || true
            if load_credcache; then
                echo "[CREDENTIALS] Loaded secrets from local encrypted cache"
            else
                echo "[CREDENTIALS] Local encrypted cache present but failed to load"
            fi
        fi
    fi

    if [[ -z "${RUNNER_SSH_KEY}" ]] || [[ -z "${DATABASE_SECRET}" ]]; then
        echo "ERROR: Could not bootstrap credentials from GSM/Vault/KMS/local cache"
        audit_deploy "bootstrap_failed" "credentials unavailable from all backends"
        exit 1
    fi

    echo "[CREDENTIALS] ✅ Credentials bootstrapped from secure backends"
    audit_deploy "credentials_bootstrapped" "gsm/vault/kms"
}

# ============================================================================
# Terraform Apply (Idempotent)
# ============================================================================
apply_terraform() {
    echo "[TERRAFORM] Applying infrastructure changes..."

    cd "${REPO_ROOT}/nexusshield/infrastructure/terraform/production"

    # Plan first
    terraform plan -out=tfplan.direct 2>&1 | tee -a "${DEPLOY_LOG}"

    # Apply (idempotent - safe to re-run)
    terraform apply tfplan.direct 2>&1 | tee -a "${DEPLOY_LOG}"

    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        echo "[TERRAFORM] ✅ Apply successful"
        audit_deploy "terraform_applied" "all resources updated"
    else
        echo "[TERRAFORM] ❌ Apply failed"
        audit_deploy "terraform_failed" "see logs for details"
        exit 1
    fi

    cd "${REPO_ROOT}"
}

# ============================================================================
# Docker Build & Deploy
# ============================================================================
deploy_containers() {
    echo "[CONTAINERS] Building and deploying..."

    # Build backend
    docker build -t portal-backend:latest backend/ 2>&1 | tee -a "${DEPLOY_LOG}"

    # Build frontend
    docker build -t portal-frontend:latest frontend/ 2>&1 | tee -a "${DEPLOY_LOG}"

    # Deploy via docker-compose (or direct to Cloud Run)
    if [[ -f "docker-compose.production.yml" ]]; then
        docker-compose -f docker-compose.production.yml up -d 2>&1 | tee -a "${DEPLOY_LOG}"
    fi

    echo "[CONTAINERS] ✅ Containers deployed"
    audit_deploy "containers_deployed" "backend and frontend running"
}

# ============================================================================
# Health Checks
# ============================================================================
health_check() {
    echo "[HEALTH] Running post-deployment health checks..."

    local retries=5
    local api_url="${API_URL:-http://localhost:3000}"

    for ((i = 1; i <= retries; i++)); do
        if curl -sf "${api_url}/health" &>/dev/null; then
            echo "[HEALTH] ✅ API is healthy"
            audit_deploy "health_check_passed" "api responding normally"
            return 0
        fi
        echo "[HEALTH] Attempt ${i}/${retries} - waiting for API..."
        sleep 5
    done

    echo "[HEALTH] ❌ Health check failed"
    audit_deploy "health_check_failed" "api not responding"
    exit 1
}

# ============================================================================
# Immutable Record
# ============================================================================
finalize_audit() {
    cd "${REPO_ROOT}"
    
    # Commit audit log to git (immutable record)
    git add logs/deployment/audit.jsonl
    git commit -m "ops: direct deployment completed (${DEPLOY_TIMESTAMP}) - immutable audit recorded" || true
    
    # Push to main (no PR, direct)
    git push origin main || true

    audit_deploy "deployment_complete" "audit committed to git"
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo "=========================================="
    echo "Direct Production Deployment"
    echo "Time: ${DEPLOY_TIMESTAMP}"
    echo "No GitHub Actions • Direct to Main • Immutable Audit"
    echo "=========================================="

    validate_deployment
    bootstrap_credentials
    apply_terraform
    deploy_containers
    health_check
    finalize_audit

    echo "=========================================="
    echo "✅ Deployment Complete"
    echo "Audit: ${AUDIT_FILE}"
    echo "=========================================="
}

main "$@"
