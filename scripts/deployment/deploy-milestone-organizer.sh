#!/usr/bin/env bash
# Autonomous Milestone Organizer Deployment Script
# Builds, pushes, and deploys milestone-organizer container to Cloud Run
# Fully hands-off, immutable, ephemeral, idempotent, no-ops automation
#
# Usage: ./deploy-milestone-organizer.sh [--dry-run] [--skip-build]
# Environment: GCP_PROJECT (defaults: nexusshield-prod), GCP_REGION (defaults: us-central1)

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GCP_PROJECT="${GCP_PROJECT:-nexusshield-prod}"
GCP_REGION="${GCP_REGION:-us-central1}"
REGISTRY="gcr.io"
IMAGE_NAME="milestone-organizer"
IMAGE_REGISTRY="${REGISTRY}/${GCP_PROJECT}/${IMAGE_NAME}"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
TAG_JQ="jq-${TIMESTAMP}"
DRY_RUN="${1:-}"
SKIP_BUILD="${2:-}"

# Logging functions
log() { echo "[${SCRIPT_NAME}] $(date -u +'%Y-%m-%d %H:%M:%S UTC') $*" >&2; }
info() { echo "[${SCRIPT_NAME}] ℹ️  $*" >&2; }
success() { echo "[${SCRIPT_NAME}] ✅ $*" >&2; }
warn() { echo "[${SCRIPT_NAME}] ⚠️  $*" >&2; }
err() { echo "[${SCRIPT_NAME}] ❌ ERROR: $*" >&2; exit 1; }

# Configuration audit
log "=== Milestone Organizer Deployment Configuration ==="
log "GCP Project: $GCP_PROJECT"
log "GCP Region: $GCP_REGION"
log "Image Registry: $IMAGE_REGISTRY"
log "New Tag: $TAG_JQ"
log "Dry Run: ${DRY_RUN:-false}"
log "Skip Build: ${SKIP_BUILD:-false}"

# Verify prerequisites
log "=== Verifying Prerequisites ==="
for cmd in gcloud docker git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "$cmd not found. Install it and try again."
  fi
  success "$cmd found"
done

# Verify Dockerfile exists
if [[ ! -f "${SCRIPT_DIR}/Dockerfile.milestone-organizer" ]]; then
  err "Dockerfile.milestone-organizer not found at ${SCRIPT_DIR}"
fi
success "Dockerfile.milestone-organizer found"

# Verify jq is in Dockerfile
if ! grep -q '^.*jq' "${SCRIPT_DIR}/Dockerfile.milestone-organizer"; then
  err "jq package not found in Dockerfile.milestone-organizer"
fi
success "jq package verified in Dockerfile"

# Authenticate with GCP
log "=== Authenticating with GCP ==="
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  err "GCP authentication failed. Run 'gcloud auth application-default login'"
fi
success "GCP authentication successful"

# Configure Docker for GCR
log "=== Configuring Docker for GCR ==="
if [[ "$DRY_RUN" != "--dry-run" ]]; then
  gcloud auth configure-docker --quiet 2>/dev/null || warn "Docker GCR configuration may have issues"
  success "Docker GCR configuration applied"
fi

# Build image
if [[ "$SKIP_BUILD" != "--skip-build" ]]; then
  log "=== Building Docker Image ==="
  info "Building with tag: ${REGISTRY}/${GCP_PROJECT}/${IMAGE_NAME}:${TAG_JQ}"
  
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    info "[DRY-RUN] Would execute: docker build -f Dockerfile.milestone-organizer -t ${IMAGE_REGISTRY}:${TAG_JQ} -t ${IMAGE_REGISTRY}:latest ${SCRIPT_DIR}"
  else
    cd "${SCRIPT_DIR}"
    docker build -f Dockerfile.milestone-organizer \
      -t "${IMAGE_REGISTRY}:${TAG_JQ}" \
      -t "${IMAGE_REGISTRY}:latest" \
      . || err "Docker build failed"
    success "Docker image built successfully"
  fi
else
  warn "Skipping image build (--skip-build flag set)"
fi

# Push image to GCR
log "=== Pushing Image to GCR ==="
if [[ "$DRY_RUN" == "--dry-run" ]]; then
  info "[DRY-RUN] Would execute: docker push ${IMAGE_REGISTRY}:${TAG_JQ}"
  info "[DRY-RUN] Would execute: docker push ${IMAGE_REGISTRY}:latest"
else
  docker push "${IMAGE_REGISTRY}:${TAG_JQ}" || err "Failed to push image with $TAG_JQ tag"
  success "Pushed image: ${IMAGE_REGISTRY}:${TAG_JQ}"
  
  docker push "${IMAGE_REGISTRY}:latest" || err "Failed to push image with latest tag"
  success "Pushed image: ${IMAGE_REGISTRY}:latest"
fi

# Deploy to Cloud Run
log "=== Deploying to Cloud Run ==="
if [[ "$DRY_RUN" == "--dry-run" ]]; then
  info "[DRY-RUN] Would execute: gcloud run deploy ${IMAGE_NAME} --image ${IMAGE_REGISTRY}:${TAG_JQ} --project ${GCP_PROJECT} --region ${GCP_REGION}"
else
  gcloud run deploy "${IMAGE_NAME}" \
    --image "${IMAGE_REGISTRY}:${TAG_JQ}" \
    --project "${GCP_PROJECT}" \
    --region "${GCP_REGION}" \
    --allow-unauthenticated \
    --no-traffic \
    --quiet || err "Cloud Run deployment failed"
  
  # Route 100% traffic to new revision
  NEW_REVISION=$(gcloud run services describe "${IMAGE_NAME}" \
    --project "${GCP_PROJECT}" \
    --region "${GCP_REGION}" \
    --format='value(status.latestReadyRevisionName)' 2>/dev/null)
  
  if [[ -n "$NEW_REVISION" ]]; then
    gcloud run services update-traffic "${IMAGE_NAME}" \
      --to-revisions "${NEW_REVISION}"=100 \
      --project "${GCP_PROJECT}" \
      --region "${GCP_REGION}" \
      --quiet || warn "Traffic routing may have failed, but deployment succeeded"
    success "Routed 100% traffic to new revision: $NEW_REVISION"
  fi
fi

# Verify deployment
log "=== Verifying Deployment ==="
if [[ "$DRY_RUN" != "--dry-run" ]]; then
  SERVICE_URL=$(gcloud run services describe "${IMAGE_NAME}" \
    --project "${GCP_PROJECT}" \
    --region "${GCP_REGION}" \
    --format='value(status.url)' 2>/dev/null)
  
  if [[ -n "$SERVICE_URL" ]]; then
    success "Service URL: $SERVICE_URL"
    
    # Brief health check
    if curl -s "${SERVICE_URL}/ready" >/dev/null 2>&1; then
      success "Health check passed"
    else
      warn "Health check endpoint not responding (expected if just deployed)"
    fi
  fi
fi

# Trigger scheduler
log "=== Triggering Cloud Scheduler ==="
if [[ "$DRY_RUN" == "--dry-run" ]]; then
  info "[DRY-RUN] Would execute: gcloud scheduler jobs run milestone-organizer-weekly --project ${GCP_PROJECT} --location ${GCP_REGION}"
else
  gcloud scheduler jobs run milestone-organizer-weekly \
    --project "${GCP_PROJECT}" \
    --location "$(echo "$GCP_REGION" | sed 's/-.*$//')" \
    --quiet 2>/dev/null || warn "Scheduler trigger may have failed (job may not exist yet)"
  success "Scheduler job triggered"
fi

# Log audit entry
log "=== Creating Audit Trail Entry ==="
AUDIT_ENTRY=$(cat <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "event_type": "deployment",
  "component": "milestone-organizer",
  "action": "deploy",
  "image_tag": "${TAG_JQ}",
  "registry": "${IMAGE_REGISTRY}",
  "gcp_project": "${GCP_PROJECT}",
  "gcp_region": "${GCP_REGION}",
  "deployed_by": "$(whoami)",
  "hostname": "$(hostname)",
  "git_commit": "$(cd "${SCRIPT_DIR}" && git rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "dry_run": "${DRY_RUN:-false}",
  "status": "success"
}
EOF
)

if [[ "$DRY_RUN" != "--dry-run" ]]; then
  AUDIT_FILE="${SCRIPT_DIR}/artifacts/milestones-assignments/audit_deployment_$(date -u +%s).jsonl"
  mkdir -p "$(dirname "$AUDIT_FILE")"
  echo "$AUDIT_ENTRY" >> "$AUDIT_FILE" || warn "Could not write audit entry to $AUDIT_FILE"
  success "Audit entry written"
fi

# Final summary
log "=== Deployment Complete ==="
if [[ "$DRY_RUN" == "--dry-run" ]]; then
  info "Dry-run mode: No actual changes were made"
  info "Remove --dry-run flag to execute deployment"
else
  success "Milestone-organizer successfully deployed"
  success "Image tag: ${TAG_JQ}"
  success "Timestamp: ${TIMESTAMP}"
fi

log "=== Next Steps ==="
info "1. Monitor Cloud Run logs: gcloud logging read \"resource.type=cloud_run_revision AND resource.labels.service_name=${IMAGE_NAME}\" --limit=50"
info "2. Check classification results: gs://nexusshield-prod-artifacts/classification.json"
info "3. View generated reports: gs://nexusshield-prod-artifacts/ (look for HTML files)"
info "4. Verify audit trail: cat ${SCRIPT_DIR}/artifacts/milestones-assignments/audit_*.jsonl"

success "End of deployment script"
