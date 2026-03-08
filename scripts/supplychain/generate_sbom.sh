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
 
