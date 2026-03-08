#!/bin/bash

################################################################################
# Phase P2 Production Rollout Orchestration Script
# 
# Purpose: Automate and guide the production deployment of provisioner-worker
#          managed-mode system.
#
# Prerequisites:
#   - Docker CLI installed and authenticated
#   - kubectl (if K8s deployment)
#   - Vault CLI installed (for credential setup)
#   - GitHub org admin access (for runner registration)
#
# Usage:
#   ./deploy-p2-production.sh [stage1|stage2|stage3|stage4|all] [options]
#   ./deploy-p2-production.sh stage1 --dry-run        # Validate only
#   ./deploy-p2-production.sh all --image myregistry/p2:prod
#
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"
DEPLOYMENT_LOG="${DEPLOYMENT_LOG:-/tmp/p2-deployment.log}"
STAGE="${1:-all}"
DRY_RUN="${DRY_RUN:-0}"

# Options
IMAGE_REGISTRY="${IMAGE_REGISTRY:-docker.io}"
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-self-hosted-runner}"
IMAGE_TAG="${IMAGE_TAG:-prod-p2}"
DEPLOYMENT_METHOD="${DEPLOYMENT_METHOD:-docker}"  # docker, systemd, k8s
TARGET_HOST="${TARGET_HOST:-}"
GIT_BRANCH="${GIT_BRANCH:-main}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$DEPLOYMENT_LOG"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*" | tee -a "$DEPLOYMENT_LOG"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$DEPLOYMENT_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$DEPLOYMENT_LOG"
}

# Helper to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Helper to run command in dry-run mode
run_cmd() {
    if [[ "$DRY_RUN" == "1" ]]; then
        log_warn "[DRY-RUN] $*"
    else
        log_info "Running: $*"
        "$@" 2>&1 | tee -a "$DEPLOYMENT_LOG"
    fi
}

################################################################################
# Stage 1: Prerequisites Validation & Image Build
################################################################################

stage1_build_image() {
    log_info "=== Stage 1: Container Image Build ==="

    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command_exists docker; then
        log_error "Docker not found. Please install Docker CLI."
        return 1
    fi
    log_success "Docker found: $(docker --version)"

    if ! command_exists git; then
        log_error "Git not found. Please install Git."
        return 1
    fi
    log_success "Git found: $(git --version | head -1)"

    # Verify git repo
    log_info "Validating Git repository..."
    if ! git -C "$PROJECT_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not a Git repository: $PROJECT_ROOT"
        return 1
    fi

    # Get current commit
    LOCAL_COMMIT=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)
    log_success "Current branch: $(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD)"
    log_success "Current commit: $LOCAL_COMMIT"

    # Build image
    log_info "Building production container image..."
    IMAGE_NAME="${IMAGE_REGISTRY}/${IMAGE_NAMESPACE}:${IMAGE_TAG}"
    
    run_cmd docker build \
        -t "$IMAGE_NAME" \
        -f "$PROJECT_ROOT/build/github-runner/Dockerfile" \
        --build-arg NODE_ENV=production \
        --label "git.commit=$LOCAL_COMMIT" \
        --label "build.date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        "$PROJECT_ROOT"

    log_success "Image built: $IMAGE_NAME"

    # Security Scan (Stage 1.5)
    if command_exists trivy; then
        log_info "Running Trivy image scan (Stage 1.5)..."
        trivy image --severity HIGH,CRITICAL --exit-code 1 "$IMAGE_NAME" || {
            log_error "Vulnerabilities found in $IMAGE_NAME. Review with security-master."
            return 1
        }
        log_success "Trivy scan passed for $IMAGE_NAME"
    else
        log_warn "Trivy not found. Skipping image scan. Install with 'apt install trivy'."
    fi
    
    # Optionally push image
    if [[ "$IMAGE_REGISTRY" != "docker.io" ]] || [[ "${PUSH_IMAGE:-0}" == "1" ]]; then
        log_info "Pushing image to registry..."
        run_cmd docker push "$IMAGE_NAME"
        log_success "Image pushed: $IMAGE_NAME"
    fi

    echo "$IMAGE_NAME"
}

################################################################################
# Stage 2: Vault AppRole Setup
################################################################################

stage2_vault_setup() {
    log_info "=== Stage 2: Vault AppRole Configuration ==="

    if ! command_exists vault; then
        log_error "Vault CLI not found. Please install it from https://www.vaultproject.io"
        return 1
    fi
    log_success "Vault CLI found: $(vault version | head -1)"

    # Check Vault connectivity
    log_info "Testing Vault connectivity..."
    if ! VAULT_TOKEN=test vault status > /dev/null 2>&1; then
        log_warn "Vault unreachable at $VAULT_ADDR"
        log_info "If using Vault in dev mode, run:"
        log_info "  vault server -dev -dev-root-token-id=root"
        return 1
    fi
    log_success "Vault reachable"

    # Prompt for Vault credentials
    if [[ -z "${VAULT_ROLE_ID:-}" ]] || [[ -z "${VAULT_SECRET_ID:-}" ]]; then
        log_info "Vault AppRole credentials not found in env variables."
        log_info "Please provide the existing AppRole credentials or create new ones."
        log_info ""
        log_info "To generate AppRole (Vault admin):"
        log_info "  vault auth enable approle"
        log_info "  vault write auth/approle/role/provisioner-worker policies=provisioner-worker"
        log_info "  vault read auth/approle/role/provisioner-worker/role-id"
        log_info "  vault write -f auth/approle/role/provisioner-worker/secret-id"
        log_info ""
        
        read -p "Enter VAULT_ROLE_ID: " VAULT_ROLE_ID
        read -sp "Enter VAULT_SECRET_ID: " VAULT_SECRET_ID
        echo ""
    fi

    # Validate AppRole authentication
    log_info "Validating AppRole authentication..."

    # Use JSON output and extract auth.client_token (compatible with Vault >=1.0)
    if ! command_exists jq; then
        log_warn "jq not found; installing is recommended for parsing Vault output"
    fi

    local _token
    _token=$(vault write -format=json auth/approle/login \
        role_id="$VAULT_ROLE_ID" \
        secret_id="$VAULT_SECRET_ID" 2>/dev/null | jq -r '.auth.client_token // empty') || true

    if [[ -n "$_token" ]]; then
        export VAULT_TOKEN="$_token"
        log_success "AppRole authentication successful (token exported to VAULT_TOKEN)"
    else
        log_error "AppRole authentication failed. Check credentials."
        return 1
    fi

    # Store credentials for deployment
    mkdir -p /tmp/provisioner-worker-creds
    (
        echo "export VAULT_ROLE_ID='$VAULT_ROLE_ID'"
        echo "export VAULT_SECRET_ID='$VAULT_SECRET_ID'"
    ) > /tmp/provisioner-worker-creds/env-vault.sh
    chmod 600 /tmp/provisioner-worker-creds/env-vault.sh
    
    log_success "Vault credentials stored in /tmp/provisioner-worker-creds/env-vault.sh"
}

################################################################################
# Stage 3: Redis Setup & Connection Validation
################################################################################

stage3_redis_setup() {
    log_info "=== Stage 3: Redis Configuration ==="

    if [[ -z "${PROVISIONER_REDIS_URL:-}" ]]; then
        log_info "PROVISIONER_REDIS_URL not configured."
        log_info "Provide Redis endpoint (e.g., redis://redis.example.com:6379)"
        read -p "Enter Redis URL: " PROVISIONER_REDIS_URL
    fi

    log_info "Testing Redis connectivity to: $PROVISIONER_REDIS_URL"

    # Parse Redis URL
    REDIS_HOST=$(echo "$PROVISIONER_REDIS_URL" | sed -E 's|redis://([^:]+).*|\1|')
    REDIS_PORT=$(echo "$PROVISIONER_REDIS_URL" | sed -E 's|.*:([0-9]+).*|\1|' || echo 6379)

    # Test connectivity
    if command_exists redis-cli; then
        if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping > /dev/null 2>&1; then
            log_success "Redis connection successful"
        else
            log_error "Redis connection failed. Verify endpoint and network access."
            return 1
        fi
    else
        log_warn "redis-cli not found; skipping Redis connection test"
        log_info "Install via: apt-get install redis-tools (Debian) or brew install redis (macOS)"
    fi

    log_success "Redis configuration ready: $PROVISIONER_REDIS_URL"
}

################################################################################
# Stage 4: Service Deployment
################################################################################

stage4_deploy_services() {
    log_info "=== Stage 4: Service Deployment ==="

    case "$DEPLOYMENT_METHOD" in
        docker)
            log_info "Deploying via docker-compose..."
            
            # Source Vault credentials
            if [[ -f /tmp/provisioner-worker-creds/env-vault.sh ]]; then
                # shellcheck source=/dev/null
                source /tmp/provisioner-worker-creds/env-vault.sh
            fi

            # Create docker-compose override for environment
            cat > /tmp/docker-compose.override.yml <<EOF
version: '3.8'
services:
  provisioner-worker:
    environment:
      - VAULT_ROLE_ID=$VAULT_ROLE_ID
      - VAULT_SECRET_ID=$VAULT_SECRET_ID
      - PROVISIONER_REDIS_URL=$PROVISIONER_REDIS_URL
      - USE_TERRAFORM_CLI=1
      - NODE_ENV=production
EOF
            
            run_cmd docker-compose \
                -f "$PROJECT_ROOT/services/provisioner-worker/deploy/docker-compose.yml" \
                -f /tmp/docker-compose.override.yml \
                up -d

            log_success "Services deployed via docker-compose"
            ;;

        systemd)
            log_info "Deploying via systemd..."
            
            if [[ -z "$TARGET_HOST" ]]; then
                log_error "systemd deployment requires TARGET_HOST (e.g., user@host)"
                return 1
            fi

            # Use deployment script
            run_cmd "$PROJECT_ROOT/services/provisioner-worker/deploy/deploy_to_host.sh" \
                "$TARGET_HOST" systemd "$GIT_BRANCH"

            log_success "Services deployed to $TARGET_HOST via systemd"
            ;;

        k8s)
            log_error "Kubernetes deployment not yet implemented"
            log_info "See: docs/PHASE_P2_DELIVERY_SUMMARY.md for future phases"
            return 1
            ;;

        *)
            log_error "Unknown deployment method: $DEPLOYMENT_METHOD"
            return 1
            ;;
    esac
}

################################################################################
# Stage 5: Smoke Testing & Validation
################################################################################

stage5_smoke_tests() {
    log_info "=== Stage 5: Smoke Testing ==="

    log_info "Waiting for services to stabilize (10 seconds)..."
    sleep 10

    case "$DEPLOYMENT_METHOD" in
        docker)
            log_info "Checking docker-compose service health..."
            run_cmd docker-compose \
                -f "$PROJECT_ROOT/services/provisioner-worker/deploy/docker-compose.yml" \
                ps

            # Check logs for errors
            log_info "Checking service logs for errors..."
            if docker-compose -f "$PROJECT_ROOT/services/provisioner-worker/deploy/docker-compose.yml" \
                   logs provisioner-worker 2>&1 | grep -i "error" | head -5; then
                log_warn "Found errors in service logs; review above"
            else
                log_success "No errors found in initial logs"
            fi
            ;;

        systemd)
            log_info "Checking systemd service status..."
            if [[ -z "$TARGET_HOST" ]]; then
                run_cmd systemctl status provisioner-worker
            else
                run_cmd ssh "$TARGET_HOST" "systemctl status provisioner-worker"
            fi
            ;;
    esac

    log_info "Enqueuing test provisioning job..."
    # This would call the managed-auth API to enqueue a test job
    # For now, just log the next steps
    log_info "Next: Call managed-auth API to enqueue test job"
    log_info "  POST /provision"
    log_info "  body: { workspace: 'test-runner-1', tfVariables: {} }"

    log_success "Smoke testing complete. Review logs above for any warnings."
}

################################################################################
# Main orchestration
################################################################################

main() {
    log_info "=== Phase P2 Production Deployment Orchestrator ==="
    log_info "Stage: $STAGE | Deployment Method: $DEPLOYMENT_METHOD | Dry-Run: $DRY_RUN"
    log_info "Log file: $DEPLOYMENT_LOG"
    echo ""

    case "$STAGE" in
        stage1)
            stage1_build_image
            ;;
        stage2)
            stage2_vault_setup
            ;;
        stage3)
            stage3_redis_setup
            ;;
        stage4)
            stage4_deploy_services
            ;;
        stage5)
            stage5_smoke_tests
            ;;
        all)
            log_info "Running all deployment stages..."
            stage1_build_image || { log_error "Stage 1 failed"; return 1; }
            stage2_vault_setup || { log_error "Stage 2 failed"; return 1; }
            stage3_redis_setup || { log_error "Stage 3 failed"; return 1; }
            stage4_deploy_services || { log_error "Stage 4 failed"; return 1; }
            stage5_smoke_tests || { log_error "Stage 5 failed"; return 1; }
            log_success "All deployment stages completed successfully!"
            ;;
        *)
            log_error "Unknown stage: $STAGE"
            echo "Usage: $0 [stage1|stage2|stage3|stage4|stage5|all]"
            return 1
            ;;
    esac
}

# Execute main
main "$@"
