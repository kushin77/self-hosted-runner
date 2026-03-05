#!/usr/bin/env bash
##
## Build Executor
## Runs build jobs in sandboxed containers with security isolation.
##
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${PROJECT_ROOT}/runner/runner-config.yaml"

JOB_ID="${1:-unknown}"
BUILD_CONTEXT="${2:-.}"
DOCKERFILE="${3:-Dockerfile}"

# Sandbox isolation using Docker
SANDBOX_NAME="build-${JOB_ID}-$(date +%s)"
SANDBOX_IMAGE="$(cat /etc/hostname)-runner:latest"

echo "Build Executor: ${JOB_ID}"
echo "Sandbox: ${SANDBOX_NAME}"

# Clean workspace at start
cleanup_workspace() {
  echo "Cleaning workspace..."
  docker rm -f "${SANDBOX_NAME}" 2>/dev/null || true
  rm -rf "/tmp/${JOB_ID}"
}

trap cleanup_workspace EXIT

# Create ephemeral workspace
mkdir -p "/tmp/${JOB_ID}"
cd "${BUILD_CONTEXT}"

# Build in sandboxed container
echo "Building in sandbox (${SANDBOX_IMAGE})..."
docker run \
  --rm \
  --name="${SANDBOX_NAME}" \
  --network=none \
  --user=builder:builder \
  --tmpfs /tmp:noexec,nosuid,nodev \
  --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  --security-opt="no-new-privileges:true" \
  -v "$(pwd):/workspace:ro" \
  -v "/tmp/${JOB_ID}:/output:rw" \
  -e "JOB_ID=${JOB_ID}" \
  -e "CI=true" \
  "${SANDBOX_IMAGE}" \
  bash -c "
    cd /workspace
    docker build -f ${DOCKERFILE} -t build-${JOB_ID}:latest . && \
    docker save build-${JOB_ID}:latest > /output/image.tar
  "

# SBOM generation
echo "Generating SBOM..."
syft "/tmp/${JOB_ID}/image.tar" -o json > "/tmp/${JOB_ID}/sbom.json"

# Sign artifacts
echo "Signing artifacts..."
cosign sign-blob \
  --key "${COSIGN_KEY}" \
  "/tmp/${JOB_ID}/image.tar" > "/tmp/${JOB_ID}/image.tar.sig"

echo "✓ Build completed"
echo "Output: /tmp/${JOB_ID}/"
