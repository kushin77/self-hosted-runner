#!/usr/bin/env bash
set -euo pipefail

echo "🔎 Verifying release gate artifacts..."

SBOM_FILE=build/sboms/sample-sbom.json
PROV_FILE=build/provenance/sample-provenance.json

MISSING=0

if [ ! -f "$SBOM_FILE" ]; then
  echo "✖ SBOM missing: $SBOM_FILE"
  MISSING=1
else
  echo "✓ SBOM present"
fi

if [ ! -f "$PROV_FILE" ]; then
  echo "✖ Provenance missing: $PROV_FILE"
  MISSING=1
else
  echo "✓ Provenance present"
fi

if [ $MISSING -eq 1 ]; then
  echo "⚠️  Release gate validation FAILED"
  exit 2
fi

echo "✅ Release gate validation PASSED"
exit 0
#!/usr/bin/env bash
set -euo pipefail

# Verify release gate: ensure SBOMs and provenance exist for images in manifest,
# and optionally verify image signatures using cosign public key.
# Usage: verify_release_gate.sh manifest.yml sbom-dir provenance-dir

MANIFEST=${1:-/tmp/airgap-manifest.yml}
SBOM_DIR=${2:-build/sboms}
PROV_DIR=${3:-build/provenance}

if [ ! -f "$MANIFEST" ]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

missing=0
images=$(grep -E "^\s*image:\s*" -h "$MANIFEST" | sed -E 's/^[[:space:]]*image:[[:space:]]*//')

for img in $images; do
  safe=$(echo "$img" | sed -E 's/[:\/]//g' | sed -E 's/\s+/_/g')
  sbom="$SBOM_DIR/${safe}.json"
  prov="$PROV_DIR/${safe}-provenance.json"

  if [ ! -f "$sbom" ]; then
    echo "Missing SBOM for $img: $sbom" >&2
    missing=$((missing+1))
  else
    echo "Found SBOM: $sbom"
  fi

  if [ ! -f "$prov" ]; then
    echo "Missing provenance for $img: $prov" >&2
    missing=$((missing+1))
  else
    echo "Found provenance: $prov"
  fi

  # If COSIGN_PUB_KEY is provided (base64), verify the image signature
  if [ -n "${COSIGN_PUB_KEY:-}" ]; then
    if ! command -v cosign >/dev/null 2>&1; then
      echo "cosign not installed; cannot verify signatures" >&2
      missing=$((missing+1))
    else
      echo "Verifying cosign signature for $img"
      echo "$COSIGN_PUB_KEY" | base64 -d > /tmp/cosign.pub
      chmod 644 /tmp/cosign.pub
      if cosign verify --key /tmp/cosign.pub "$img" >/dev/null 2>&1; then
        echo "Signature verified for $img"
      else
        echo "Signature verification FAILED for $img" >&2
        missing=$((missing+1))
      fi
    fi
  fi

done

if [ $missing -ne 0 ]; then
  echo "$missing checks failed; release gate not satisfied" >&2
  exit 2
fi

echo "All release gate checks passed"
exit 0
