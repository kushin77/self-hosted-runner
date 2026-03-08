#!/bin/bash
set -u

# Push Docker image to Google Artifact Registry
# Usage: ./scripts/push-to-gar.sh <image-tag>
# Environment: GCP_PROJECT_ID, GCP_SERVICE_ACCOUNT_KEY (optional)

IMAGE_TAG="${1:?Image tag required}"
LOCATION="${GAR_LOCATION:-us-east1}"
REPOSITORY="${GAR_REPOSITORY:-docker-hub-mirror}"
PROJECT_ID="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"

REGISTRY="$LOCATION-docker.pkg.dev/$PROJECT_ID/$REPOSITORY"

log() { echo "[GAR] $(date +'%Y-%m-%d %H:%M:%S') $*"; }
fail() { echo "[GAR] ERROR: $*" >&2; exit 1; }
pass() { echo "[GAR] ✓ $*"; }

log "Pushing to Google Artifact Registry: $REGISTRY/app-backup:$IMAGE_TAG"

# Configure Docker auth for GAR
log "Authenticating with Google Cloud..."
if [[ -n "${GCP_SERVICE_ACCOUNT_KEY:-}" ]]; then
  # Use service account key
  echo "$GCP_SERVICE_ACCOUNT_KEY" | docker login \
    -u _json_key \
    --password-stdin \
    "$LOCATION-docker.pkg.dev" 2>/dev/null || fail "GCP authentication failed"
else
  # Use gcloud configured credentials
  gcloud auth configure-docker "$LOCATION-docker.pkg.dev" --quiet 2>/dev/null || fail "GCP auth configure-docker failed"
fi

pass "GCP authentication successful"

# Verify image exists locally
docker inspect "elevatediq/app-backup:$IMAGE_TAG" >/dev/null 2>&1 || \
  fail "Local image not found: elevatediq/app-backup:$IMAGE_TAG"

# Tag image for GAR
log "Tagging image for GAR..."
docker tag "elevatediq/app-backup:$IMAGE_TAG" "$REGISTRY/app-backup:$IMAGE_TAG" || fail "Tag failed"
docker tag "elevatediq/app-backup:$IMAGE_TAG" "$REGISTRY/app-backup:latest" || fail "Latest tag failed"

# Push to GAR
log "Pushing $IMAGE_TAG to GAR..."
docker push "$REGISTRY/app-backup:$IMAGE_TAG" 2>/dev/null || fail "Push $IMAGE_TAG failed"

log "Pushing latest tag to GAR..."
docker push "$REGISTRY/app-backup:latest" 2>/dev/null || fail "Push latest failed"

pass "Successfully pushed $IMAGE_TAG and latest to Google Artifact Registry"

# Get image digest
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$REGISTRY/app-backup:$IMAGE_TAG" 2>/dev/null | grep -oP 'sha256:[a-f0-9]{64}' || echo "sha256:unknown")

echo "gar_image=$REGISTRY/app-backup:$IMAGE_TAG"
echo "gar_digest=$DIGEST"
