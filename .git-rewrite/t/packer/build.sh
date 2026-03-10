#!/usr/bin/env bash
set -euo pipefail

# Packer Build: Immutable Runner Image (Golden AMI)
# Creates content-addressable, signed runner artifacts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKR_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "v1.0.0")
BUILD_ID="$(date +%s)"

packer build \
  -var "runner_version=${PKR_VERSION}" \
  -var "build_id=${BUILD_ID}" \
  -var "timestamp=$(date +%Y%m%d-%H%M%S)" \
  -on-error=ask \
  "${SCRIPT_DIR}/runner-image.pkr.hcl"

echo "✅ Golden AMI built successfully"
echo "Version: ${PKR_VERSION}"
echo "Build ID: ${BUILD_ID}"
