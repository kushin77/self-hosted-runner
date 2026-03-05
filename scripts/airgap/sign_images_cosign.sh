#!/usr/bin/env bash
set -euo pipefail

# Sign images using cosign. Requires cosign binary and a private key file.
# Usage: ./sign_images_cosign.sh manifest-with-digests.yml /path/to/cosign.key

MANIFEST=${1:-/dev/stdin}
KEY_FILE=${2:-${COSIGN_KEY_FILE:-}}

if [ -z "$KEY_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  echo "Provide cosign key file as second argument or set COSIGN_KEY_FILE env var" >&2
  exit 1
fi

images=$(grep -E "^\s*image:\s*" -h "$MANIFEST" | sed -E 's/^[[:space:]]*image:[[:space:]]*//')

for img in $images; do
  echo "Signing $img"
  cosign sign --key "$KEY_FILE" "$img"
done

echo "Signed $(echo "$images" | wc -w) images"
