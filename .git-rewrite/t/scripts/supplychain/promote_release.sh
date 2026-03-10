#!/usr/bin/env bash
set -euo pipefail

# Promote images from manifest to target registry. This is a safe placeholder
# that tags and pushes images to $TARGET_REGISTRY. Requires docker login or
# DOCKER_USERNAME/DOCKER_PASSWORD env vars to be configured in the runner.
# Usage: promote_release.sh manifest.yml TARGET_REGISTRY

MANIFEST=${1:-/tmp/airgap-manifest.yml}
TARGET_REGISTRY=${2:-${TARGET_REGISTRY:-}}

if [ -z "$TARGET_REGISTRY" ]; then
  echo "Target registry must be provided as second arg or TARGET_REGISTRY env" >&2
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

images=$(grep -E "^\s*image:\s*" -h "$MANIFEST" | sed -E 's/^[[:space:]]*image:[[:space:]]*//')

for img in $images; do
  echo "Promoting $img -> $TARGET_REGISTRY/$img"
  docker pull "$img"
  docker tag "$img" "$TARGET_REGISTRY/$img"
  docker push "$TARGET_REGISTRY/$img"
done

echo "Promotion completed to $TARGET_REGISTRY"
