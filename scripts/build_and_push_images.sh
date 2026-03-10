#!/usr/bin/env bash
set -euo pipefail

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