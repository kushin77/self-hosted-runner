#!/bin/bash
# scripts/airgap/manifest_generator.sh
# Generates a JSON manifest of all required images for air-gapped environment.

set -e

MANIFEST_FILE="airgap_manifest.json"
OUTPUT_DIR="airgap_artifacts"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Default Image List (Base Runner + Dependencies)
IMAGES=(
  "ghcr.io/actions/actions-runner:latest"
  "ghcr.io/actions/actions-runner-controller:latest"
  "registry:2"
)

echo "Generating Air-Gap Manifest: $MANIFEST_FILE"

cat <<EOF > "$MANIFEST_FILE"
{
  "version": "1.0.0",
  "generated_at": "$TIMESTAMP",
  "images": [
EOF

for i in "${!IMAGES[@]}"; do
  IMAGE="${IMAGES[$i]}"
  echo " - $IMAGE"
  if [ $i -eq $(( ${#IMAGES[@]} - 1 )) ]; then
    echo "    \"$IMAGE\"" >> "$MANIFEST_FILE"
  else
    echo "    \"$IMAGE\"," >> "$MANIFEST_FILE"
  fi
done

cat <<EOF >> "$MANIFEST_FILE"
  ]
}
EOF

echo "Done. Created $MANIFEST_FILE"
chmod +x "$MANIFEST_FILE"
