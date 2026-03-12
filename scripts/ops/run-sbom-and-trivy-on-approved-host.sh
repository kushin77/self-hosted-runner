#!/usr/bin/env bash
set -euo pipefail

# Run this on the approved host (e.g., 192.168.168.42) with Docker available.
# Usage: ./scripts/ops/run-sbom-and-trivy-on-approved-host.sh image_name gs://sbom-bucket/path

IMAGE=${1:-}
DEST=${2:-}
if [ -z "$IMAGE" ] || [ -z "$DEST" ]; then
  echo "Usage: $0 <image:tag> <gs://bucket/path>" >&2
  exit 2
fi

TMP=$(mktemp -d)
pushd "$TMP" >/dev/null

echo "Generating SBOM (syft)..."
if ! syft "$IMAGE" -o json > sbom-${IMAGE//[:/]-}.json; then
  echo "syft failed" >&2
  popd >/dev/null
  exit 1
fi

echo "Generating CycloneDX SBOM..."
if ! syft "$IMAGE" -o cyclonedx-json > sbom-${IMAGE//[:/]-}.cyclonedx.json; then
  echo "syft cyclonedx failed" >&2
  popd >/dev/null
  exit 1
fi

echo "Running trivy scan (JSON)..."
if ! trivy image --quiet --format json -o trivy-${IMAGE//[:/]-}.json "$IMAGE"; then
  echo "trivy scan reported findings (exit code non-zero). Check output." >&2
  # still upload results for auditing
fi

echo "Uploading results to $DEST"
# Ensure gsutil authenticated; destination should exist or be creatable by CI account
gsutil cp sbom-* trivy-* "$DEST/"

popd >/dev/null
rm -rf "$TMP"

echo "SBOM and trivy results uploaded to $DEST"