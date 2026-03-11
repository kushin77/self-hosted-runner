#!/usr/bin/env bash
set -euo pipefail

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