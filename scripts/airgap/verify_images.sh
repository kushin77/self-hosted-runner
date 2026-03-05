#!/usr/bin/env bash
set -euo pipefail

# Verify images exist in a registry by attempting docker pull.
# Usage: ./verify_images.sh <registry> <manifest.yml>

REGISTRY=${1:?Please provide target registry (e.g. my-registry.local:5000)}
MANIFEST=${2:-deploy/airgap/manifest.yml}

if [ ! -f "$MANIFEST" ]; then
  echo "Manifest not found: $MANIFEST"
  exit 1
fi

images=$(grep -E "^\s*image:\s*" -h "$MANIFEST" | sed -E 's/^[[:space:]]*image:[[:space:]]*//')

failed=0
for img in $images; do
  target="$REGISTRY/$img"
  echo -n "Checking $target ... "
  if docker pull "$target" >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL"
    failed=$((failed+1))
  fi
done

if [ $failed -ne 0 ]; then
  echo "$failed images failed to pull from $REGISTRY"
  exit 2
fi

echo "All images verified in $REGISTRY"
