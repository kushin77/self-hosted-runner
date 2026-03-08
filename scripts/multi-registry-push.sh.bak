#!/bin/bash
set -u

# Multi-registry backup orchestration
# Pushes image to Docker Hub, AWS ECR, and Google Artifact Registry in parallel
# Usage: ./scripts/multi-registry-push.sh <image-tag>

IMAGE_TAG="${1:?Image tag required}"

log() { echo "[MULTI-REGISTRY] $(date +'%Y-%m-%d %H:%M:%S') $*"; }
fail() { echo "[MULTI-REGISTRY] ERROR: $*" >&2; exit 1; }
pass() { echo "[MULTI-REGISTRY] ✓ $*"; }

log "Starting multi-registry push for $IMAGE_TAG"
log "Target registries: Docker Hub, AWS ECR, Google Artifact Registry"
echo ""

# Create temp directory for tracking
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

DOCKER_HUB_LOG="$TEMP_DIR/docker-hub.log"
AWS_ECR_LOG="$TEMP_DIR/aws-ecr.log"
GAR_LOG="$TEMP_DIR/gar.log"

# Start Docker Hub push in background (guarded by credentials or FORCE_PUSH)
(
  if [[ "${FORCE_PUSH:-}" == "1" ]]; then
    if docker push "docker.io/elevatediq/app-backup:$IMAGE_TAG" >/dev/null 2>&1; then
      echo "success" > "$DOCKER_HUB_LOG"
    else
      echo "failed" > "$DOCKER_HUB_LOG"
    fi
  elif [[ -n "${DOCKERHUB_USERNAME:-}" && -n "${DOCKERHUB_PASSWORD:-}" ]] || [[ -n "${DOCKERHUB_TOKEN:-}" ]]; then
    # Login before push
    if [[ -n "${DOCKERHUB_TOKEN:-}" ]]; then
      echo "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin >/dev/null 2>&1 || true
    else
      echo "$DOCKERHUB_PASSWORD" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin >/dev/null 2>&1 || true
    fi
    if docker push "docker.io/elevatediq/app-backup:$IMAGE_TAG" >>"$DOCKER_HUB_LOG" 2>&1; then
      echo "success" > "$DOCKER_HUB_LOG"
    else
      echo "failed" > "$DOCKER_HUB_LOG"
    fi
  else
    echo "skipped" > "$DOCKER_HUB_LOG"
  fi
) &
DOCKER_HUB_PID=$!

# Start AWS ECR push in background (requires credentials)
(
  if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] && [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    if bash scripts/push-to-aws-ecr.sh "$IMAGE_TAG" >>"$AWS_ECR_LOG" 2>&1; then
      echo "success" >> "$AWS_ECR_LOG"
    else
      echo "failed" >> "$AWS_ECR_LOG"
    fi
  else
    echo "skipped" > "$AWS_ECR_LOG"
  fi
) &
AWS_ECR_PID=$!

# Start Google Artifact Registry push in background (guarded by GCP credentials or FORCE_PUSH)
(
  if [[ "${FORCE_PUSH:-}" == "1" ]]; then
    if bash scripts/push-to-gar.sh "$IMAGE_TAG" >>"$GAR_LOG" 2>&1; then
      echo "success" > "$GAR_LOG"
    else
      echo "failed" > "$GAR_LOG"
    fi
  elif [[ -n "${GCP_PROJECT_ID:-}" && -n "${GCP_SERVICE_ACCOUNT_KEY:-}" ]]; then
    echo "$GCP_SERVICE_ACCOUNT_KEY" > "$TEMP_DIR/gcp-sa.json"
    export GOOGLE_APPLICATION_CREDENTIALS="$TEMP_DIR/gcp-sa.json"
    if bash scripts/push-to-gar.sh "$IMAGE_TAG" >>"$GAR_LOG" 2>&1; then
      echo "success" > "$GAR_LOG"
    else
      echo "failed" > "$GAR_LOG"
    fi
  else
    echo "skipped" > "$GAR_LOG"
  fi
) &
GAR_PID=$!

log "Waiting for all registry pushes to complete..."
wait $DOCKER_HUB_PID $AWS_ECR_PID $GAR_PID 2>/dev/null || true

# Collect results
DOCKER_HUB_RESULT=$(tail -1 "$DOCKER_HUB_LOG" 2>/dev/null || echo "unknown")
AWS_ECR_RESULT=$(tail -1 "$AWS_ECR_LOG" 2>/dev/null || echo "unknown") 
GAR_RESULT=$(tail -1 "$GAR_LOG" 2>/dev/null || echo "unknown")

# Count successes
SUCCESSES=0
[[ "$DOCKER_HUB_RESULT" == "success" ]] && ((SUCCESSES++))
[[ "$AWS_ECR_RESULT" == "success" ]] && ((SUCCESSES++))
[[ "$GAR_RESULT" == "success" ]] && ((SUCCESSES++))

# Generate summary
cat > multi-registry-push-results.json << EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "image_tag": "$IMAGE_TAG",
  "registries": {
    "docker-hub": {
      "status": "$DOCKER_HUB_RESULT"
    },
    "aws-ecr": {
      "status": "$AWS_ECR_RESULT"
    },
    "google-artifact-registry": {
      "status": "$GAR_RESULT"
    }
  },
  "summary": {
    "total_registries": 3,
    "successful": $SUCCESSES,
    "success_rate": "$((SUCCESSES * 100 / 3))%"
  }
}
EOF

echo ""
log "Multi-registry push complete:"
log "  Docker Hub: $DOCKER_HUB_RESULT"
log "  AWS ECR: $AWS_ECR_RESULT"
log "  Google Artifact Registry: $GAR_RESULT"
log "  Success rate: $((SUCCESSES * 100 / 3))% ($SUCCESSES/3)"
echo ""

# Display results
cat multi-registry-push-results.json | jq .

# Exit with error if all failed
if [[ $SUCCESSES -eq 0 ]]; then
  fail "All registry pushes failed"
elif [[ $SUCCESSES -lt 3 ]]; then
  log "Warning: Some registries failed, but at least one succeeded"
  exit 0
else
  pass "All registries pushed successfully"
  exit 0
fi
