#!/usr/bin/env bash
set -euo pipefail

mkdir -p build/sboms

SBOM_FILE=build/sboms/sample-sbom.json

cat > "$SBOM_FILE" <<EOF
{
  "sbom": {
    "name": "sample-artifact",
    "version": "0.0.1",
    "components": [
      {"name": "libexample", "version": "1.2.3", "purl": "pkg:generic/libexample@1.2.3"}
    ]
  }
}
EOF

echo "✓ SBOM generated: $SBOM_FILE"
#!/usr/bin/env bash
set -euo pipefail

# Generate SBOMs for images listed in the manifest using Syft.
# Usage: ./generate_sbom.sh manifest.yml output-dir

MANIFEST=${1:-deploy/airgap/manifest.yml}
OUTDIR=${2:-build/sboms}
mkdir -p "$OUTDIR"

if [ ! -f "$MANIFEST" ]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

images=$(grep -E "^\s*image:\s*" -h "$MANIFEST" | sed -E 's/^[[:space:]]*image:[[:space:]]*//')

if ! command -v syft >/dev/null 2>&1; then
  echo "syft not found in PATH. Please install syft: https://github.com/anchore/syft" >&2
  exit 2
fi

for img in $images; do
  safe=$(echo "$img" | sed -E 's/[:\/]/_/g')
  out="$OUTDIR/${safe}.json"
  echo "Generating SBOM for $img -> $out"
  syft "$img" -o json > "$out"
done

echo "SBOM generation complete. Files in $OUTDIR"
