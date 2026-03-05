#!/usr/bin/env bash
set -euo pipefail

# Generate a manifest with image digests (sha256) for images listed in a manifest.
# Usage: ./generate_manifest_checksums.sh [in-manifest.yml] [out-manifest.yml]

IN_MANIFEST=${1:-deploy/airgap/manifest.yml}
OUT_MANIFEST=${2:-/dev/stdout}

if [ ! -f "$IN_MANIFEST" ]; then
  echo "Input manifest not found: $IN_MANIFEST" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "images:" > "$OUT_MANIFEST"

images=$(grep -E "^\s*image:\s*" -h "$IN_MANIFEST" | sed -E 's/^[[:space:]]*image:[[:space:]]*//')

for img in $images; do
  echo "Processing $img" >&2
  docker pull "$img" >/dev/null 2>&1 || true
  # Try to get RepoDigest from docker inspect
  repo_digest=$(docker inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$img" 2>/dev/null | head -n1 || true)
  if [ -z "$repo_digest" ]; then
    # Fallback: try to get digest via manifest inspect (if available)
    digest=$(docker image inspect --format='{{index .RepoDigests 0}}' "$img" 2>/dev/null || true)
    repo_digest=${digest}
  fi
  # normalize digest (extract sha256:...)
  checksum=""
  if [[ "$repo_digest" =~ @(.+) ]]; then
    checksum=${BASH_REMATCH[1]}
  else
    # as last resort, leave empty
    checksum=""
  fi

  cat >> "$OUT_MANIFEST" <<YAML
  - image: $img
    digest: "$checksum"
YAML
done

echo "Wrote checksummed manifest to $OUT_MANIFEST" >&2
