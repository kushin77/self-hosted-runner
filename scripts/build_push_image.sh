#!/usr/bin/env bash
set -euo pipefail

# Build and push portal-backend image to GCP
# Requires: gcloud authenticated (gcloud auth login or service account), Docker

PROJECT=${1:-nexusshield-prod}
IMAGE_NAME=${2:-portal-backend}
TAG=${3:-latest}

FULL_IMAGE=gcr.io/${PROJECT}/${IMAGE_NAME}:${TAG}

echo "Building image ${FULL_IMAGE}..."
docker build -t "${FULL_IMAGE}" .

echo "Configuring Docker auth for gcr..."
gcloud auth configure-docker --quiet

echo "Pushing ${FULL_IMAGE}..."
docker push "${FULL_IMAGE}"

echo "Image pushed: ${FULL_IMAGE}"