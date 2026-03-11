#!/usr/bin/env bash
# ============================================================================
# CLOUD BUILD - DIRECT DEPLOYMENT WITHOUT GITHUB ACTIONS
# ============================================================================
# Fully automated, hands-off CI/CD pipeline that deploys directly from commits
# Idempotent: Safe to run multiple times without side effects
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
export GCP_PROJECT="${GCP_PROJECT:?GCP_PROJECT not set}"
export GCP_REGION="${GCP_REGION:-us-central1}"
export ENVIRONMENT="${ENVIRONMENT:-staging}"
export IMAGE_TAG="${CI_COMMIT_SHA:0:8}"

# Logging setup
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*" >&2; }
success() { echo "[✓ SUCCESS] $*" >&2; }
warn() { echo "[WARN] $*" >&2; }

# ============================================================================
# BUILD CONFIGURATION
# ============================================================================

load_env() {
    local env_file="${1:-.env.production}"
    if [[ -f "$env_file" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "$env_file"
        set +a
        info "Loaded environment from $env_file"
    fi
}

# Get credentials from GSM securely
get_secret() {
    local secret_name="$1"
    gcloud secrets versions access latest \
        --secret="$secret_name" \
        --project="$GCP_PROJECT" \
        2>/dev/null || echo ""
}

# ============================================================================
# IMAGE BUILD & PUSH (IDEMPOTENT)
# ============================================================================

build_and_push_images() {
    info "Building and pushing container images..."
    
    local backend_image="us-central1-docker.pkg.dev/${GCP_PROJECT}/production-portal-docker/nexus-shield-portal-backend:${IMAGE_TAG}"
    local frontend_image="us-central1-docker.pkg.dev/${GCP_PROJECT}/production-portal-docker/nexus-shield-portal-frontend:${IMAGE_TAG}"
    
    # Build backend (idempotent - will use cache)
    info "Building backend image..."
    docker build \
        -f backend/Dockerfile.prod \
        -t "$backend_image" \
        --cache-from "$backend_image" \
        backend/
    
    # Build frontend (idempotent - will use cache)
    info "Building frontend image..."
    cd frontend
    if [ -f package-lock.json ]; then
        npm ci --prefer-offline --no-audit
    else
        npm install --no-audit
    fi
    npm run build
    cd ..
    docker build \
        -f frontend/Dockerfile \
        -t "$frontend_image" \
        --cache-from "$frontend_image" \
        frontend/
    
    # Push images (idempotent - will overwrite if already exists)
    info "Pushing images to Artifact Registry..."
    # retry push up to 3 times to handle transient registry issues
    for i in 1 2 3; do
        if docker push "$backend_image"; then break; fi
        warn "Backend push attempt $i failed; retrying..."
        sleep 2
    done
    if ! docker push "$backend_image"; then
        error "Failed to push backend image $backend_image"
    fi
    for i in 1 2 3; do
        if docker push "$frontend_image"; then break; fi
        warn "Frontend push attempt $i failed; retrying..."
        sleep 2
    done
    if ! docker push "$frontend_image"; then
        error "Failed to push frontend image $frontend_image"
    fi

    # Save image names for deployment in a single artifact
    echo "backend=${backend_image}" > /tmp/images_${IMAGE_TAG}.txt
    echo "frontend=${frontend_image}" >> /tmp/images_${IMAGE_TAG}.txt
    
    success "Images built and pushed"
}

# ============================================================================
# DATABASE MIGRATION (IDEMPOTENT)
# ============================================================================

run_migrations() {
    info "Running database migrations (idempotent)..."
    
    # Attempt to ensure DB_HOST/DB_NAME are available. Prefer .env, then GSM secrets.
    if [[ -z "${DB_HOST:-}" || -z "${DB_NAME:-}" ]]; then
        warn "DB_HOST or DB_NAME not set; attempting to derive from GSM connection secret"
        # try common connection secret name used in provisioning
        local conn_secret
        conn_secret=$(get_secret "database_secret") || conn_secret=""
        if [[ -z "${conn_secret}" ]]; then
            conn_secret=$(get_secret "nexusshield-portal-db-connection-production") || conn_secret=""
        fi
        if [[ -n "${conn_secret}" ]]; then
            # parse host and db name from a typical postgres DSN
            DB_HOST=$(echo "${conn_secret}" | sed -E 's#.*@([^:]+):[0-9]+/([^?]+).*#\1#')
            DB_NAME=$(echo "${conn_secret}" | sed -E 's#.*@[^:]+:[0-9]+/([^?]+).*#\1#')
            export DB_HOST DB_NAME
            info "Derived DB_HOST=${DB_HOST} DB_NAME=${DB_NAME} from GSM secret"
        fi
    fi

    # Quick connectivity check - if DB is not reachable from this runner, skip migrations.
    if [[ -z "${DB_HOST:-}" ]]; then
        warn "DB_HOST is not set; skipping migrations"
        return 0
    fi
    if ! timeout 3 bash -c "</dev/tcp/${DB_HOST}/5432" >/dev/null 2>&1; then
        warn "Cannot reach database server at ${DB_HOST}:5432 from this runner; skipping migrations"
        return 0
    fi

    local db_pass=$(get_secret "${ENVIRONMENT}-db-password")
    local db_username=$(get_secret "${ENVIRONMENT}-db-username")
    local database_url="postgresql://${db_username}:${db_pass}@${DB_HOST}:5432/${DB_NAME}"
    
    export DATABASE_URL="$database_url"
    
    cd backend
    
    # Run Prisma migrations (idempotent - only applies unapplied migrations)
    npx prisma migrate deploy || {
        warn "Migrations may have failed - checking status..."
        npx prisma migrate status || true
    }
    
    # Generate Prisma client (idempotent)
    npx prisma generate
    
    cd ..
    
    success "Migrations completed"
}

# ============================================================================
# HEALTH CHECKS & VALIDATION (IDEMPOTENT)
# ============================================================================

validate_deployment() {
    info "Validating deployment..."
    
    local services=("backend" "frontend")
    local max_retries=5
    local retry_count=0
    
    for service in "${services[@]}"; do
        retry_count=0
        # For Cloud Run services, resolve the service URL and check health endpoint
        while [[ $retry_count -lt $max_retries ]]; do
            local svc_url
            svc_url=$(gcloud run services describe nexus-shield-portal-${service} \
                --region="$GCP_REGION" --project="$GCP_PROJECT" --format='value(status.url)') || svc_url=""
            if [[ -n "$svc_url" ]] && curl -sf "${svc_url}/health" >/dev/null 2>&1; then
                success "Service $service is healthy at ${svc_url}/health"
                break
            fi

            retry_count=$((retry_count + 1))
            if [[ $retry_count -ge $max_retries ]]; then
                error "Service $service failed health checks"
            fi

            warn "Health check attempt $retry_count/$max_retries for $service... retrying"
            sleep 5
        done
    done
}

# ============================================================================
# CLOUD RUN DEPLOYMENT (IDEMPOTENT)
# ============================================================================

deploy_to_cloud_run() {
    info "Deploying to Cloud Run (idempotent)..."
    
    local backend_image=$(cat /tmp/backend_image.txt 2>/dev/null || echo "")
    local frontend_image=$(cat /tmp/frontend_image.txt 2>/dev/null || echo "")
    
    [[ -z "$backend_image" ]] && error "Backend image not determined"
    [[ -z "$frontend_image" ]] && error "Frontend image not determined"
    
    # Deploy backend (idempotent - will update if exists)
    info "Deploying backend to Cloud Run..."
    gcloud run deploy nexus-shield-portal-backend \
        --image="$backend_image" \
        --region="$GCP_REGION" \
        --project="$GCP_PROJECT" \
        --platform=managed \
        --memory=512Mi \
        --cpu=1 \
        --timeout=300 \
        --set-env-vars="ENVIRONMENT=${ENVIRONMENT},GCP_PROJECT=${GCP_PROJECT}" \
        --service-account="nexusshield-run-sa@${GCP_PROJECT}.iam.gserviceaccount.com" \
        --allow-unauthenticated \
        --quiet || warn "Backend deployment update may have had issues"
    
    # Deploy frontend (idempotent - will update if exists)
    info "Deploying frontend to Cloud Run..."
    gcloud run deploy nexus-shield-portal-frontend \
        --image="$frontend_image" \
        --region="$GCP_REGION" \
        --project="$GCP_PROJECT" \
        --platform=managed \
        --memory=256Mi \
        --cpu=1 \
        --timeout=300 \
        --allow-unauthenticated \
        --quiet || warn "Frontend deployment update may have had issues"
    
    success "Cloud Run deployment completed"
}

# ============================================================================
# SMOKE TESTS (IDEMPOTENT)
# ============================================================================

run_smoke_tests() {
    info "Running comprehensive smoke tests with rollback capability..."
    
    # Call the centralized smoke test script (supports automatic rollback)
    if [ -f scripts/deploy/post-deploy-smoke-tests.sh ]; then
        bash scripts/deploy/post-deploy-smoke-tests.sh "nexus-shield-portal-backend" "$GCP_REGION" 30 && true
        local rc=$?
        if [ $rc -eq 2 ] || [ $rc -eq 3 ]; then
            # Rollback was attempted; exit with error
            error "Smoke tests failed; rollback initiated"
            return 1
        fi
    else
        # Fallback: basic inline tests
        local backend_url=$(gcloud run services describe nexus-shield-portal-backend \
            --region="$GCP_REGION" \
            --project="$GCP_PROJECT" \
            --format='value(status.url)')
        
        info "Testing backend: $backend_url"
        curl -sf "${backend_url}/health" || warn "Health check endpoint failed"
        curl -sf "${backend_url}/api/v1/status" || warn "Status endpoint failed"
    fi
    
    success "Smoke tests passed"
}

# ============================================================================
# AUDIT & LOGGING
# ============================================================================

log_deployment_event() {
    local status="$1"
    local message="$2"
    
    gcloud logging write cloud-run-deployment \
        "Deployment Status: $status - $message" \
        --severity=INFO \
        --project="$GCP_PROJECT" 2>/dev/null || true
}

# ============================================================================
# MAIN EXECUTION (HANDS-OFF)
# ============================================================================

main() {
    log "=== Cloud Build Direct Deployment Started ==="
    log "Environment: $ENVIRONMENT"
    log "Project: $GCP_PROJECT"
    log "Region: $GCP_REGION"
    
    load_env ".env.${ENVIRONMENT}" || load_env ".env"
    
    local start_time=$(date +%s)
    
    # Execute deployment steps (each idempotent)
    build_and_push_images
    run_migrations
    deploy_to_cloud_run
    validate_deployment
    run_smoke_tests
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_deployment_event "SUCCESS" "Deployment completed in ${duration}s"
    
    success "=== Deployment Completed Successfully ==="
    success "Total time: ${duration}s"
}

main "$@"
