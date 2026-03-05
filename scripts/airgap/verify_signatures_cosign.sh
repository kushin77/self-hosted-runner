#!/usr/bin/env bash
set -euo pipefail

# Verify cosign signatures for images using a public key file.
# Usage: ./verify_signatures_cosign.sh manifest-with-digests.yml /path/to/cosign.pub

MANIFEST=${1:-/dev/stdin}
PUB_KEY=${2:-${COSIGN_PUB_KEY_FILE:-}}

if [ -z "$PUB_KEY" ] || [ ! -f "$PUB_KEY" ]; then
  echo "Provide cosign public key file as second argument or set COSIGN_PUB_KEY_FILE env var" >&2
  exit 1
fi

images=$(grep -E "^\s*image:\s*" -h "$MANIFEST" | sed -E 's/^[[:space:]]*image:[[:space:]]*//')

failed=0
for img in $images; do
  echo -n "Verifying $img ... "
  if cosign verify --key "$PUB_KEY" "$img" >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL"
    failed=$((failed+1))
  fi
done

if [ $failed -ne 0 ]; then
  echo "$failed images failed signature verification" >&2
  exit 2
fi

echo "All images verified with cosign public key"
