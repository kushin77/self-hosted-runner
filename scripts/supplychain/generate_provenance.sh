#!/usr/bin/env bash
set -euo pipefail

mkdir -p build/provenance

PROV_FILE=build/provenance/sample-provenance.json

cat > "$PROV_FILE" <<EOF
{
  "provenance": {
    "builder": "sample-ci",
    "buildType": "example/build",
    "source": {
      "type": "git",
      "url": "https://github.com/example/repo",
      "commit": "0000000000000000000000000000000000000000"
    }
  }
}
EOF

echo "✓ Provenance generated: $PROV_FILE"
#!/usr/bin/env bash
set -euo pipefail

# Generate a simple SLSA-like provenance JSON for each image listed in manifest.
# Optionally attest (sign) the provenance using cosign if COSIGN_KEY is provided.
# Usage: ./generate_provenance.sh manifest.yml sbom-dir out-dir [--sign]

MANIFEST=${1:-deploy/airgap/manifest.yml}
SBOM_DIR=${2:-build/sboms}
OUT_DIR=${3:-build/provenance}
SIGN=${4:-}

mkdir -p "$OUT_DIR"

if [ ! -f "$MANIFEST" ]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

images=$(grep -E "^\s*image:\s*" -h "$MANIFEST" | sed -E 's/^[[:space:]]*image:[[:space:]]*//')

for img in $images; do
  safe=$(echo "$img" | sed -E 's/[:\/]//g' | sed -E 's/\s+/_/g')
  sbom_file="$SBOM_DIR/${safe}.json"
  prov_file="$OUT_DIR/${safe}-provenance.json"

  started_on=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  finished_on=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  cat > "$prov_file" <<JSON
{
  "_type": "https://slsa.dev/provenance/v1",
  "subject": [{ "name": "$img" }],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "builder": { "id": "self-hosted-runner/airgap-scripts" },
    "buildType": "https://example.com/airgap/generate-provenance",
    "invocation": { "command": "./scripts/supplychain/generate_provenance.sh $MANIFEST $SBOM_DIR $OUT_DIR" },
    "metadata": { "startedOn": "$started_on", "finishedOn": "$finished_on" },
    "materials": []
  }
}
JSON

  # attach SBOM reference if present
  if [ -f "$sbom_file" ]; then
    jq --arg sbom "${sbom_file}" '.predicate.materials += [{"uri":$sbom}]' "$prov_file" > "$prov_file.tmp" && mv "$prov_file.tmp" "$prov_file"
  fi

  echo "Wrote provenance: $prov_file"

  if [ "$SIGN" = "--sign" ] || [ -n "${COSIGN_KEY:-}" ]; then
    if ! command -v cosign >/dev/null 2>&1; then
      echo "cosign not found in PATH; cannot attest" >&2
      continue
    fi
    # If COSIGN_KEY env is set (base64 encoded), write it to a temp key file
    keyfile=""
    if [ -n "${COSIGN_KEY:-}" ]; then
      keyfile="/tmp/cosign.key"
      echo "$COSIGN_KEY" | base64 -d > "$keyfile"
      chmod 600 "$keyfile"
    fi

    echo "Creating cosign attestation for $img"
    predicate_file="$prov_file"
    # cosign attest expects an image reference and a predicate file
    # Use keyfile if available, otherwise expect cosign to be configured
    if [ -n "$keyfile" ]; then
      cosign attest --key "$keyfile" --predicate "$predicate_file" "$img" || echo "attest failed for $img"
    else
      cosign attest --predicate "$predicate_file" "$img" || echo "attest failed for $img"
    fi
  fi

done

echo "Provenance generation completed. Files in $OUT_DIR"
