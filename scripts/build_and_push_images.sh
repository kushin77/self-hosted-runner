#!/usr/bin/env bash
set -euo pipefail

TARGET_BUILD_HOST="${TARGET_BUILD_HOST:-192.168.168.42}"
CURRENT_HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

if [[ "$CURRENT_HOST_IP" != "$TARGET_BUILD_HOST" ]]; then
  echo "[FATAL] ONPREM build mandate violation: current host ${CURRENT_HOST_IP:-unknown}, required ${TARGET_BUILD_HOST}" >&2
  exit 42
fi

# Block execution from managed CI/cloud runtimes to keep builds strictly on-prem.
if [[ -n "${BUILD_ID:-}" || -n "${CLOUD_BUILD:-}" || -n "${K_SERVICE:-}" || -n "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
  echo "[FATAL] Cloud runtime detected. NO BUILDING IN CLOUD is mandatory." >&2
  exit 42
fi

# Usage: ./scripts/build_and_push_images.sh <tag>
TAG=${1:-latest}
PROJECT=nexusshield-prod
REPO=us-central1-docker.pkg.dev/${PROJECT}/production-portal-docker

echo "Building backend image..."
docker build -f backend/Dockerfile.prod -t ${REPO}/nexus-shield-portal-backend:${TAG} backend/

echo "Building frontend image..."
docker build -f frontend/Dockerfile -t ${REPO}/nexus-shield-portal-frontend:${TAG} frontend/

echo "Configuring docker for Artifact Registry"
gcloud auth configure-docker us-central1-docker.pkg.dev --quiet

echo "Pushing backend image..."
docker push ${REPO}/nexus-shield-portal-backend:${TAG}

echo "Pushing frontend image..."
docker push ${REPO}/nexus-shield-portal-frontend:${TAG}

echo "Updating Cloud Run services to use new images"
# Update Cloud Run services (no traffic shift — replace image)
gcloud run deploy nexus-shield-portal-backend \
  --image=${REPO}/nexus-shield-portal-backend:${TAG} --region=us-central1 --project=${PROJECT} --platform=managed --no-traffic --quiet || true

gcloud run deploy nexus-shield-portal-frontend \
  --image=${REPO}/nexus-shield-portal-frontend:${TAG} --region=us-central1 --project=${PROJECT} --platform=managed --no-traffic --quiet || true

echo "Build and push complete. To promote images, adjust Cloud Run traffic or re-deploy with desired flags."