#!/usr/bin/env bash
set -euo pipefail

TARGET_BUILD_HOST="${TARGET_BUILD_HOST:-192.168.168.42}"
CURRENT_HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

if [[ "$CURRENT_HOST_IP" != "$TARGET_BUILD_HOST" ]]; then
  echo "[FATAL] ONPREM build mandate violation: current host ${CURRENT_HOST_IP:-unknown}, required ${TARGET_BUILD_HOST}" >&2
  exit 42
fi

if [[ -n "${BUILD_ID:-}" || -n "${CLOUD_BUILD:-}" || -n "${K_SERVICE:-}" || -n "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
  echo "[FATAL] Cloud runtime detected. NO BUILDING IN CLOUD is mandatory." >&2
  exit 42
fi

# Idempotent build-and-push script for canonical secrets images.
# Requires: DOCKER_REGISTRY (e.g. registry.example.com/org) and optionally IMAGE_TAG/PORTAL_IMAGE_TAG

REGISTRY=${DOCKER_REGISTRY:-}
IMAGE_TAG=${IMAGE_TAG:-$(date +%Y%m%d%H%M%S)}
PORTAL_IMAGE_TAG=${PORTAL_IMAGE_TAG:-$IMAGE_TAG}

if [ -z "$REGISTRY" ]; then
  echo "DOCKER_REGISTRY not set. Building local images only. Set DOCKER_REGISTRY to push." >&2
  BUILD_ONLY=1
else
  BUILD_ONLY=0
fi

echo "Building backend image..."
docker build -f backend/Dockerfile -t ${REGISTRY:+$REGISTRY/}canonical-secrets-api:$IMAGE_TAG .

if [ "$BUILD_ONLY" -eq 0 ]; then
  echo "Pushing backend image to $REGISTRY..."
  docker push $REGISTRY/canonical-secrets-api:$IMAGE_TAG
fi

echo "Note: portal image build is out-of-scope. Ensure portal image exists as $REGISTRY/secrets-portal:$PORTAL_IMAGE_TAG"

echo "Build complete. IMAGE_TAG=$IMAGE_TAG"