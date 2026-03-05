#!/usr/bin/env bash
##
## Generate SBOM (Software Bill of Materials)
## Creates SPDX and CycloneDX SBOMs for all artifacts.
##
set -euo pipefail

ARTIFACT="${1:-.}"
OUTPUT_DIR="${2:-./sbom}"
JOB_ID="${3:-unknown}"

mkdir -p "${OUTPUT_DIR}"

echo "Generating SBOM for: ${ARTIFACT}"

# Check for Syft (preferred)
if command -v syft &>/dev/null; then
  echo "Using Syft for SBOM generation..."
  
  # SPDX format
  syft "${ARTIFACT}" \
    -o spdx-json \
    > "${OUTPUT_DIR}/sbom-spdx.json"
  
  # CycloneDX format
  syft "${ARTIFACT}" \
    -o cyclonedx-json \
    > "${OUTPUT_DIR}/sbom-cyclonedx.json"
else
  echo "Syft not found, installing..."
  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
  
  syft "${ARTIFACT}" \
    -o spdx-json \
    > "${OUTPUT_DIR}/sbom-spdx.json"
  
  syft "${ARTIFACT}" \
    -o cyclonedx-json \
    > "${OUTPUT_DIR}/sbom-cyclonedx.json"
fi

# Add metadata
cat > "${OUTPUT_DIR}/sbom-metadata.json" <<EOF
{
  "generated": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "artifact": "${ARTIFACT}",
  "jobId": "${JOB_ID}",
  "generatorVersion": "$(syft --version | awk '{print $NF}')"
}
EOF

# Validate SBOM
echo "Validating SBOM..."
if jq empty "${OUTPUT_DIR}/sbom-spdx.json" 2>/dev/null; then
  echo "✓ SBOM valid"
else
  echo "✗ SBOM validation failed"
  exit 1
fi

# Sign SBOM
if [ -n "${COSIGN_KEY:-}" ]; then
  echo "Signing SBOM..."
  cosign sign-blob \
    --key "${COSIGN_KEY}" \
    "${OUTPUT_DIR}/sbom-spdx.json" \
    > "${OUTPUT_DIR}/sbom-spdx.json.sig"
fi

# Print summary
echo "SBOM Summary:"
jq '.components | length' "${OUTPUT_DIR}/sbom-spdx.json"

echo "✓ SBOM generation completed"
echo "Output: ${OUTPUT_DIR}/"
